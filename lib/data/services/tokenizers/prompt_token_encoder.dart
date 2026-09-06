/// 提示词 token 分词器抽象 (同步计数：BPE/SentencePiece 对短文本均为毫秒级)。
///
/// 实现对齐 NovelAI 官网前端：
/// - V4 / V4.5：T5 SentencePiece ([T5PromptTokenEncoder])；
/// - V5：Qwen 3.5 byte-level BPE ([QwenPromptTokenEncoder])；
/// - V3 及更早：CLIP，本仓库无词表资产，由计数服务回退启发式估算。
library;

abstract interface class PromptTokenEncoder {
  /// 统计文本 token 数 (空文本返回 0)。
  int countTokens(String text);
}
