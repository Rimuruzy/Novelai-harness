# LLM 提示缓存

## 请求策略

模型设置中的 `cacheConfig` 由 `LlmModelConfig` 持久化，经 Studio Harness 装配注入 `OpenAiCompatibleProvider`，由 `PromptCachePolicy` 构建缓存字段；只用于 Chat Completions，不把 Anthropic / Responses 原生协议混入该策略。

实现依据为本地 `reference/pi/packages/ai/src/api/openai-completions.ts`、`openai-prompt-cache.ts` 及对应的 `openai-completions-prompt-cache.test.ts` / `openai-completions-cache-control-format.test.ts`。

- 自动：OpenAI 官方域名发送稳定的会话级 `prompt_cache_key`（最多 64 个 Unicode 码点）；OpenRouter 的 `anthropic/` 模型发送 Anthropic 标记。未知中转站不猜缓存格式，不因模型名为 GPT/Claude/Gemini 就注入供应商字段。
- OpenAI：显式声明代理兼容，发送会话键。用户选择延长时增加 `prompt_cache_retention: "24h"`。
- Anthropic：在系统提示词的末尾文本块、最后一个工具定义、最后一条可标记的会话消息文本块添加 `cache_control: {type: "ephemeral"}`。用户选择延长时增加 `ttl: "1h"`。不标记图片块，不修改原始会话或工具注册表。
- 不发送缓存提示：只停止客户端提示字段及亲和头，不能关闭服务端隐式缓存。
- 会话亲和请求头默认不发送，支持显式 OpenAI（`session_id` / `x-client-request-id` / `x-session-affinity`）或 OpenRouter（`x-session-id`）格式。仅在网关明确支持时启用。
- 相比 pi 的部分兼容端点长缓存推断，本项目更保守：未知中转站必须显式选择格式才发长缓存字段。长保留时间可能改变计费，不默认开启。
- 对明确返回 HTTP 400 且拒绝缓存键/保留字段的端点逐项降级并重试；记录按完整端点、模型与字段隔离，最多重试两次。非法字段值/长度不会误记为不支持。

`cached_tokens: 0` 只表示上游报告零命中，不证明请求最优，也不证明服务端不支持缓存。客户端提示不能保证网关保留字段、维持账号/渠道路由、返回真实计费统计或提供折扣。缺字段则不能推断为零。

## 前缀稳定性与图片

系统提示词和工具列表在一次 send 的工具循环内保持不变，会话键来自 recorder.sessionId 而非每个请求的时间戳。图片遵守原有 imageEpoch 单次展示约束：下一次 send 将旧图替换为固定占位符。这个替换会改变从图片位置开始的前缀，不能声称完全不影响缓存；替换后占位符保持稳定。不得为提高命中率而重新发送全部历史图片。

## 用量口径

- 与 pi 一致：`input` 是未缓存输入，`cacheRead` / `cacheWrite` 是互斥输入类别。
- Chat Completions 缓存读取优先级：`prompt_tokens_details.cached_tokens` → `prompt_cache_hit_tokens` → 顶层 `cached_tokens`。零是有效读数；别名不相加。
- 缓存写入读取 `prompt_tokens_details.cache_write_tokens`；`input = max(0, prompt_tokens - cacheRead - cacheWrite)`。
- 顶层 `usage` 优先，缺失时读取 `choices[0].usage`。usage 事件是请求级累计快照，Harness 取最后一个，而非逐块相加。
- `completion_tokens` 已含 reasoning，不重复相加；不拿不一致的 `total_tokens` 差额猜测缓存。
- `cacheReadReported` 保留字段缺失与明确零的区别。聚合中只要有输入请求未报告，就不显示看似精确的命中率；有已知缓存读数时显示“部分报告”，否则显示“未报告”。
- 命中率 = `cacheRead / (input + cacheRead + cacheWrite)`，全缓存输入为 100%。

## 旧数据兼容

新用量 JSON 带 `inputAccounting: "exclusive"`，账本版本升级为 2。旧本应用 v1 账本及 `api: "openai-chat"` 会话曾把总输入存入 input：读取时减去已记录的缓存一次。新标记防止重复减去；外部 Pi 会话维持既有互斥口径，不做该迁移。原始 JSONL 不重写，旧账本只在下一次正常记账时按已有原子落盘流程保存。

旧日志没有原始 usage，因此无法恢复漏掉的缓存读写或判断历史零是否明确报告；不伪造历史命中。
