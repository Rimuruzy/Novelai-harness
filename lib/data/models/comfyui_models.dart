/// ComfyUI 模式数据模型：PromptToolkit AI Bridge (HTTP) 的实体与快照。
///
/// Bridge 事实源：reference/PromptToolkit (custom_nodes) 的 `nodes/ai_bridge.py`，
/// 路由前缀 `/pt/ai/*`：
/// - PromptPanel 节点注册正向提示词 (`/pt/ai/prompt`)；
/// - ResolutionMasterPT 节点注册分辨率 (`/pt/ai/resolution`)；
/// - ParamsPanelPT 节点注册负向词与采样参数 (`/pt/ai/params`)；
/// - AIImageOutput 节点发布生成图片 (`/pt/ai/image/latest` / `raw`)。
library;

import 'dart:typed_data';

/// ComfyUI Bridge 连接状态 (供生成坞 / 参数页状态卡展示)
enum ComfyUiConnectionStatus { disconnected, connecting, connected }

/// AI Bridge 一次连接探测得到的节点注册快照 (各注册表的键即节点 id)。
class ComfyUiBridgeState {
  /// 已注册正向提示词的 PromptPanel 节点 id 列表
  final List<String> promptNodeIds;

  /// 已注册分辨率的 ResolutionMasterPT 节点 id 列表
  final List<String> resolutionNodeIds;

  /// 已注册采样参数的 ParamsPanelPT 节点 id 列表
  final List<String> paramsNodeIds;

  /// 目标 ComfyUI 服务地址 (来自配置，用于状态展示)
  final String baseUrl;

  const ComfyUiBridgeState({
    required this.promptNodeIds,
    required this.resolutionNodeIds,
    required this.paramsNodeIds,
    required this.baseUrl,
  });

  const ComfyUiBridgeState.empty(String baseUrl)
    : this(
        promptNodeIds: const [],
        resolutionNodeIds: const [],
        paramsNodeIds: const [],
        baseUrl: baseUrl,
      );

  /// 是否具备驱动一次 ComfyUI 生图的最低条件 (至少一个提示词面板)
  bool get canDrive => promptNodeIds.isNotEmpty;

  /// 从三条注册表路由的 JSON 响应组装 (外层 key: prompts/resolutions/params)。
  /// /pt/ai/params 在旧版插件上可能 404，由调用方容错后传空 map。
  static ComfyUiBridgeState fromResponses({
    required Map<String, dynamic> prompts,
    required Map<String, dynamic> resolutions,
    required Map<String, dynamic> params,
    required String baseUrl,
  }) {
    List<String> idsOf(Map<String, dynamic> body, String key) =>
        (body[key] as Map<String, dynamic>? ?? const {})
            .keys
            .toList(growable: false);
    return ComfyUiBridgeState(
      promptNodeIds: idsOf(prompts, 'prompts'),
      resolutionNodeIds: idsOf(resolutions, 'resolutions'),
      paramsNodeIds: idsOf(params, 'params'),
      baseUrl: baseUrl,
    );
  }
}

/// ParamsPanelPT 的一次参数下发补丁 (字段为 null 表示不修改该 widget)。
///
/// 字段名与插件端 `PARAMS_FIELDS` 一一对应，序列化时仅携带非空字段。
class ComfyUiParamsPatch {
  final String? negative;
  final int? steps;
  final double? cfg;
  final int? seed;
  final double? denoise;

  const ComfyUiParamsPatch({
    this.negative,
    this.steps,
    this.cfg,
    this.seed,
    this.denoise,
  });

  bool get isEmpty =>
      negative == null &&
      steps == null &&
      cfg == null &&
      seed == null &&
      denoise == null;

  Map<String, dynamic> toJson() => {
    if (negative != null) 'negative': negative,
    if (steps != null) 'steps': steps,
    if (cfg != null) 'cfg': cfg,
    if (seed != null) 'seed': seed,
    if (denoise != null) 'denoise': denoise,
  };
}

/// AIImageOutput 发布到 Bridge 的单张图片条目 (newest first 列表的元素)。
class ComfyUiBridgeImage {
  final String? nodeId;
  final String filename;

  /// 全分辨率 PNG 绝对路径 (ComfyUI 主机本地路径，仅同机可用)
  final String? absPath;

  /// ≤1024px JPEG 预览绝对路径 (同上)
  final String? previewPath;

  /// 发布时间戳 (秒，服务端 time.time())
  final double time;

  const ComfyUiBridgeImage({
    required this.nodeId,
    required this.filename,
    required this.absPath,
    required this.previewPath,
    required this.time,
  });

  static ComfyUiBridgeImage fromJson(Map<String, dynamic> json) {
    return ComfyUiBridgeImage(
      nodeId: json['node_id'] as String?,
      filename: json['filename'] as String? ?? '',
      absPath: json['abs_path'] as String?,
      previewPath: json['preview_path'] as String?,
      time: (json['time'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// ComfyUI 拉回的成品图 (全分辨率字节 + 来源信息)。
class ComfyUiGeneratedImage {
  final Uint8List bytes;
  final ComfyUiBridgeImage entry;

  const ComfyUiGeneratedImage({required this.bytes, required this.entry});
}

/// AI Bridge 通信异常 (连接失败 / HTTP 非 2xx / 响应结构异常)。
class ComfyUiBridgeException implements Exception {
  final String message;

  /// 是否为「连不上服务」类错误 (用于 UI 区分地址错误与协议错误)
  final bool isConnectionError;

  const ComfyUiBridgeException(this.message, {this.isConnectionError = false});

  @override
  String toString() => message;
}
