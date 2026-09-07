import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_blocks.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('折叠详情按需构建，收起后移除', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      _wrap(
        CollapsibleTile(
          header: const Text('详情'),
          bodyBuilder: (_) {
            builds++;
            return const Text('完整输出');
          },
        ),
      ),
    );
    expect(builds, 0);
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(builds, 1);
    expect(find.text('完整输出'), findsOneWidget);
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text('完整输出'), findsNothing);
  });

  testWidgets('思考、调用和结果轨道对齐并连续', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            AssistantMessageItem(
              message: AgentMessage(
                id: 'assistant',
                role: AgentRole.assistant,
                content: '',
                thoughts: '规划',
                toolCalls: [
                  ToolCall(id: 'call', name: 'search', arguments: {}),
                ],
              ),
            ),
            ToolResultBlock(
              message: AgentMessage(
                id: 'result',
                role: AgentRole.tool,
                content: '结果',
                toolName: 'search',
              ),
            ),
          ],
        ),
      ),
    );
    final steps = find.byType(AgentTimelineStep);
    expect(steps, findsNWidgets(3));
    for (var i = 1; i < 3; i++) {
      expect(
        tester.getTopLeft(steps.at(i)).dx,
        tester.getTopLeft(steps.at(i - 1)).dx,
      );
      expect(
        tester.getTopLeft(steps.at(i)).dy,
        tester.getBottomLeft(steps.at(i - 1)).dy,
      );
    }
    expect(find.byType(Card), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅思考变化时复用 Markdown，正文变化时刷新', (tester) async {
    Widget stream(String thoughts, String content) =>
        _wrap(StreamingMessageBubble(thoughts: thoughts, content: content));
    await tester.pumpWidget(stream('思考', '正文'));
    final original = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    await tester.pumpWidget(stream('思考继续', '正文'));
    expect(
      identical(
        original,
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)),
      ),
      isTrue,
    );
    await tester.pumpWidget(stream('思考继续', '正文更新'));
    expect(tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data, '正文更新');
  });

  test('首条有效行提取不受空行和 CRLF 干扰', () {
    expect(firstNonEmptyLine('\n  \r\n  第一行\r\n第二行'), '第一行');
    expect(firstNonEmptyLine('  '), '');
  });
}
