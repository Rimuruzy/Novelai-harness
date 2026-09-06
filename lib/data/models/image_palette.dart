import 'dart:ui' show Color;

/// 图片主色盘提取结果 (纯 Dart 数据模型，不依赖 Flutter)
///
/// 由 [PaletteService] 基于 MD3 官方算法 (QuantizerCelebi + Score) 提取，
/// 色值统一使用 0xAARRGGBB 整型，UI 层按需 `Color(value)` 转换。
class ImagePalette {
  /// 主种子色 (Score 排序第一名，可直接作为 MD3 DynamicScheme 种子)
  final int seed;

  /// 按适宜度降序的主色列表 (含占比)
  final List<PaletteColor> colors;

  const ImagePalette({required this.seed, required this.colors});

  bool get isEmpty => colors.isEmpty;

  /// UI 便捷转换：主色列表 → Color 集合
  List<Color> get colorValues =>
      colors.map((c) => Color(c.argb)).toList(growable: false);
}

/// 单个主色条目
class PaletteColor {
  /// 0xAARRGGBB 色值
  final int argb;

  /// 占比 (该簇像素数 / 参与量化的总像素数, 0~1)
  final double share;

  const PaletteColor({required this.argb, required this.share});
}

/// 主题强调色配置快照 (持久化在 AppConfig 中的运行时形态)
///
/// [seed] 为 null 表示回退默认 Notion 蓝主题。
class AccentThemeSnapshot {
  final Color? seed;
  final String variantId;

  const AccentThemeSnapshot({required this.seed, required this.variantId});
}
