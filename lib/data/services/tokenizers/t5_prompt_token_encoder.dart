import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/services.dart';

import 'prompt_token_encoder.dart';

/// NovelAI V4 / V4.5 使用的 T5 分词器 (SentencePiece)。
///
/// 词表资产移植自 Aaalice_NAI_Launcher 参考实现 (官方 t5_spiece.model)，
/// 依赖包 dart_sentencepiece_tokenizer 纯 Dart 实现，桌面端可用。
class T5PromptTokenEncoder implements PromptTokenEncoder {
  T5PromptTokenEncoder._(this._tokenizer);

  /// 按资产路径缓存实例，词表解析只做一次。
  static final Map<String, Future<T5PromptTokenEncoder>> _instances =
      <String, Future<T5PromptTokenEncoder>>{};

  final SentencePieceTokenizer _tokenizer;

  static Future<T5PromptTokenEncoder> load({required String assetPath}) {
    return _instances.putIfAbsent(assetPath, () => _loadFromAsset(assetPath));
  }

  /// 用原始词表字节构造 (测试与离线校验使用，绕过 rootBundle)。
  static T5PromptTokenEncoder fromBytes(List<int> bytes) {
    final tokenizer = SentencePieceTokenizer.fromBytes(
      bytes,
      config: const SentencePieceConfig(),
    );
    return T5PromptTokenEncoder._(tokenizer);
  }

  static Future<T5PromptTokenEncoder> _loadFromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return fromBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  @override
  int countTokens(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return 0;
    }

    final encoding = _tokenizer.encode(normalized, addSpecialTokens: false);
    return encoding.ids.length;
  }
}
