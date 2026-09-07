import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/features/studio/views/studio_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 完整应用装配下的握把拖拽瞬移回归：
/// Flutter RawScrollbar._getPrimaryDelta 以「拖拽起点握把位置 × 当前内容
/// 高度」做绝对映射，拖拽途中内容高度变化 (流式增长 / 流式结束气泡消失
/// 收缩) 会污染映射基准，下一次握把移动按污染映射瞬移；方向冲突增量
/// 兜底仅覆盖「增长+上翻」等半数组合。修复：手势期间冻结消息列表渲染
/// 数据源 (消息/流式气泡/提问卡片/思考展开态快照)，内容高度恒定、
/// 映射自洽，手势结束恢复实时数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('scrollbar_fullapp_test');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('完整应用: 流式增长中握把拖拽观察位移', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    AppLocaleController.instance.syncFromConfig(
      const AppConfig(localePreference: AppLocalePreference.zh),
    );
    addTearDown(AppLocaleController.instance.resetForTest);

    // 应用自建 MaterialApp 主题未锁 platform，经 defaultTargetPlatform
    // 继承该覆写，从而让桌面端自动滚动条插入
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final viewModel = StudioView.testViewModelHook;
    expect(viewModel, isNotNull);
    viewModel!.setMessagesForTesting([
      for (var i = 0; i < 40; i++)
        AgentMessage(
          id: 'full_m$i',
          role: i.isEven ? AgentRole.user : AgentRole.assistant,
          content: '第 $i 条消息 ${'内容行\n' * 6}',
        ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 找 AgentChatCard 内的消息 ListView 与其控制器
    final cardFinder = find.byType(AgentChatCard);
    expect(cardFinder, findsOneWidget);
    final listView = tester.widget<ListView>(
      find.descendant(of: cardFinder, matching: find.byType(ListView)),
    );
    final controller = listView.controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    // 开启流式
    viewModel.setChatStreamingForTesting(true);
    viewModel.streamingText.appendContent('流式正文开头\n' * 3);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    // 定位滚动条握把
    final scrollbarElement = find
        .byType(Scrollbar)
        .evaluate()
        .firstWhere(
          (element) => (element.widget as Scrollbar).controller == controller,
        );
    final scrollbarRect = tester.getRect(
      find.byWidget(scrollbarElement.widget),
    );
    final position = controller.position;
    final trackExtent = scrollbarRect.height;
    final contentExtent = position.maxScrollExtent + position.viewportDimension;
    final thumbExtent = (trackExtent * trackExtent / contentExtent).clamp(
      18.0,
      trackExtent,
    );
    final thumbOffset = (position.pixels / position.maxScrollExtent) *
        (trackExtent - thumbExtent);
    final thumbCenter = Offset(
      scrollbarRect.right - 3,
      scrollbarRect.top + thumbOffset + thumbExtent / 2,
    );

    final gesture = await tester.startGesture(
      thumbCenter,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    // 捏住不动 600ms，流式持续增长：冻结期内容高度必须恒定
    final maxExtentAtDragStart = controller.position.maxScrollExtent;
    final pixelsAtDragStart = controller.position.pixels;
    for (var i = 0; i < 12; i++) {
      viewModel.streamingText.appendContent('静默期增量 $i\n' * 4);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      controller.position.maxScrollExtent,
      closeTo(maxExtentAtDragStart, 0.5),
      reason: '握把按住期间流式增长不得改变内容高度 (冻结生效)',
    );
    expect(
      controller.position.pixels,
      closeTo(pixelsAtDragStart, 0.5),
      reason: '握把按住期间跟随不得在冷却窗过后把视口拽回底部',
    );

    // 先拖离底部 30px 拇指，稳定在中部
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();

    // 关键场景：拖拽途中流式结束，大段瞬态内容 (气泡/进度提示) 收缩消失
    viewModel.setChatStreamingForTesting(false);
    await tester.pump();
    expect(
      controller.position.maxScrollExtent,
      closeTo(maxExtentAtDragStart, 0.5),
      reason: '握把按住期间流式结束收缩不得改变内容高度 (冻结生效)',
    );

    // 收缩后小幅移动握把，观察是否瞬移
    final moves = <double>[];
    for (var i = 0; i < 4; i++) {
      final before = controller.position.pixels;
      await gesture.moveBy(const Offset(0, -4));
      await tester.pump();
      final after = controller.position.pixels;
      moves.add(after - before);
    }

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      controller.position.maxScrollExtent,
      isNot(closeTo(maxExtentAtDragStart, 0.5)),
      reason: '松手后冻结解除，实时内容高度恢复 (流式气泡已消失)',
    );

    // 框架不变量检查在 addTearDown 之前跑，手动即时复位
    debugDefaultTargetPlatformOverride = null;

    final ratio = controller.position.maxScrollExtent /
        controller.position.viewportDimension;
    final maxJump = moves.map((d) => d.abs()).reduce((a, b) => a > b ? a : b);
    expect(maxJump, lessThan(ratio * 4 * 3));
  });
}
