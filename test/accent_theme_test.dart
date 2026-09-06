import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/palette_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_accent_controller.dart';
import 'package:novelai_harness/ui/core/theme/app_colors_extension.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/theme/md3_accent.dart';
import 'package:novelai_harness/ui/features/settings/widgets/general_settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('强调色配置解析与持久化', () {
    test('AppAccentMode 解析：未知值回退默认蓝', () {
      expect(parseAccentMode(null), AppAccentMode.defaultBlue);
      expect(parseAccentMode('garbage'), AppAccentMode.defaultBlue);
      expect(parseAccentMode('adaptive'), AppAccentMode.adaptive);
      expect(parseAccentMode('manual'), AppAccentMode.manual);
    });

    test('AppAccentVariant 解析与存储往返一致', () {
      expect(parseAccentVariant(null), AppAccentVariant.tonalSpot);
      for (final variant in AppAccentVariant.values) {
        expect(parseAccentVariant(accentVariantStorage(variant)), variant);
      }
    });

    test('种子色 ↔ #RRGGBB 文本往返', () {
      expect(parseSeedColorText(null), isNull);
      expect(parseSeedColorText('zzzzzz'), isNull);
      expect(parseSeedColorText('#E32D14'), 0xFFE32D14);
      expect(seedColorText(0xFFE32D14), '#E32D14');
      expect(seedColorText(null), isNull);
      // 往返
      expect(parseSeedColorText(seedColorText(0xFF0075DE)), 0xFF0075DE);
    });

    test('AppConfig 出厂默认与 copyWith 透传', () {
      const config = AppConfig();
      expect(config.accentMode, AppAccentMode.defaultBlue);
      expect(config.accentVariant, AppAccentVariant.tonalSpot);
      expect(config.accentSeedColor, isNull);

      final updated = config.copyWith(
        accentMode: AppAccentMode.adaptive,
        accentVariant: AppAccentVariant.vibrant,
        accentSeedColor: '#E32D14',
      );
      expect(updated.accentMode, AppAccentMode.adaptive);
      expect(updated.accentVariant, AppAccentVariant.vibrant);
      expect(updated.accentSeedColor, '#E32D14');
      // 不传时保持原值
      expect(updated.copyWith().accentSeedColor, '#E32D14');
    });

    test('saveConfig → loadConfig 往返不丢失', () async {
      SharedPreferences.setMockInitialValues({});
      final service = ConfigService();
      await service.saveConfig(
        const AppConfig(
          accentMode: AppAccentMode.manual,
          accentVariant: AppAccentVariant.expressive,
          accentSeedColor: '#FFB110',
        ),
      );
      final loaded = await service.loadConfig();
      expect(loaded.accentMode, AppAccentMode.manual);
      expect(loaded.accentVariant, AppAccentVariant.expressive);
      expect(loaded.accentSeedColor, '#FFB110');
    });

    test('旧版本无 accent 键时回退出厂默认', () async {
      SharedPreferences.setMockInitialValues({'novelai_opus_free_mode': false});
      final loaded = await ConfigService().loadConfig();
      expect(loaded.accentMode, AppAccentMode.defaultBlue);
      expect(loaded.accentVariant, AppAccentVariant.tonalSpot);
      expect(loaded.accentSeedColor, isNull);
    });
  });

  group('PaletteService 主色提取', () {
    test('纯色图片提取出该主色为种子', () async {
      final bytes = _encodeSolidPng(0xFF, 0x2D, 0x14);
      final palette = await PaletteService.instance.extract(bytes);
      expect(palette, isNotNull);
      expect(palette!.colors, isNotEmpty);
      // 种子应落在偏红区域 (Vermillion 红色调)
      final seed = Hct.fromInt(palette.seed);
      expect(seed.hue, greaterThanOrEqualTo(0));
      expect(seed.hue, lessThan(60));
    });

    test('多色渐变图片提取出多个主色且占比归一', () async {
      final image = img.Image(width: 120, height: 40);
      for (var x = 0; x < 120; x++) {
        final half = x < 60;
        for (var y = 0; y < 40; y++) {
          image.setPixelRgba(
            x,
            y,
            half ? 220 : 30,
            half ? 30 : 180,
            half ? 40 : 240,
            255,
          );
        }
      }
      final palette = await PaletteService.instance.extract(
        img.encodePng(image),
      );
      expect(palette, isNotNull);
      expect(palette!.colors.length, greaterThanOrEqualTo(2));
      final shareSum = palette.colors.fold<double>(
        0,
        (sum, c) => sum + c.share,
      );
      expect(shareSum, lessThanOrEqualTo(1.0001));
    });

    test('空字节与非法字节返回 null', () async {
      expect(await PaletteService.instance.extract(Uint8List(0)), isNull);
      expect(
        await PaletteService.instance.extract(
          Uint8List.fromList([0x00, 0x01, 0x02, 0x03]),
        ),
        isNull,
      );
    });

    test('cacheKey 命中 LRU 缓存 (同一实例)', () async {
      final bytes = _encodeSolidPng(0x10, 0x99, 0x60);
      final first = await PaletteService.instance.extract(
        bytes,
        cacheKey: 'cache-test',
      );
      final second = await PaletteService.instance.extract(
        bytes,
        cacheKey: 'cache-test',
      );
      expect(identical(first, second), isTrue);
    });
  });

  group('MD3 强调色令牌', () {
    const seed = Color(0xFFE32D14);

    test('亮暗两套令牌主色 tone 档位不同', () {
      final light = buildM3AccentTokens(
        seed: seed,
        brightness: Brightness.light,
        variant: AppAccentVariant.tonalSpot,
      );
      final dark = buildM3AccentTokens(
        seed: seed,
        brightness: Brightness.dark,
        variant: AppAccentVariant.tonalSpot,
      );
      // 亮色主色较深、暗色主色较浅
      expect(_luminance(light.primary), lessThan(_luminance(dark.primary)));
      // 亮色底色应为高明度浅色
      expect(_luminance(light.primaryTint), greaterThan(0.8));
      // 全部不透明
      for (final color in [
        light.primary,
        light.primaryLight,
        light.primaryDark,
        light.primaryTint,
        dark.primary,
        dark.primaryLight,
        dark.primaryDark,
      ]) {
        expect(color.a, 1.0);
      }
    });

    test('不同取色方案推导结果不同', () {
      final tonalSpot = buildM3AccentTokens(
        seed: seed,
        brightness: Brightness.light,
        variant: AppAccentVariant.tonalSpot,
      );
      final vibrant = buildM3AccentTokens(
        seed: seed,
        brightness: Brightness.light,
        variant: AppAccentVariant.vibrant,
      );
      final monochrome = buildM3AccentTokens(
        seed: seed,
        brightness: Brightness.light,
        variant: AppAccentVariant.monochrome,
      );
      expect(tonalSpot.primary, isNot(vibrant.primary));
      expect(tonalSpot.primary, isNot(monochrome.primary));
    });
  });

  group('AppTheme 种子注入', () {
    test('无种子时与原生 Notion 主题一致', () {
      final built = AppTheme.buildTheme(Brightness.light);
      expect(built.primaryColor, AppTheme.lightTheme.primaryColor);
      final ext = built.extension<AppColorsExtension>();
      expect(ext, isNotNull);
      expect(ext!.primary, AppColorsExtension.light.primary);
    });

    test('注入种子后仅强调色族变化 (中性色保持 Notion)', () {
      final built = AppTheme.buildTheme(
        Brightness.dark,
        seed: const Color(0xFFE32D14),
        variant: AppAccentVariant.vibrant,
      );
      final base = AppColorsExtension.dark;
      final ext = built.extension<AppColorsExtension>()!;
      // 强调色族已替换
      expect(ext.primary, isNot(base.primary));
      expect(ext.accent, ext.primary);
      expect(ext.borderFocus, ext.primary);
      // 中性色不动
      expect(ext.canvasBackground, base.canvasBackground);
      expect(ext.cardBackground, base.cardBackground);
      expect(ext.textPrimary, base.textPrimary);
      expect(ext.borderDefault, base.borderDefault);
      expect(ext.tagArtist, base.tagArtist);
      // ColorScheme 同步注入
      expect(built.colorScheme.primary, ext.primary);
    });
  });

  group('AppAccentController', () {
    setUp(AppAccentController.instance.resetForTest);

    test('syncFromConfig 手动种子生效', () {
      final controller = AppAccentController.instance;
      controller.syncFromConfig(
        const AppConfig(
          accentMode: AppAccentMode.manual,
          accentSeedColor: '#FFB110',
        ),
      );
      expect(controller.state.value.mode, AppAccentMode.manual);
      expect(controller.state.value.seed, const Color(0xFFFFB110));
    });

    test('自适应模式保留运行时种子', () {
      final controller = AppAccentController.instance;
      controller.syncFromConfig(
        const AppConfig(accentMode: AppAccentMode.adaptive),
      );
      controller.applyAdaptiveSeed(const Color(0xFF0F9960));
      expect(controller.state.value.seed, const Color(0xFF0F9960));
      // 再次 sync (如其它设置保存) 不清空运行时种子
      controller.syncFromConfig(
        const AppConfig(
          accentMode: AppAccentMode.adaptive,
          accentVariant: AppAccentVariant.rainbow,
        ),
      );
      expect(controller.state.value.seed, const Color(0xFF0F9960));
      expect(controller.state.value.variant, AppAccentVariant.rainbow);
    });

    test('applyAdaptiveSeed 在非自适应模式下被忽略', () {
      final controller = AppAccentController.instance;
      controller.applyAdaptiveSeed(const Color(0xFF0F9960));
      expect(controller.state.value.seed, isNull);
    });

    test('同值种子重复应用不触发通知', () {
      final controller = AppAccentController.instance;
      controller.syncFromConfig(
        const AppConfig(accentMode: AppAccentMode.adaptive),
      );
      controller.applyAdaptiveSeed(const Color(0xFF0F9960));
      var notifications = 0;
      void listener() => notifications++;
      controller.state.addListener(listener);
      controller.applyAdaptiveSeed(const Color(0xFF0F9960));
      expect(notifications, 0);
      controller.state.removeListener(listener);
    });
  });

  group('GeneralSettingsTab 强调色选择器', () {
    testWidgets('渲染强调色与取色方案卡片并切换草稿', (tester) async {
      final draft = GeneralSettingsDraft(const AppConfig());
      addTearDown(draft.dispose);
      expect(draft.accentMode, AppAccentMode.defaultBlue);
      expect(draft.accentVariant, AppAccentVariant.tonalSpot);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: GeneralSettingsTab(draft: draft)),
        ),
      );

      expect(find.text('强调色'), findsOneWidget);
      expect(find.text('取色方案'), findsOneWidget);
      expect(find.text('默认蓝色'), findsOneWidget);
      expect(find.text('色斑 (默认)'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<AppAccentMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随图片').last);
      await tester.pumpAndSettle();
      expect(draft.accentMode, AppAccentMode.adaptive);
    });
  });
}

// ------------------------- 测试辅助 -------------------------

/// 构造纯色图并编码为 PNG 字节
Uint8List _encodeSolidPng(int r, int g, int b) {
  final image = img.Image(width: 64, height: 64);
  for (final pixel in image) {
    pixel.setRgba(r, g, b, 255);
  }
  return img.encodePng(image);
}

double _luminance(Color color) => color.computeLuminance();
