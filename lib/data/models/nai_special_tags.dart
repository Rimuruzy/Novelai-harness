import 'tag_models.dart';

/// NovelAI 官方专属标签数据源
///
/// 来源：官方文档 <https://docs.novelai.net/en/image/tags> 的
/// Special Tags / Renamed Tags / Other Tags 三节。这些词条是 NovelAI
/// 自训练数据集独有的指令词，Danbooru 词库 (assets/danbooru.tsv) 中
/// **完全不存在**，因此单列一份静态事实源，由 TagDictionaryService 与
/// Danbooru 词条同构合并进统一检索/反查管线 (标签补全、灵感库、
/// 提示词高亮、Agent 离线标签检索均自动受益)。
///
/// 年代标签 (`year XXXX`) 为动态词条 (任意年份可用)，不在静态清单内，
/// 由 TagDictionaryService 按查询前缀实时合成，此处仅提供灵感库样例。

/// 官方文档的专属标签分组 (枚举顺序即灵感库侧栏展示顺序)
enum NaiSpecialTagGroup {
  quality('画质'),
  aesthetic('美学'),
  complexity('复杂度'),
  year('年代'),
  dataset('数据集'),
  alpha('透明通道'),
  renamed('改名标签'),
  other('其他');

  /// 中文分组名 (数据域展示名，UI 侧直接渲染)
  final String label;

  const NaiSpecialTagGroup(this.label);

  /// 标签补全卡分类胶囊文案 (覆盖标准 Danbooru 分类显示)
  String get pillLabel => 'NAI·$label';
}

/// 单枚 NovelAI 专属标签
class NaiSpecialTag {
  /// 上屏文本 (空格形态，与补全卡其余词条一致)
  final String tag;

  /// 中文释义
  final String zh;

  /// 官方文档所属分组
  final NaiSpecialTagGroup group;

  /// 分类 (决定补全胶囊配色；改名标签多为画面元素，归 general)
  final DanbooruTagCategory category;

  /// 可用模型范围说明 (null 表示全系可用)
  final String? modelNote;

  /// 别名 / 旧写法 (改名标签的历史语法，输入旧写法也能补全到新词条)
  final List<String> aliases;

  const NaiSpecialTag({
    required this.tag,
    required this.zh,
    required this.group,
    this.category = DanbooruTagCategory.meta,
    this.modelNote,
    this.aliases = const [],
  });

  /// 展示释义：中文 + 可用模型范围 (标签补全与提示词高亮使用)
  String get displayZh => modelNote == null ? zh : '$zh · $modelNote';

  /// 灵感库展示释义：额外附带改名标签的旧写法提示
  ///
  /// 补全卡已有 matchedAlias 胶囊展示命中别名，故旧写法不写入 displayZh，
  /// 避免同一行重复出现两次旧语法；灵感库没有别名胶囊，在此补齐说明。
  String get galleryZh =>
      aliases.isEmpty ? displayZh : '$displayZh · 旧写法 ${aliases.join(' / ')}';
}

/// NovelAI 专属标签全量清单 (按官方文档分节顺序；未标注 modelNote 即全系可用)
const List<NaiSpecialTag> kNaiSpecialTags = [
  // ---- Quality Tags：影响整体画质 ----
  NaiSpecialTag(
    tag: 'best quality',
    zh: '顶级画质',
    group: NaiSpecialTagGroup.quality,
  ),
  NaiSpecialTag(
    tag: 'amazing quality',
    zh: '惊艳画质',
    group: NaiSpecialTagGroup.quality,
  ),
  NaiSpecialTag(
    tag: 'great quality',
    zh: '优良画质',
    group: NaiSpecialTagGroup.quality,
  ),
  NaiSpecialTag(
    tag: 'normal quality',
    zh: '普通画质',
    group: NaiSpecialTagGroup.quality,
  ),
  NaiSpecialTag(
    tag: 'bad quality',
    zh: '低劣画质',
    group: NaiSpecialTagGroup.quality,
  ),
  NaiSpecialTag(
    tag: 'worst quality',
    zh: '最差画质',
    group: NaiSpecialTagGroup.quality,
  ),

  // ---- Aesthetic Tags：影响画面美感 ----
  NaiSpecialTag(
    tag: 'masterpiece',
    zh: '杰作',
    group: NaiSpecialTagGroup.aesthetic,
    modelNote: 'V4.5 及以上',
  ),
  NaiSpecialTag(
    tag: 'top aesthetic',
    zh: '顶级美感',
    group: NaiSpecialTagGroup.aesthetic,
    modelNote: 'V4 及以上',
  ),
  NaiSpecialTag(
    tag: 'very aesthetic',
    zh: '极富美感',
    group: NaiSpecialTagGroup.aesthetic,
  ),
  NaiSpecialTag(
    tag: 'aesthetic',
    zh: '美感',
    group: NaiSpecialTagGroup.aesthetic,
  ),
  NaiSpecialTag(
    tag: 'displeasing',
    zh: '观感不佳',
    group: NaiSpecialTagGroup.aesthetic,
  ),
  NaiSpecialTag(
    tag: 'very displeasing',
    zh: '观感极差',
    group: NaiSpecialTagGroup.aesthetic,
  ),

  // ---- Complexity Tags：控制画面复杂度 (V5 专属) ----
  NaiSpecialTag(
    tag: 'low complexity',
    zh: '低复杂度 (风格化)',
    group: NaiSpecialTagGroup.complexity,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'medium complexity',
    zh: '中复杂度',
    group: NaiSpecialTagGroup.complexity,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'high complexity',
    zh: '高复杂度 (常规推荐)',
    group: NaiSpecialTagGroup.complexity,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'ultra complexity',
    zh: '超高复杂度 (风格化)',
    group: NaiSpecialTagGroup.complexity,
    modelNote: 'V5 专属',
  ),

  // ---- Dataset Tags：切换训练数据集 (需置于提示词最前) ----
  NaiSpecialTag(
    tag: 'fur dataset',
    zh: '兽人数据集 (Furry 模式)',
    group: NaiSpecialTagGroup.dataset,
    modelNote: 'V4 及以上',
  ),
  NaiSpecialTag(
    tag: 'background dataset',
    zh: '无人物摄影数据集 (风景/动物/静物)',
    group: NaiSpecialTagGroup.dataset,
    modelNote: 'V4.5 及以上',
  ),

  // ---- Alpha Transparency Tags：真透明通道 (V5 专属) ----
  NaiSpecialTag(
    tag: 'transparent background',
    zh: '透明背景',
    group: NaiSpecialTagGroup.alpha,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'has alpha',
    zh: '启用 Alpha 通道 (抽象透明需求)',
    group: NaiSpecialTagGroup.alpha,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'alpha transparency',
    zh: 'Alpha 半透明效果 (火焰/魔法/雨伞等)',
    group: NaiSpecialTagGroup.alpha,
    modelNote: 'V5 专属',
  ),

  // ---- Renamed Tags：因 | 是提示词混合分隔符而改名的词条 ----
  // 旧写法一律走 aliases：输入旧语法即以别名档位 (800) 补全到官方新词条，
  // 不会被中文释义包含匹配 (300) 降级，也不会与 Danbooru 高热度旧词条混淆
  NaiSpecialTag(
    tag: 'peace sign',
    zh: '剪刀手',
    group: NaiSpecialTagGroup.renamed,
    category: DanbooruTagCategory.general,
    aliases: ['v'],
  ),
  NaiSpecialTag(
    tag: 'double peace',
    zh: '双手剪刀手',
    group: NaiSpecialTagGroup.renamed,
    category: DanbooruTagCategory.general,
    aliases: ['double v'],
  ),
  NaiSpecialTag(
    tag: 'bar eyes',
    zh: '条形眼',
    group: NaiSpecialTagGroup.renamed,
    category: DanbooruTagCategory.general,
    aliases: ['|_|'],
  ),
  NaiSpecialTag(
    tag: 'open \\m/',
    zh: '张开的 \\m/ 手势',
    group: NaiSpecialTagGroup.renamed,
    category: DanbooruTagCategory.general,
    aliases: ['\\||/'],
  ),
  NaiSpecialTag(
    tag: 'neutral face',
    zh: '面无表情',
    group: NaiSpecialTagGroup.renamed,
    category: DanbooruTagCategory.general,
    aliases: [':|', ';|'],
  ),
  NaiSpecialTag(
    tag: 'neco-arc eyes',
    zh: 'Neco-Arc 眼',
    group: NaiSpecialTagGroup.renamed,
    category: DanbooruTagCategory.general,
    aliases: ['<|> <|>'],
  ),
  NaiSpecialTag(
    tag: 'square bikini',
    zh: '方形比基尼',
    group: NaiSpecialTagGroup.renamed,
    category: DanbooruTagCategory.general,
    aliases: ['eyepatch bikini'],
  ),
  NaiSpecialTag(
    tag: 'character image',
    zh: '角色立绘',
    group: NaiSpecialTagGroup.renamed,
    aliases: ['tachi-e'],
  ),

  // ---- Other Tags：其余官方专属词条 ----
  NaiSpecialTag(
    tag: 'location',
    zh: '场景 (兼具 indoors 与 outdoors)',
    group: NaiSpecialTagGroup.other,
  ),
  NaiSpecialTag(
    tag: 'depthness',
    zh: '加深阴影立体感',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'attractive male',
    zh: '俊美男性',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'meta:novel era',
    zh: '偏向复古画风',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'meta:golden era',
    zh: '偏向现代画风',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'visual novel art',
    zh: '视觉小说画风',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'visual novel bg',
    zh: '视觉小说背景',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'visual novel cg',
    zh: '视觉小说 CG',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'visual novel chibi',
    zh: '视觉小说 Q 版',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
  NaiSpecialTag(
    tag: 'visual novel sprite',
    zh: '视觉小说立绘精灵',
    group: NaiSpecialTagGroup.other,
    modelNote: 'V5 专属',
  ),
];

/// 年代标签样例年份 (`year XXXX` 实际可填任意年份，此处仅供灵感库速查)
const List<int> kNaiYearTagSamples = [
  2025,
  2020,
  2015,
  2010,
  2005,
  2000,
  1995,
  1990,
  1985,
  1980,
];

/// 年代标签样例词条 (灵感库展示用；检索侧由服务动态合成任意年份)
final List<NaiSpecialTag> kNaiYearSampleTags = [
  for (final year in kNaiYearTagSamples)
    NaiSpecialTag(
      tag: 'year $year',
      zh: '$year 年代画风',
      group: NaiSpecialTagGroup.year,
    ),
];

/// 按官方文档分组聚合的专属标签 (含年代样例，灵感库分组渲染用)
final Map<NaiSpecialTagGroup, List<NaiSpecialTag>> kNaiSpecialTagsByGroup = {
  for (final group in NaiSpecialTagGroup.values)
    group: [
      ...kNaiSpecialTags.where((t) => t.group == group),
      if (group == NaiSpecialTagGroup.year) ...kNaiYearSampleTags,
    ],
};

/// 年代标签解析：`year 2014` / `year_2014` → 2014，非年代词条返回 null
int? parseNaiYearTag(String tagName) {
  final key = tagName.trim().replaceAll('_', ' ').toLowerCase();
  final match = RegExp(r'^year (\d{4})$').firstMatch(key);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// 年代标签中文释义 (`year 2014` → `2014 年代画风`)
String? naiYearTagTranslation(String tagName) {
  final year = parseNaiYearTag(tagName);
  return year == null ? null : '$year 年代画风';
}
