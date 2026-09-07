import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_blocks.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('根级 CallbackShortcuts: 输入框聚焦时 Ctrl+O 仍可冒泡触发', (tester) async {
    var toggled = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () =>
                  toggled++,
            },
            child: Focus(
              autofocus: true,
              child: TextField(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(toggled, 1);
    controller.dispose();
  });

  testWidgets('ThinkingBlock: forceExpanded 展开正文，关闭后恢复折叠', (tester) async {
    Finder body() => find.text('第一段思考\n第二段思考', findRichText: true);
    Widget build(bool expanded) =>
        _wrap(ThinkingBlock(thoughts: '第一段思考\n第二段思考', forceExpanded: expanded));
    await tester.pumpWidget(build(false));
    expect(body(), findsNothing);
    await tester.pumpWidget(build(true));
    expect(body(), findsOneWidget);
    await tester.pumpWidget(build(false));
    expect(body(), findsNothing);
  });
}
