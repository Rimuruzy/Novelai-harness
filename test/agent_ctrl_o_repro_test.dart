import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 与 StudioView 相同的快捷键装配：根级 CallbackShortcuts + Focus(autofocus)
Widget _buildStudioLikeApp(StudioViewModel viewModel) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            viewModel.toggleThinkingExpanded(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SizedBox(
            height: 700,
            width: 420,
            child: ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) => AgentChatCard(viewModel: viewModel),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StudioViewModel viewModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ctrl_o_test');
    viewModel = StudioViewModel();
    await viewModel.init();
    viewModel.setMessagesForTesting([
      AgentMessage(
        id: 'assistant_1',
        role: AgentRole.assistant,
        content: '正文内容',
        thoughts: '思考内容第一行\n思考内容第二行',
      ),
    ]);
  });

  tearDown(() async {
    viewModel.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Finder thinkingBody() => find.text('思考内容第一行\n思考内容第二行', findRichText: true);

  Future<void> pressCtrlO(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('Ctrl+O 展开/折叠思考块 (焦点在根节点)', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_buildStudioLikeApp(viewModel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(thinkingBody(), findsNothing);
    await pressCtrlO(tester);
    expect(viewModel.isThinkingExpanded, isTrue);
    expect(thinkingBody(), findsOneWidget);
    await pressCtrlO(tester);
    expect(viewModel.isThinkingExpanded, isFalse);
    expect(thinkingBody(), findsNothing);
  });

  testWidgets('Ctrl+O 在对话输入框聚焦时同样生效', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_buildStudioLikeApp(viewModel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 聚焦对话输入框
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(thinkingBody(), findsNothing);

    await pressCtrlO(tester);
    expect(viewModel.isThinkingExpanded, isTrue);
    expect(thinkingBody(), findsOneWidget);
  });
}
