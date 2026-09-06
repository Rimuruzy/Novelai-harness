import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/widgets/app_color_picker_dialog.dart';
import 'package:novelai_harness/ui/features/settings/widgets/general_settings_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapApp(Widget child) => MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('parseHexField 十六进制解析', () {
    test('合法输入 (带#、不带#、小写) 正确解析', () {
      expect(parseHexField('#E32D14'), const Color(0xFFE32D14));
      expect(parseHexField('E32D14'), const Color(0xFFE32D14));
      expect(parseHexField('#e32d14'), const Color(0xFFE32D14));
      expect(parseHexField(' #0075DE '), const Color(0xFF0075DE));
    });

    test('非法输入返回 null', () {
      expect(parseHexField(''), isNull);
      expect(parseHexField('#12345'), isNull);
      expect(parseHexField('#1234567'), isNull);
      expect(parseHexField('#zzzzzz'), isNull);
      expect(parseHexField('  '), isNull);
    });
  });

  group('AppColorPickerDialog', () {
    testWidgets('展示初始色并原样保存返回', (tester) async {
      Color? result = const Color(0xFF123456);
      await tester.pumpWidget(
        wrapApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await AppColorPickerDialog.show(
                    context,
                    initialColor: const Color(0xFFE32D14),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 初始色 hex 回显
      expect(find.text('#E32D14'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, const Color(0xFFE32D14));
    });

    testWidgets('点选预设色后保存返回该色', (tester) async {
      Color? result;
      await tester.pumpWidget(
        wrapApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await AppColorPickerDialog.show(
                    context,
                    initialColor: const Color(0xFF0075DE),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 点击紫色预设色块
      final swatch = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final decoration = w.decoration;
        return decoration is BoxDecoration &&
            decoration.color == const Color(0xFF7B1FA2);
      });
      expect(swatch, findsOneWidget);
      await tester.tap(swatch, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('#7B1FA2'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, const Color(0xFF7B1FA2));
    });

    testWidgets('点击色相条带左端改变颜色', (tester) async {
      Color? result;
      await tester.pumpWidget(
        wrapApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await AppColorPickerDialog.show(
                    context,
                    initialColor: const Color(0xFF0075DE),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('#0075DE'), findsOneWidget);

      // 点击「色相」标签下方的条带最左端 (hue → 0，红色系)
      final labelRect = tester.getRect(find.text('色相'));
      await tester.tapAt(Offset(labelRect.left + 4, labelRect.bottom + 12));
      await tester.pumpAndSettle();

      // 颜色已不再是初始蓝，hex 文本已更新
      expect(find.text('#0075DE'), findsNothing);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result, isNot(const Color(0xFF0075DE)));
    });

    testWidgets('取消返回 null', (tester) async {
      Color? result = const Color(0xFF123456);
      await tester.pumpWidget(
        wrapApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await AppColorPickerDialog.show(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('GeneralSettingsTab 种子色入口', () {
    testWidgets('点色块打开取色器，选色保存后草稿切换手动模式', (tester) async {
      final draft = GeneralSettingsDraft(const AppConfig());
      addTearDown(draft.dispose);
      expect(draft.accentMode, AppAccentMode.defaultBlue);
      expect(draft.accentSeedColor, isNull);

      await tester.pumpWidget(wrapApp(GeneralSettingsTab(draft: draft)));
      expect(find.text('种子色'), findsOneWidget);

      // 点击种子色色块打开取色器
      await tester.tap(find.byTooltip('种子色'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('预设颜色'), findsOneWidget);

      // 选万寿菊黄预设并保存
      final swatch = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final decoration = w.decoration;
        return decoration is BoxDecoration &&
            decoration.color == const Color(0xFFFFB110);
      });
      await tester.tap(swatch, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(draft.accentMode, AppAccentMode.manual);
      expect(draft.accentSeedColor, '#FFB110');
    });
  });
}
