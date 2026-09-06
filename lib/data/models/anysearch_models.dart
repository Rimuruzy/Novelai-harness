/// AnySearch (api.anysearch.com) 协议实体模型
///
/// 官方文档: https://www.anysearch.com/docs
/// 端点: POST /v1/search、GET /v1/sub-domains、POST /v1/extract
/// 响应统一信封: {"code": 0, "message": "success", "data": {...}}
/// 错误时 code 为 -1，message 携带错误原因，request_id 可选。
library;

/// AnySearch 调用异常
class AnySearchException implements Exception {
  final String message;

  /// HTTP 状态码 (0 = 网络层/解析层错误，未拿到 HTTP 响应)
  final int statusCode;

  /// 服务端 request_id (排查问题用，可为空)
  final String requestId;

  /// 配额耗尽时服务端自动签发的新 API Key (可为 null)
  ///
  /// 官方语义: 匿名额度耗尽时响应 auto_registered 字段可能携带新 Key，
  /// 需用户确认后才能保存使用 (本项目不做自动保存，仅透传给用户决定)。
  final String? autoRegisteredKey;

  const AnySearchException(
    this.message, {
    this.statusCode = 0,
    this.requestId = '',
    this.autoRegisteredKey,
  });

  @override
  String toString() => message;
}

/// AnySearch 支持的垂直领域目录 (官方 skill constants.json)
const List<String> kAnySearchDomains = [
  'general',
  'resource',
  'social_media',
  'finance',
  'academic',
  'legal',
  'health',
  'business',
  'security',
  'ip',
  'code',
  'energy',
  'environment',
  'agriculture',
  'travel',
  'film',
  'gaming',
];

/// 单条搜索结果
class AnySearchResult {
  final String title;
  final String url;

  /// 结果摘要 (服务端字段 content 或 snippet)
  final String content;

  const AnySearchResult({
    required this.title,
    required this.url,
    required this.content,
  });

  factory AnySearchResult.fromJson(Map<String, dynamic> json) {
    return AnySearchResult(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      content:
          (json['content'] as String?) ?? (json['snippet'] as String? ?? ''),
    );
  }
}

/// 搜索响应 (data 部分)
class AnySearchResponse {
  final List<AnySearchResult> results;

  /// 结果总数 (服务端 metadata.total_results，缺省为当前页条数)
  final int totalResults;

  /// 服务端检索耗时 (毫秒)
  final int searchTimeMs;

  const AnySearchResponse({
    required this.results,
    required this.totalResults,
    required this.searchTimeMs,
  });

  factory AnySearchResponse.fromJson(Map<String, dynamic> json) {
    final results = <AnySearchResult>[];
    final rawResults = json['results'];
    if (rawResults is List) {
      for (final e in rawResults) {
        if (e is Map<String, dynamic>) {
          results.add(AnySearchResult.fromJson(e));
        }
      }
    }
    final metadata = json['metadata'];
    final total = metadata is Map<String, dynamic>
        ? (metadata['total_results'] as num?)?.toInt() ?? results.length
        : results.length;
    final elapsed = metadata is Map<String, dynamic>
        ? (metadata['search_time_ms'] as num?)?.toInt() ?? 0
        : 0;
    return AnySearchResponse(
      results: results,
      totalResults: total,
      searchTimeMs: elapsed,
    );
  }
}

/// 垂直子域的单个参数规格
class AnySearchSubDomainParam {
  final String name;
  final String description;
  final bool required;
  final int sortOrder;

  const AnySearchSubDomainParam({
    required this.name,
    required this.description,
    required this.required,
    required this.sortOrder,
  });
}

/// 垂直子域能力 (如 finance.quote)
class AnySearchSubDomain {
  /// 路由键，形如 "finance.quote"，搜索时作为 tag 传入
  final String subDomain;
  final String description;
  final List<AnySearchSubDomainParam> params;

  const AnySearchSubDomain({
    required this.subDomain,
    required this.description,
    required this.params,
  });

  factory AnySearchSubDomain.fromJson(Map<String, dynamic> json) {
    final params = <AnySearchSubDomainParam>[];
    final rawParams = json['params'];
    if (rawParams is Map<String, dynamic>) {
      rawParams.forEach((name, spec) {
        final info = spec is Map<String, dynamic> ? spec : const {};
        params.add(
          AnySearchSubDomainParam(
            name: name,
            description: info['description'] as String? ?? '',
            required: info['required'] as bool? ?? false,
            sortOrder: (info['sort_order'] as num?)?.toInt() ?? 0,
          ),
        );
      });
    }
    params.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return AnySearchSubDomain(
      subDomain: json['sub_domain'] as String? ?? '',
      description: json['description'] as String? ?? '',
      params: params,
    );
  }
}

/// 单个垂直领域的完整能力目录
class AnySearchDomainCapabilities {
  final String domain;
  final List<AnySearchSubDomain> subDomains;

  const AnySearchDomainCapabilities({
    required this.domain,
    required this.subDomains,
  });

  factory AnySearchDomainCapabilities.fromJson(Map<String, dynamic> json) {
    final subDomains = <AnySearchSubDomain>[];
    final raw = json['sub_domains'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          subDomains.add(AnySearchSubDomain.fromJson(e));
        }
      }
    }
    return AnySearchDomainCapabilities(
      domain: json['domain'] as String? ?? '',
      subDomains: subDomains,
    );
  }
}

/// 网页正文提取结果 (Markdown)
class AnySearchExtractResult {
  final String title;
  final String url;
  final String content;

  const AnySearchExtractResult({
    required this.title,
    required this.url,
    required this.content,
  });

  factory AnySearchExtractResult.fromJson(Map<String, dynamic> json) {
    return AnySearchExtractResult(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }
}
