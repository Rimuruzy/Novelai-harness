import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';

import '../models/image_palette.dart';

/// 图片主色盘提取服务 (调色盘单一事实源)
///
/// 采用 MD3 官方取色算法 (与 Android 12+ 取壁纸色同源)：
/// Wu+Wsmeans (Celebi) K-Means 聚类量化 → Score 按适宜度打分排序。
/// 量化在后台 Isolate 执行，解码后先降采样到最长边 128px，大图零卡顿。
class PaletteService {
  PaletteService._();

  /// 全局唯一实例
  static final PaletteService instance = PaletteService._();

  /// 参与量化的最长边 (降采样后)；128² 量级已足够稳定提取主色
  static const int _kSampleLongestSide = 128;

  /// 聚类簇数上限
  static const int _kMaxColors = 24;

  /// Score 输出的推荐主色数
  static const int _kDesired = 8;

  /// 结果 LRU 缓存上限 (按调用方提供的 cacheKey)
  static const int _kCacheLimit = 24;

  final Map<String, ImagePalette> _cache = <String, ImagePalette>{};

  /// 提取图片主色盘；解码失败或图片为空返回 null。
  ///
  /// [cacheKey] 传图片唯一标识 (如 image.id) 时启用 LRU 缓存，
  /// 同一张图重复查看调色盘/自适应取色零开销。
  Future<ImagePalette?> extract(Uint8List bytes, {String? cacheKey}) async {
    if (cacheKey != null) {
      final cached = _cache[cacheKey];
      if (cached != null) return cached;
    }
    if (bytes.isEmpty) return null;

    final ImagePalette? palette = await Isolate.run(
      () => _extract(bytes, _kSampleLongestSide, _kMaxColors, _kDesired),
    ).catchError((_) => null);

    if (palette != null && cacheKey != null) {
      if (_cache.length >= _kCacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      _cache[cacheKey] = palette;
    }
    return palette;
  }

  /// 提取实现 (只在后台 Isolate 内执行；Celebi 量化为异步 API)
  static Future<ImagePalette?> _extract(
    Uint8List bytes,
    int sampleLongestSide,
    int maxColors,
    int desired,
  ) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }

    // 降采样：最长边压到 sampleLongestSide，保持纵横比
    var image = decoded;
    final longest = image.width >= image.height ? image.width : image.height;
    if (longest > sampleLongestSide) {
      final scale = sampleLongestSide / longest;
      final targetW = (image.width * scale).round().clamp(1, sampleLongestSide);
      final targetH = (image.height * scale).round().clamp(
        1,
        sampleLongestSide,
      );
      image = img.copyResize(image, width: targetW, height: targetH);
    }

    // 像素集 → 0xAARRGGBB (image 包像素通道为 num，需显式取整)
    final pixels = <int>[];
    for (final pixel in image) {
      final a = pixel.a.toInt();
      // 透明像素不参与取色，避免透明通道拉出水色簇
      if (a == 0) continue;
      pixels.add(
        (a << 24) |
            (pixel.r.toInt() << 16) |
            (pixel.g.toInt() << 8) |
            pixel.b.toInt(),
      );
    }
    if (pixels.isEmpty) return null;

    final quantized = await QuantizerCelebi().quantize(pixels, maxColors);
    final clusterCounts = quantized.colorToCount;
    if (clusterCounts.isEmpty) return null;

    final total = clusterCounts.values.reduce((a, b) => a + b);
    if (total <= 0) return null;

    final scored = Score.score(clusterCounts, desired: desired);
    if (scored.isEmpty) return null;

    final colors = [
      for (final argb in scored)
        PaletteColor(argb: argb, share: (clusterCounts[argb] ?? 0) / total),
    ];
    return ImagePalette(seed: scored.first, colors: colors);
  }
}
