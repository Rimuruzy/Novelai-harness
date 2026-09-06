import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/anysearch_models.dart';

/// AnySearch 官方 REST 服务 (https://api.anysearch.com)
///
/// 官方文档: https://www.anysearch.com/docs
/// - POST /v1/search        通用/垂直领域实时搜索
/// - GET  /v1/sub-domains   垂直领域能力目录 (子域 + 参数规格)
/// - POST /v1/extract       网页正文提取 (返回 Markdown)
///
/// 鉴权: Authorization: Bearer + API Key，可选；匿名访问可用但限流更低。
/// 响应统一信封 {"code": 0, "message": "success", "data": {...}}；
/// 错误时 code = -1，message 为原因，request_id 可选。
/// 匿名额度耗尽时响应可能携带 auto_registered 新 Key (不做自动保存，透传给用户决定)。
class AnySearchService {
  static final AnySearchService instance = AnySearchService._();

  AnySearchService._() : _client = http.Client();

  /// 测试或自定义部署用构造
  AnySearchService.forTesting({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client() {
    if (baseUrl != null) _baseUrl = baseUrl;
  }

  final http.Client _client;

  String _baseUrl = 'https://api.anysearch.com';

  String get baseUrl => _baseUrl;

  /// 允许运行时切换服务地址 (自建部署场景)
  set baseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) _baseUrl = trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  static const Duration _timeout = Duration(seconds: 35);

  /// 客户端标识 (官方 skill 用 "skill/3.1.1"，桌面端标识自己的来源)
  static const String _clientHeader = 'novelai-harness/1.0';

  Map<String, String> _buildHeaders(String? apiKey) => {
    'Content-Type': 'application/json',
    'X-Anysearch-Client': _clientHeader,
    if (apiKey != null && apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  /// 解析统一信封；code != 0 或 HTTP >= 400 抛 [AnySearchException]
  Map<String, dynamic> _parseEnvelope(http.Response resp) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not a json object');
      }
      body = decoded;
    } on FormatException {
      throw AnySearchException(
        '服务端返回了无法解析的响应 (HTTP ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }

    final code = (body['code'] as num?)?.toInt() ?? 0;
    if (resp.statusCode >= 400 || code != 0) {
      final requestId = body['request_id'] as String? ?? '';
      var message = body['message'] as String? ?? 'HTTP ${resp.statusCode}';
      // 匿名额度耗尽时服务端可能自动签发新 Key，透传给上层展示给用户
      String? autoKey;
      final auto = body['auto_registered'];
      if (auto is Map<String, dynamic>) {
        final key = auto['api_key'];
        if (key is String && key.isNotEmpty) {
          autoKey = key;
          message = '$message (服务端自动签发了新 API Key: $autoKey)';
        }
      }
      throw AnySearchException(
        message,
        statusCode: resp.statusCode,
        requestId: requestId,
        autoRegisteredKey: autoKey,
      );
    }
    return body;
  }

  Map<String, dynamic> _dataOf(Map<String, dynamic> envelope) =>
      envelope['data'] is Map<String, dynamic>
      ? envelope['data'] as Map<String, dynamic>
      : const <String, dynamic>{};

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
    String? apiKey,
  ) async {
    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: _buildHeaders(apiKey),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AnySearchException('请求超时，请稍后重试');
    } on http.ClientException catch (e) {
      throw AnySearchException('网络错误: ${e.message}');
    }
    return _parseEnvelope(resp);
  }

  // ── 实时搜索 ──────────────────────────────────────────────

  /// 通用/垂直领域搜索。
  ///
  /// [tag] 垂直子域路由键 (如 "finance.quote")；null 为通用网页搜索。
  /// [params] 垂直子域附加参数 (getSubDomains 返回的 required 参数必须全部带上)。
  /// [zone] 地区偏好 "cn" / "intl"；[language] 结果语言偏好 (如 "zh-CN")。
  /// [maxResults] 1~10。
  Future<AnySearchResponse> search(
    String query, {
    String? apiKey,
    String? tag,
    Map<String, String>? params,
    String? zone,
    String? language,
    int? maxResults,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const AnySearchResponse(
        results: [],
        totalResults: 0,
        searchTimeMs: 0,
      );
    }

    final payload = <String, dynamic>{'query': q};
    final normalizedTag = tag?.trim();
    if (normalizedTag != null && normalizedTag.isNotEmpty) {
      payload['tag'] = normalizedTag;
    }
    if (params != null && params.isNotEmpty) {
      payload['params'] = params;
    }
    final normalizedZone = zone?.trim();
    if (normalizedZone != null && normalizedZone.isNotEmpty) {
      payload['zone'] = normalizedZone;
    }
    final normalizedLanguage = language?.trim();
    if (normalizedLanguage != null && normalizedLanguage.isNotEmpty) {
      payload['language'] = normalizedLanguage;
    }
    if (maxResults != null) {
      payload['max_results'] = maxResults.clamp(1, 10);
    }

    final envelope = await _postJson('/v1/search', payload, apiKey);
    return AnySearchResponse.fromJson(_dataOf(envelope));
  }

  // ── 垂直领域能力目录 ──────────────────────────────────────

  /// 查询 1~5 个垂直领域的子域目录 (垂直搜索前必须先调用)。
  Future<List<AnySearchDomainCapabilities>> getSubDomains(
    List<String> domains, {
    String? apiKey,
  }) async {
    final normalized = domains
        .map((d) => d.trim().toLowerCase())
        .where((d) => d.isNotEmpty)
        .take(5)
        .toList();
    if (normalized.isEmpty) return const [];

    // 同名 key "domain" 需重复传参，手工拼接避免 Uri 覆盖
    final qs = normalized
        .map((d) => 'domain=${Uri.encodeQueryComponent(d)}')
        .join('&');
    http.Response resp;
    try {
      resp = await _client
          .get(
            Uri.parse('$_baseUrl/v1/sub-domains?$qs'),
            headers: _buildHeaders(apiKey),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AnySearchException('请求超时，请稍后重试');
    } on http.ClientException catch (e) {
      throw AnySearchException('网络错误: ${e.message}');
    }
    final envelope = _parseEnvelope(resp);
    final data = _dataOf(envelope);
    final raw = data['domains'];
    final result = <AnySearchDomainCapabilities>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          result.add(AnySearchDomainCapabilities.fromJson(e));
        }
      }
    }
    return result;
  }

  // ── 网页正文提取 ──────────────────────────────────────────

  /// 提取网页正文并转为 Markdown (支持 HTML/纯文本/JSON/Markdown，
  /// 不支持 PDF/Office/媒体等二进制格式；正文可能截断至 50000 字符)。
  Future<AnySearchExtractResult> extract(String url, {String? apiKey}) async {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      throw const AnySearchException('URL 不能为空');
    }
    final envelope = await _postJson('/v1/extract', {
      'url': normalized,
    }, apiKey);
    return AnySearchExtractResult.fromJson(_dataOf(envelope));
  }
}
