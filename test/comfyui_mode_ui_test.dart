import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/generate_dock.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompts_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioViewModel viewModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final configService = ConfigService();
    await configService.loadConfig();
    viewModel = StudioViewModel(
      configService: configService,
      repository: NovelAiRepository(service: NovelAiService()),
    );
    // ComfyUI 模式：地址指向必然拒绝的本机端口，状态探测快速失败，
    // 不依赖任何真实网络服务
    await viewModel.updateConfig(
      viewModel.config.copyWith(
        comfyUiEnabled: true,
        comfyUiBaseUrl: 'http://127.0.0.1:9',
      ),
    );
  });

  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    );
  }

  test('estimatedGenerationCost 在 ComfyUI 模式下恒为 0', () {
    expect(viewModel.isComfyUiMode, isTrue);
    expect(viewModel.estimatedGenerationCost, 0);
  });

  test('AppConfig ComfyUI 字段 copyWith 往返', () {
    final config = viewModel.config.copyWith(
      comfyUiEnabled: true,
      comfyUiBaseUrl: 'http://192.168.1.20:8188',
      comfyUiPromptNodeId: '10',
      comfyUiResolutionNodeId: '20',
      comfyUiParamsNodeId: '30',
    );
    expect(config.comfyUiEnabled, isTrue);
    expect(config.comfyUiBaseUrl, 'http://192.168.1.20:8188');
    expect(config.comfyUiPromptNodeId, '10');
    expect(config.comfyUiResolutionNodeId, '20');
    expect(config.comfyUiParamsNodeId, '30');
  });

  testWidgets('参数页 ComfyUI 模式：显示后端切换与连接卡，隐藏模型与采样器', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(ParametersPage(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    // 后端切换胶囊与 ComfyUI 连接状态卡
    expect(find.text('ComfyUI'), findsAtLeastNWidgets(1));

    // NovelAI 专属区块隐藏：模型选择 / Sampler 下拉 / 高级选项
    expect(find.text('模型'), findsNothing);
    expect(find.text('Sampler'), findsNothing);
  });

  testWidgets('参数页 NovelAI 模式：恢复模型选择与 Sampler 两栏', (
    WidgetTester tester,
  ) async {
    // 参数页较长，Sampler 两栏在默认 600 高视口之外：拉大视口保证全部构建
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await viewModel.updateConfig(
      viewModel.config.copyWith(comfyUiEnabled: false),
    );
    await tester.pumpWidget(
      buildTestWidget(ParametersPage(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    expect(find.text('模型'), findsOneWidget);
    expect(find.text('Sampler'), findsOneWidget);
    // 连接状态卡不再展示 (后端切换胶囊仍常驻，ComfyUI 仅作为未选中选项出现)
    expect(find.text('http://127.0.0.1:9'), findsNothing);
    expect(find.textContaining('ComfyUI 未连接'), findsNothing);
  });

  testWidgets('提示词页 ComfyUI 模式：隐藏质量词与 UC 预设工具条及 Token 状态条', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(PromptsPage(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Quality Tags'), findsNothing);
    expect(find.textContaining('UC Preset'), findsNothing);
    expect(find.textContaining('Transparent BG'), findsNothing);
  });

  testWidgets('提示词页 NovelAI 模式：恢复质量词与 UC 预设工具条', (
    WidgetTester tester,
  ) async {
    await viewModel.updateConfig(
      viewModel.config.copyWith(comfyUiEnabled: false),
    );
    await tester.pumpWidget(
      buildTestWidget(PromptsPage(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Quality Tags'), findsOneWidget);
    expect(find.textContaining('UC Preset'), findsOneWidget);
  });

  testWidgets('生成坞 ComfyUI 模式：账号栏换成 Bridge 状态行', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(GenerateDock(viewModel: viewModel)));
    await tester.pumpAndSettle();

    // 状态行出现 ComfyUI 字样与服务地址，主按钮仍为「生成图片」
    expect(find.textContaining('ComfyUI'), findsAtLeastNWidgets(1));
    expect(find.text('http://127.0.0.1:9'), findsOneWidget);
    expect(find.text('生成图片'), findsOneWidget);
    // 账号信息与点数相关文案不应出现
    expect(find.textContaining('Anlas'), findsNothing);
  });
}
