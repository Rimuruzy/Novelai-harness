import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/data/models/anysearch_models.dart';
import 'package:novelai_harness/data/services/anysearch_service.dart';

/// 构造 Mock 服务: routes 键为 "METHOD /path" (可含 query)，值为响应 JSON
AnySearchService _svc(
  Map<String, String> routes, {
  void Function(http.Request)? onRequest,
}) {
  return AnySearchService.forTesting(
    baseUrl: 'http://test',
    client: MockClient((request) async {
      onRequest?.call(request);
      final key =
          '${request.method} ${request.url.path}'
          '${request.url.query.isEmpty ? '' : '?${request.url.query}'}';
      final body = routes[key];
      return http.Response.bytes(
        utf8.encode(body ?? jsonEncode({'code': -1, 'message': 'not found'})),
        body == null ? 404 : 200,
      );
    }),
  );
}

Map<String, dynamic> _ok([Map<String, dynamic>? data]) => {
  'code': 0,
  'message': 'success',
  'data': ?data,
};

void main() {
  group('AnySearchService.search', () {
    test('解析结果与元数据 (content/snippet 兜底)', () async {
      final svc = _svc({
        'POST /v1/search': jsonEncode(
          _ok({
            'results': [
              {
                'title': 'NovelAI 官方文档',
                'url': 'https://docs.novelai.net/',
                'content': '图像生成参数说明',
              },
              {
                'title': '备用结果',
                'url': 'https://example.com/2',
                'snippet': 'snippet 字段兜底',
              },
            ],
            'metadata': {'total_results': 42, 'search_time_ms': 350},
          }),
        ),
      });
      final resp = await svc.search('novelai docs');
      expect(resp.results, hasLength(2));
      expect(resp.results.first.title, 'NovelAI 官方文档');
      expect(resp.results.first.content, '图像生成参数说明');
      expect(resp.results[1].content, 'snippet 字段兜底');
      expect(resp.totalResults, 42);
      expect(resp.searchTimeMs, 350);
    });

    test('携带 Bearer 鉴权与客户端头；匿名时不带 Authorization', () async {
      final headersLog = <http.Request>[];
      final svc = _svc({
        'POST /v1/search': jsonEncode(_ok({})),
      }, onRequest: headersLog.add);
      await svc.search('q1', apiKey: 'as_sk_test');
      await svc.search('q2');
      expect(headersLog, hasLength(2));
      expect(headersLog[0].headers['Authorization'], 'Bearer as_sk_test');
      expect(headersLog[0].headers['X-Anysearch-Client'], isNotEmpty);
      expect(headersLog[1].headers.containsKey('Authorization'), isFalse);
    });

    test('垂直搜索: tag/params/zone/language/max_results 全部下发并夹取', () async {
      final bodies = <Map<String, dynamic>>[];
      final svc = _svc(
        {'POST /v1/search': jsonEncode(_ok({}))},
        onRequest: (r) {
          if (r.body.isNotEmpty) {
            bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          }
        },
      );
      await svc.search(
        'AAPL',
        tag: 'finance.quote',
        params: const {'type': 'stock', 'symbol': 'AAPL', 'cn_code': ''},
        zone: 'cn',
        language: 'zh-CN',
        maxResults: 99,
      );
      expect(bodies.single['tag'], 'finance.quote');
      expect(bodies.single['params'], {
        'type': 'stock',
        'symbol': 'AAPL',
        'cn_code': '',
      });
      expect(bodies.single['zone'], 'cn');
      expect(bodies.single['language'], 'zh-CN');
      expect(bodies.single['max_results'], 10); // 夹取到上限
    });

    test('错误信封: code=-1 抛异常并携带 message/request_id', () async {
      final svc = _svc({
        'POST /v1/search': jsonEncode({
          'code': -1,
          'message': 'Rate limited, retry after 300 seconds.',
          'request_id': 'req_123',
        }),
      });
      await expectLater(
        svc.search('q'),
        throwsA(
          isA<AnySearchException>()
              .having((e) => e.message, 'message', contains('Rate limited'))
              .having((e) => e.requestId, 'requestId', 'req_123'),
        ),
      );
    });

    test('配额耗尽时透传 auto_registered 新 Key', () async {
      final svc = _svc({
        'POST /v1/search': jsonEncode({
          'code': -1,
          'message': 'Quota exceeded.',
          'auto_registered': {'api_key': 'as_sk_new'},
        }),
      });
      try {
        await svc.search('q');
        fail('should throw');
      } on AnySearchException catch (e) {
        expect(e.autoRegisteredKey, 'as_sk_new');
        expect(e.message, contains('as_sk_new'));
      }
    });
  });

  group('AnySearchService.getSubDomains', () {
    test('重复 domain 传参与目录解析 (必填/排序)', () async {
      final paths = <String>[];
      final svc = _svc(
        {
          'GET /v1/sub-domains?domain=finance&domain=academic': jsonEncode(
            _ok({
              'domains': [
                {
                  'domain': 'finance',
                  'sub_domains': [
                    {
                      'sub_domain': 'finance.quote',
                      'description': '股票/基金实时行情',
                      'params': {
                        'symbol': {
                          'description': '股票代码',
                          'required': true,
                          'sort_order': 2,
                        },
                        'type': {
                          'description': '证券类型',
                          'required': true,
                          'sort_order': 1,
                        },
                        'cn_code': {
                          'description': 'A股代码',
                          'required': false,
                          'sort_order': 3,
                        },
                      },
                    },
                  ],
                },
                {'domain': 'academic', 'sub_domains': []},
              ],
            }),
          ),
        },
        onRequest: (r) => paths.add('${r.method} ${r.url.path}?${r.url.query}'),
      );
      final caps = await svc.getSubDomains(['finance', 'academic']);
      expect(
        paths.single,
        'GET /v1/sub-domains?domain=finance&domain=academic',
      );
      expect(caps, hasLength(2));
      final finance = caps.first;
      expect(finance.domain, 'finance');
      final sub = finance.subDomains.single;
      expect(sub.subDomain, 'finance.quote');
      // sort_order 排序: type(1) < symbol(2) < cn_code(3)
      expect(sub.params.map((p) => p.name).toList(), [
        'type',
        'symbol',
        'cn_code',
      ]);
      expect(sub.params.first.required, isTrue);
      expect(sub.params.last.required, isFalse);
    });
  });

  group('AnySearchService.extract', () {
    test('POST /v1/extract 下发 url 并解析正文', () async {
      final bodies = <Map<String, dynamic>>[];
      final svc = _svc(
        {
          'POST /v1/extract': jsonEncode(
            _ok({
              'title': 'AnySearch Docs',
              'url': 'https://www.anysearch.com/docs',
              'content': '# 页面正文\nMarkdown 内容',
            }),
          ),
        },
        onRequest: (r) {
          if (r.body.isNotEmpty) {
            bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          }
        },
      );
      final result = await svc.extract('https://www.anysearch.com/docs');
      expect(bodies.single, {'url': 'https://www.anysearch.com/docs'});
      expect(result.title, 'AnySearch Docs');
      expect(result.content, contains('Markdown 内容'));
    });

    test('非 JSON 响应体抛解析异常', () async {
      final svc = AnySearchService.forTesting(
        baseUrl: 'http://test',
        client: MockClient(
          (request) async =>
              http.Response.bytes(utf8.encode('<html>502</html>'), 502),
        ),
      );
      await expectLater(
        svc.extract('https://example.com'),
        throwsA(isA<AnySearchException>()),
      );
    });
  });
}
