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

/// 完整应用握把回归：静态变高列表也会随懒加载窗口重估总高度。
/// 数据冻结只能隔离实时增删，不能稳定 SliverList 的估算值。
/// 同时覆盖静态往返、手势取消、流式增长/收尾与松手解冻，
/// 并断言实际发生滚动，禁止未命中握把时零位移假通过。
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

  testWidgets('静态变高消息: 握把跨懒加载窗口往返不跳位', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();
    final vm = StudioView.testViewModelHook!;
    vm.setMessagesForTesting([
      for (var i = 0; i < 100; i++)
        AgentMessage(
          id: 'varied_$i',
          role: AgentRole.assistant,
          content:
              '消息 $i\n${'内容行\n' * (i < 15
                      ? 2
                      : i < 45
                      ? 45
                      : 8)}',
        ),
    ]);
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byType(AgentChatCard),
        matching: find.byType(ListView),
      ),
    );
    final controller = list.controller!;
    controller.jumpTo(100);
    await tester.pump();
    controller.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final bar = find
        .byWidgetPredicate((w) => w is RawScrollbar)
        .evaluate()
        .firstWhere((e) => (e.widget as RawScrollbar).controller == controller);
    final rect = tester.getRect(find.byWidget(bar.widget));
    final pos = controller.position;
    final thumb =
        (rect.height *
                rect.height /
                (pos.maxScrollExtent + pos.viewportDimension))
            .clamp(18.0, rect.height);
    final ratio = pos.maxScrollExtent / (rect.height - thumb);
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: Offset(rect.right - 8, rect.top + 20));
    await hover.moveTo(Offset(rect.right - 8, rect.top + 20));
    await tester.pump(const Duration(milliseconds: 200));
    final painter =
        tester
                .widget<CustomPaint>(
                  find
                      .descendant(
                        of: find.byWidget(bar.widget),
                        matching: find.byWidgetPredicate(
                          (w) =>
                              w is CustomPaint &&
                              w.foregroundPainter is ScrollbarPainter,
                        ),
                      )
                      .first,
                )
                .foregroundPainter!
            as ScrollbarPainter;
    Offset? hit;
    for (var y = 4.0; y < rect.height && hit == null; y++) {
      for (var x = rect.width - 16; x < rect.width; x++) {
        if (painter.hitTest(Offset(x, y)) == true) {
          hit = rect.topLeft + Offset(x + 2, y + 6);
          break;
        }
      }
    }
    expect(hit, isNotNull, reason: '真实 painter 握把必须可命中');
    final gesture = await tester.startGesture(
      hit!,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 4));
    await tester.pump();
    expect(pos.pixels, greaterThan(0), reason: '必须实际命中握把并开始滚动');
    final extents = <double>{};
    for (final direction in [1.0, -1.0]) {
      for (var step = 0; step < 45; step++) {
        final before = pos.pixels;
        extents.add(pos.maxScrollExtent);
        await gesture.moveBy(Offset(0, direction * 4));
        await tester.pump();
        final delta = pos.pixels - before;
        expect(
          delta.abs(),
          lessThanOrEqualTo(ratio * 4 * 1.5 + 1),
          reason:
              'step=$step dir=$direction before=$before extent=${pos.maxScrollExtent}',
        );
        expect(
          delta * direction,
          greaterThanOrEqualTo(-1),
          reason: '握把移动不可反向跳位',
        );
      }
    }
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(pos.isScrollingNotifier.value, isFalse, reason: '取消握把手势必须释放 Drag');
    await hover.removePointer();
    expect(extents.length, greaterThan(1), reason: '必须跨越非等高懒加载窗口');
    debugDefaultTargetPlatformOverride = null;
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
        .byWidgetPredicate((w) => w is RawScrollbar)
        .evaluate()
        .firstWhere(
          (element) =>
              (element.widget as RawScrollbar).controller == controller,
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
    final thumbOffset =
        (position.pixels / position.maxScrollExtent) *
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
      expect(after, lessThan(before), reason: '必须真实拖动握把，不能零位移假通过');
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

    final ratio =
        controller.position.maxScrollExtent /
        controller.position.viewportDimension;
    final maxJump = moves.map((d) => d.abs()).reduce((a, b) => a > b ? a : b);
    expect(maxJump, lessThan(ratio * 4 * 3));
  });
}
