import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/nai_special_tags.dart';
import 'package:novelai_harness/data/models/tag_models.dart';
import 'package:novelai_harness/data/services/tag_dictionary_service.dart';

/// NovelAI 官方专属标签 (docs.novelai.net/en/image/tags) 接入离线词典的回归测试
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Danbooru 侧样本：含与官方专属词重叠的 transparent_background / alpha_transparency
  const sampleTsv =
      '1girl\t6008644\t1个女孩\t1girls,sole_female\n'
      'long_hair\t4350743\t长发\t/lh,longhair\n'
      'transparent_background\t177672\t透明背景\ttransparent_png\t0\n'
      'alpha_transparency\t2085\tAlpha透明通道\t\t5\n';

  final service = TagDictionaryService.instance;

  setUpAll(() {
    // 主线程同步扫描：结果确定，且不依赖真实 isolate 回投时序
    TagDictionaryService.backgroundSearchEnabled = false;
  });

  tearDownAll(() {
    TagDictionaryService.backgroundSearchEnabled = true;
  });

  setUp(() async {
    await service.ensureLoaded(rawTsvContent: sampleTsv);
    service.clearQueryCache();
  });

  group('官方专属标签检索', () {
    test('画质标签可前缀命中并携带 NAI 分组胶囊', () async {
      final results = await service.search('best qual', limit: 5);

      expect(results, isNotEmpty);
      expect(results.first.tag, 'best quality');
      expect(results.first.customCategoryLabel, 'NAI·画质');
      expect(results.first.category, DanbooruTagCategory.meta);
      expect(results.first.translation, contains('顶级画质'));
      // 全系可用，不带模型限制后缀
      expect(results.first.translation, isNot(contains('V5')));
    });

    test('美学标签携带模型可用范围说明', () async {
      final results = await service.search('aesthetic', limit: 10);

      final byTag = {for (final r in results) r.tag: r};
      expect(byTag.keys, containsAll(<String>['very aesthetic', 'aesthetic']));
      expect(byTag['top aesthetic']?.translation, contains('V4 及以上'));

      final masterpiece = await service.search('masterpiece', limit: 5);
      expect(masterpiece.first.tag, 'masterpiece');
      expect(masterpiece.first.translation, contains('V4.5 及以上'));
    });

    test('复杂度标签整组命中且标注 V5 专属', () async {
      final results = await service.search('complexity', limit: 10);

      expect(results, hasLength(4));
      expect(results.every((e) => e.customCategoryLabel == 'NAI·复杂度'), isTrue);
      expect(results.every((e) => e.translation!.contains('V5 专属')), isTrue);
      expect(results.map((e) => e.tag).toSet(), {
        'low complexity',
        'medium complexity',
        'high complexity',
        'ultra complexity',
      });
    });

    test('中文释义检索官方专属标签', () async {
      final results = await service.search('画质', limit: 10);

      expect(
        results.map((e) => e.tag).toSet(),
        containsAll(<String>['best quality', 'bad quality', 'worst quality']),
      );
      expect(results.every((e) => e.customCategoryLabel == 'NAI·画质'), isTrue);
    });

    test('改名标签的旧写法别名可补全到新词条', () async {
      final tachiE = await service.search('tachi-e', limit: 5);
      expect(tachiE.first.tag, 'character image');
      expect(tachiE.first.matchedAlias, 'tachi-e');

      final eyepatch = await service.search('eyepatch bikini', limit: 5);
      expect(eyepatch.first.tag, 'square bikini');

      final doubleV = await service.search('double v', limit: 5);
      expect(doubleV.first.tag, 'double peace');
    });

    test('与 Danbooru 重叠的词条去重并合并热度计数', () async {
      final results = await service.search('transparent background', limit: 5);
      final hits = results.where((e) => e.tag == 'transparent background');

      expect(hits, hasLength(1));
      // 保留官方专属释义与分组胶囊，热度沿用 Danbooru 计数
      expect(hits.first.customCategoryLabel, 'NAI·透明通道');
      expect(hits.first.translation, contains('V5 专属'));
      expect(hits.first.postCount, 177672);
    });

    test('冷门专属词不挤占高热度 Danbooru 词条排序', () async {
      // location (专属, 无热度) 与 long hair (433 万热度) 同为前缀命中
      final results = await service.search('lo', limit: 5);

      expect(results.first.tag, 'long hair');
      expect(results.map((e) => e.tag), contains('location'));
    });
  });

  group('年代标签动态合成', () {
    test('完整四位年份精确合成单条建议', () async {
      final results = await service.search('year 2014', limit: 5);

      expect(results, hasLength(1));
      expect(results.first.tag, 'year 2014');
      expect(results.first.customCategoryLabel, 'NAI·年代');
      expect(results.first.translation, '2014 年代画风');
      expect(results.first.category, DanbooruTagCategory.meta);
    });

    test('下划线写法同样命中', () async {
      final results = await service.search('year_1998', limit: 5);

      expect(results, hasLength(1));
      expect(results.first.tag, 'year 1998');
    });

    test('年份前缀按新近度降序补全', () async {
      final results = await service.search('year 20', limit: 5);

      expect(results, hasLength(5));
      final years = results
          .map((e) => int.parse(e.tag.substring('year '.length)))
          .toList();
      expect(years.every((y) => '$y'.startsWith('20')), isTrue);
      expect(years, orderedEquals([...years]..sort((a, b) => b.compareTo(a))));
    });

    test('仅输入 year 时给出近年候选', () async {
      final results = await service.search('year', limit: 6);

      expect(results, hasLength(6));
      expect(results.every((e) => e.tag.startsWith('year ')), isTrue);
    });

    test('中文「年代」查询也能唤出年代标签', () async {
      final results = await service.search('年代', limit: 4);

      expect(results, isNotEmpty);
      expect(results.every((e) => e.tag.startsWith('year ')), isTrue);
    });

    test('分类过滤为非 meta 时不注入年代标签', () async {
      final results = await service.search(
        'year 2014',
        limit: 5,
        category: DanbooruTagCategory.character,
      );

      expect(results, isEmpty);
    });
  });

  group('反查表 (提示词高亮)', () {
    test('官方专属标签写入中文释义与分类反查', () {
      expect(service.translationOf('best quality'), contains('顶级画质'));
      expect(service.translationOf('best_quality'), contains('顶级画质'));
      expect(service.translationOf('masterpiece'), contains('杰作'));
      expect(service.categoryOf('best quality'), DanbooruTagCategory.meta);
      expect(service.categoryOf('peace sign'), DanbooruTagCategory.general);
    });

    test('年代标签为动态词条，反查按需还原', () {
      expect(service.translationOf('year 1998'), '1998 年代画风');
      expect(service.translationOf('year_1998'), '1998 年代画风');
      expect(service.categoryOf('year 1998'), DanbooruTagCategory.meta);
      expect(parseNaiYearTag('year 1998'), 1998);
      expect(parseNaiYearTag('year_98'), isNull);
      expect(parseNaiYearTag('years 1998'), isNull);
    });

    test('Danbooru 原有反查不受专属词条影响', () {
      expect(service.translationOf('long hair'), '长发');
      expect(service.translationOf('1girl'), '1个女孩');
      expect(service.categoryOf('1girl'), DanbooruTagCategory.general);
      expect(service.translationOf('不存在的词'), isNull);
    });
  });

  group('数据源与降级', () {
    test('专属标签清单覆盖官方文档全部分组', () {
      expect(kNaiSpecialTags, isNotEmpty);
      expect(
        kNaiSpecialTags.map((t) => t.tag).toSet(),
        containsAll(<String>[
          'best quality',
          'amazing quality',
          'great quality',
          'normal quality',
          'bad quality',
          'worst quality',
          'masterpiece',
          'top aesthetic',
          'very aesthetic',
          'aesthetic',
          'displeasing',
          'very displeasing',
          'low complexity',
          'medium complexity',
          'high complexity',
          'ultra complexity',
          'fur dataset',
          'background dataset',
          'transparent background',
          'has alpha',
          'alpha transparency',
          'peace sign',
          'double peace',
          'bar eyes',
          'open \\m/',
          'neutral face',
          'neco-arc eyes',
          'square bikini',
          'character image',
          'location',
          'depthness',
          'attractive male',
          'meta:novel era',
          'meta:golden era',
          'visual novel art',
          'visual novel bg',
          'visual novel cg',
          'visual novel chibi',
          'visual novel sprite',
        ]),
      );
      // 分组齐备 (年代组无静态词条，由动态合成 + 灵感库样例承载)
      expect(
        kNaiSpecialTagsByGroup.keys,
        containsAll(NaiSpecialTagGroup.values),
      );
      expect(kNaiYearSampleTags, isNotEmpty);
      expect(
        kNaiYearSampleTags.every((t) => t.group == NaiSpecialTagGroup.year),
        isTrue,
      );
    });

    test('词库为空时仍可补全官方专属标签与年代标签', () async {
      await service.replaceWithContent('');
      service.clearQueryCache();
      expect(service.count, 0);

      final quality = await service.search('best quality', limit: 5);
      expect(quality, isNotEmpty);
      expect(quality.first.tag, 'best quality');

      final year = await service.search('year 2014', limit: 5);
      expect(year.first.tag, 'year 2014');

      // 恢复样本词库，避免污染后续用例
      await service.replaceWithContent(sampleTsv);
      service.clearQueryCache();
      expect(service.count, 4);
    });
  });

  group('后台检索 isolate (生产路径)', () {
    setUp(() async {
      TagDictionaryService.backgroundSearchEnabled = true;
      await service.ensureLoaded(rawTsvContent: sampleTsv);
      service.clearQueryCache();
    });

    tearDown(() {
      TagDictionaryService.backgroundSearchEnabled = false;
    });

    test('worker isolate 扫描同样覆盖官方专属词条', () async {
      final viaWorker = await service.search('best qual', limit: 5);

      expect(viaWorker, isNotEmpty);
      expect(viaWorker.first.tag, 'best quality');
      expect(viaWorker.first.customCategoryLabel, 'NAI·画质');
      expect(viaWorker.first.translation, contains('顶级画质'));

      // 改名标签的旧写法别名在 worker 侧同样走别名档位
      service.clearQueryCache();
      final alias = await service.search('tachi-e', limit: 5);
      expect(alias.first.tag, 'character image');
      expect(alias.first.matchedAlias, 'tachi-e');
    });

    test('worker 与主线程兑底的专属词条结果一致', () async {
      final viaWorker = await service.search('complexity', limit: 10);

      service.clearQueryCache();
      TagDictionaryService.backgroundSearchEnabled = false;
      final viaMain = await service.search('complexity', limit: 10);
      TagDictionaryService.backgroundSearchEnabled = true;

      expect(
        viaWorker.map((e) => e.tag).toList(),
        viaMain.map((e) => e.tag).toList(),
      );
      expect(viaWorker, hasLength(4));
    });

    test('年代标签在主线程合成，不依赖 worker 就绪', () async {
      final results = await service.search('year 2014', limit: 5);

      expect(results, hasLength(1));
      expect(results.first.tag, 'year 2014');
      expect(results.first.customCategoryLabel, 'NAI·年代');
    });
  });
}
