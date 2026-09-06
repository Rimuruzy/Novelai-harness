import 'package:flutter/material.dart' show Brightness, Color, immutable;
import 'package:material_color_utilities/material_color_utilities.dart';

import '../../../data/services/config_service.dart';

/// MD3 动态取色推导出的主题强调色令牌组。
///
/// 种子色经 [DislikeAnalyzer] 修正后，按选定方案 ([SchemeTonalSpot] 等 8 种)
/// 构建完整 DynamicScheme，取 primary tonal palette 不同 tone 档位映射到
/// 本项目的强调色 token 体系 (primary / primaryLight / primaryDark / primaryTint)。
/// 中性色 (背景/文字/边框) 保持 Notion 观感不参与映射，避免整站洗色。
@immutable
class M3AccentTokens {
  /// 主强调色 (亮色 = tone 40，暗色 = tone 80，随方案自适应对比度)
  final Color primary;

  /// 主强调色上的前景文字色
  final Color onPrimary;

  /// 次级强调 (轻量高亮/滑块轨道/选中态装饰)
  final Color primaryLight;

  /// 深档强调 (按压/悬浮加深态)
  final Color primaryDark;

  /// 极浅底色 (Ghost CTA 背景/选中行底色)
  final Color primaryTint;

  const M3AccentTokens({
    required this.primary,
    required this.onPrimary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primaryTint,
  });
}

/// 从种子色推导 MD3 强调色令牌
///
/// [seed] 任意图片主色；[variant] 取色方案；[brightness] 目标主题亮度。
M3AccentTokens buildM3AccentTokens({
  required Color seed,
  required Brightness brightness,
  required AppAccentVariant variant,
}) {
  // Android 同款处理：种子色落在「被嫌弃」色域 (浑浊橙/棕) 时先拉回可用的种子
  final source = DislikeAnalyzer.fixIfDisliked(Hct.fromInt(seed.toARGB32()));
  final isDark = brightness == Brightness.dark;
  final DynamicScheme scheme = switch (variant) {
    AppAccentVariant.tonalSpot => SchemeTonalSpot(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.vibrant => SchemeVibrant(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.expressive => SchemeExpressive(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.content => SchemeContent(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.neutral => SchemeNeutral(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.monochrome => SchemeMonochrome(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.rainbow => SchemeRainbow(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.fruitSalad => SchemeFruitSalad(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
  };

  final primaryPalette = scheme.primaryPalette;
  if (!isDark) {
    return M3AccentTokens(
      primary: Color(scheme.primary),
      onPrimary: Color(scheme.onPrimary),
      primaryLight: Color(primaryPalette.get(60)),
      primaryDark: Color(primaryPalette.get(30)),
      primaryTint: Color(primaryPalette.get(92)),
    );
  }
  return M3AccentTokens(
    primary: Color(scheme.primary),
    onPrimary: Color(scheme.onPrimary),
    primaryLight: Color(primaryPalette.get(68)),
    primaryDark: Color(primaryPalette.get(40)),
    primaryTint: Color(scheme.primary).withValues(alpha: 0.15),
  );
}
