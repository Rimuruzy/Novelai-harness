import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StreamingViewModel extends StudioViewModel {
  _StreamingViewModel(String directory) : super(sessionLogBaseDir: directory);
  bool _streaming = true;
  int abortCount = 0;
  @override
  bool get isChatStreaming => _streaming;
  @override
  Future<void> abortChat() async {
    abortCount++;
    _streaming = false;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _StreamingViewModel vm;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('escape_test_');
    SharedPreferences.setMockInitialValues({});
    vm = _StreamingViewModel(directory.path);
    await vm.init();
  });
  tearDown(() async {
    vm.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  testWidgets('输入框聚焦时单击 Esc 中断，长按不触发回溯', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 400, child: AgentChatCard(viewModel: vm)),
        ),
      ),
    );
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(vm.abortCount, 1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(vm.abortCount, 1);
    expect(find.text('回溯历史时刻'), findsNothing);
    // Flutter 测试框架会自动报告未处理异常。
  });
}
