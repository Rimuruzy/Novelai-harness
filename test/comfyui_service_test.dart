import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/data/models/comfyui_models.dart';
import 'package:novelai_harness/data/services/comfyui_service.dart';

void main() {
  group('ComfyUiParamsPatch', () {
    test('仅序列化非空字段', () {
      const patch = ComfyUiParamsPatch(negative: 'lowres', steps: 30, cfg: 6.5);
      final json = patch.toJson();
      expect(json, containsPair('negative', 'lowres'));
      expect(json, containsPair('steps', 30));
      expect(json, containsPair('cfg', 6.5));
      expect(json.containsKey('seed'), isFalse);
      expect(json.containsKey('denoise'), isFalse);
      expect(patch.isEmpty, isFalse);
    });

    test('sampler_name/scheduler 映射为插件 PARAMS_FIELDS 字段名', () {
      const patch = ComfyUiParamsPatch(
        samplerName: 'dpmpp_2m',
        scheduler: 'karras',
      );
      final json = patch.toJson();
      expect(json, containsPair('sampler_name', 'dpmpp_2m'));
      expect(json, containsPair('scheduler', 'karras'));
      expect(patch.isEmpty, isFalse);

      const empty = ComfyUiParamsPatch(samplerName: null, scheduler: null);
      expect(empty.toJson(), isEmpty);
    });

    test('空补丁 isEmpty 且不下发', () async {
      const patch = ComfyUiParamsPatch();
      expect(patch.isEmpty, isTrue);
      expect(patch.toJson(), isEmpty);
    });
  });

  group('ComfyUiBridgeState', () {
    test('fromResponses 从三张注册表提取节点 id', () {
      final state = ComfyUiBridgeState.fromResponses(
        prompts: {
          'prompts': {'10': 'a', '11': 'b'},
        },
        resolutions: {
          'resolutions': {'20': {}},
        },
        params: const {},
        baseUrl: 'http://127.0.0.1:8188',
      );
      expect(state.promptNodeIds, ['10', '11']);
      expect(state.resolutionNodeIds, ['20']);
      expect(state.paramsNodeIds, isEmpty);
      expect(state.canDrive, isTrue);
      expect(state.baseUrl, 'http://127.0.0.1:8188');
    });

    test('空快照 canDrive 为 false', () {
      const state = ComfyUiBridgeState.empty('http://x');
      expect(state.canDrive, isFalse);
    });
  });

  group('ComfyUiService', () {
    test('fetchBridgeState 汇聚三条注册表路由', () async {
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path == '/pt/ai/prompt') {
            return http.Response(
              jsonEncode({
                'prompts': {'1': 'hello'},
              }),
              200,
            );
          }
          if (path == '/pt/ai/resolution') {
            return http.Response(
              jsonEncode({
                'resolutions': {
                  '2': {'width': 832, 'height': 1216},
                },
              }),
              200,
            );
          }
          if (path == '/pt/ai/params') {
            return http.Response(
              jsonEncode({
                'params': {
                  '3': {'steps': 28},
                },
              }),
              200,
            );
          }
          fail('unexpected request: $path');
        }),
      );

      final state = await service.fetchBridgeState();
      expect(state.promptNodeIds, ['1']);
      expect(state.resolutionNodeIds, ['2']);
      expect(state.paramsNodeIds, ['3']);
    });

    test('旧版插件 /pt/ai/params 404 时按空表容错', () async {
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient((request) async {
          if (request.url.path == '/pt/ai/params') {
            return http.Response(jsonEncode({'error': 'not found'}), 404);
          }
          return http.Response(
            jsonEncode({
              'prompts': {'1': 'hello'},
              'resolutions': {},
            }),
            200,
          );
        }),
      );

      final state = await service.fetchBridgeState();
      expect(state.promptNodeIds, ['1']);
      expect(state.paramsNodeIds, isEmpty);
    });

    test('连接失败翻译为 ComfyUiBridgeException', () async {
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient(
          (request) async => throw http.ClientException('refused'),
        ),
      );

      await expectLater(
        service.fetchBridgeState(),
        throwsA(
          isA<ComfyUiBridgeException>().having(
            (e) => e.isConnectionError,
            'isConnectionError',
            isTrue,
          ),
        ),
      );
    });

    test('setParams 携带 node_id 与补丁字段', () async {
      Map<String, dynamic>? captured;
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/pt/ai/params/set');
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      await service.setParams(
        '3',
        const ComfyUiParamsPatch(negative: 'bad', steps: 30, seed: 42),
      );
      expect(captured, isNotNull);
      expect(captured!['node_id'], '3');
      expect(captured!['negative'], 'bad');
      expect(captured!['steps'], 30);
      expect(captured!['seed'], 42);
      expect(captured!.containsKey('cfg'), isFalse);
    });

    test('fetchOptionCatalog 优先解析 ParamsPanelPT 节点定义', () async {
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/object_info/ParamsPanelPT');
          return http.Response(
            jsonEncode({
              'ParamsPanelPT': {
                'input': {
                  'required': {
                    'negative': [
                      'STRING',
                      {'default': ''},
                    ],
                    'steps': [
                      'INT',
                      {'default': 28},
                    ],
                    'sampler_name': [
                      ['euler', 'dpmpp_2m', 'dpmpp_sde'],
                      {'tooltip': '...'},
                    ],
                    'scheduler': [
                      ['normal', 'karras', 'exponential'],
                      {'tooltip': '...'},
                    ],
                  },
                },
              },
            }),
            200,
          );
        }),
      );

      final catalog = await service.fetchOptionCatalog();
      expect(catalog.samplers, ['euler', 'dpmpp_2m', 'dpmpp_sde']);
      expect(catalog.schedulers, ['normal', 'karras', 'exponential']);
      expect(catalog.isNotEmpty, isTrue);
    });

    test('旧版插件无采样器字段时回退 KSampler 节点定义', () async {
      final paths = <String>[];
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/object_info/ParamsPanelPT') {
            // 旧版 ParamsPanelPT：没有 sampler_name/scheduler 字段
            return http.Response(
              jsonEncode({
                'ParamsPanelPT': {
                  'input': {
                    'required': {
                      'negative': [
                        'STRING',
                        {'default': ''},
                      ],
                    },
                  },
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'KSampler': {
                'input': {
                  'required': {
                    'sampler_name': [
                      ['euler', 'heun'],
                      {'tooltip': '...'},
                    ],
                    'scheduler': [
                      ['normal', 'karras'],
                      {'tooltip': '...'},
                    ],
                  },
                },
              },
            }),
            200,
          );
        }),
      );

      final catalog = await service.fetchOptionCatalog();
      expect(paths, ['/object_info/ParamsPanelPT', '/object_info/KSampler']);
      expect(catalog.samplers, ['euler', 'heun']);
      expect(catalog.schedulers, ['normal', 'karras']);
    });

    test('两处都拿不到时抛出异常', () async {
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient(
          (request) async =>
              http.Response(jsonEncode({'error': 'not found'}), 400),
        ),
      );

      await expectLater(
        service.fetchOptionCatalog(),
        throwsA(isA<ComfyUiBridgeException>()),
      );
    });

    test('setPrompt 与 setResolution 的请求体', () async {
      final bodies = <String, Map<String, dynamic>>{};
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient((request) async {
          bodies[request.url.path] =
              jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      await service.setPrompt('1', 'masterpiece, 1girl');
      await service.setResolution('2', 1024, 1024);

      expect(bodies['/pt/ai/prompt/set']!['node_id'], '1');
      expect(bodies['/pt/ai/prompt/set']!['positive'], 'masterpiece, 1girl');
      expect(bodies['/pt/ai/resolution/set']!['width'], 1024);
      expect(bodies['/pt/ai/resolution/set']!['height'], 1024);
    });

    test('latestImages 解析 newest first 列表', () async {
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/pt/ai/image/latest');
          expect(request.url.queryParameters['limit'], '3');
          return http.Response(
            jsonEncode({
              'images': [
                {
                  'node_id': '9',
                  'filename': 'b.png',
                  'abs_path': r'C:\temp\b.png',
                  'preview_path': r'C:\temp\b_preview.jpg',
                  'time': 100.5,
                },
                {
                  'node_id': '8',
                  'filename': 'a.png',
                  'abs_path': r'C:\temp\a.png',
                  'preview_path': null,
                  'time': 99.0,
                },
              ],
            }),
            200,
          );
        }),
      );

      final images = await service.latestImages(limit: 3);
      expect(images, hasLength(2));
      expect(images.first.filename, 'b.png');
      expect(images.first.time, 100.5);
      expect(images.first.previewPath, r'C:\temp\b_preview.jpg');
      expect(images.last.time, 99.0);
    });

    test('rawImageBytes 返回字节且透传 index', () async {
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/pt/ai/image/raw');
          expect(request.url.queryParameters['index'], '0');
          return http.Response.bytes([1, 2, 3, 4], 200);
        }),
      );

      final bytes = await service.rawImageBytes();
      expect(bytes, [1, 2, 3, 4]);
    });

    test('HTTP 错误响应展开服务端 error 字段', () async {
      final service = ComfyUiService(
        baseUrl: 'http://127.0.0.1:8188',
        httpClient: MockClient(
          (request) async =>
              http.Response(jsonEncode({'error': 'node_id is required'}), 400),
        ),
      );

      await expectLater(
        service.queue(),
        throwsA(
          isA<ComfyUiBridgeException>().having(
            (e) => e.message,
            'message',
            'node_id is required',
          ),
        ),
      );
    });
  });
}
