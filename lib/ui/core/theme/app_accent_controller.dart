import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart';

/// 应用主题强调色全局单一事实源 (MD3 自适应取色)。
///
/// - 持有三段运行时状态：来源模式 / 取色方案 / 当前种子色 (null = 默认 Notion 蓝)；
/// - [StudioViewModel.updateConfig] 保存配置后调用 [syncFromConfig]；
/// - 自适应模式下 ViewModel 在选图/生图后调用 [applyAdaptiveSeed] 注入图片主色；
/// - `main.dart` 根节点监听 [state] 局部重建 `MaterialApp.theme/darkTheme`，
///   主题切换由 MaterialApp 内建 200ms 动画平滑过渡，不经过 `notifyListeners()`。
///
/// 故意不放在 ViewModel/Mixin 上：强调色是应用级 (MaterialApp 根) 状态，
/// 生命周期长于任何一个工作台会话 (与 AppThemeModeController 同构)。
@immutable
class AccentThemeState {
  /// 来源模式
  final AppAccentMode mode;

  /// MD3 取色方案
  final AppAccentVariant variant;

  /// 当前种子色 (null = 默认 Notion 蓝，不注入)
  final Color? seed;

  const AccentThemeState({
    required this.mode,
    required this.variant,
    this.seed,
  });

  bool get isAdaptive => mode == AppAccentMode.adaptive;

  /// 种子或方案变化才视为状态变化 (mode 变化但种子未定不触发重建)
  AccentThemeState copyWith({Color? seed, AppAccentVariant? variant}) =>
      AccentThemeState(
        mode: mode,
        variant: variant ?? this.variant,
        seed: seed ?? this.seed,
      );

  @override
  bool operator ==(Object other) =>
      other is AccentThemeState &&
      other.mode == mode &&
      other.variant == variant &&
      other.seed?.toARGB32() == seed?.toARGB32();

  @override
  int get hashCode =>
      Object.hash(mode, variant, seed?.toARGB32());
}

class AppAccentController {
  AppAccentController._();

  /// 全局唯一实例 (应用生命周期级别，永不 dispose)
  static final AppAccentController instance = AppAccentController._();

  /// 当前生效的强调色状态 (初始默认蓝，main 启动时会按配置立即校正)
  final ValueNotifier<AccentThemeState> state = ValueNotifier(
    const AccentThemeState(
      mode: AppAccentMode.defaultBlue,
      variant: AppAccentVariant.tonalSpot,
    ),
  );

  /// 配置保存/加载后同步；仅状态真正变化时通知。
  void syncFromConfig(AppConfig config) {
    final seedArgb = parseSeedColorText(config.accentSeedColor);
    final target = AccentThemeState(
      mode: config.accentMode,
      variant: config.accentVariant,
      seed: seedArgb == null ? null : Color(seedArgb),
    );
    // 自适应模式保留运行时已提取的种子 (配置里没有“当前图片色”)，
    // 只同步方案变化；mode 必须显式写入 (copyWith 不携带 mode)
    if (config.accentMode == AppAccentMode.adaptive) {
      final current = state.value;
      if (current.isAdaptive &&
          current.variant == config.accentVariant &&
          current.seed != null) {
        return;
      }
      state.value = AccentThemeState(
        mode: AppAccentMode.adaptive,
        variant: config.accentVariant,
        seed: current.isAdaptive ? current.seed : null,
      );
      return;
    }
    if (state.value != target) {
      state.value = target;
    }
  }

  /// 自适应模式：注入从当前图片提取的种子色 (非自适应模式忽略)
  void applyAdaptiveSeed(Color seed) {
    final current = state.value;
    if (!current.isAdaptive) return;
    if (current.seed?.toARGB32() == seed.toARGB32()) return;
    state.value = AccentThemeState(
      mode: current.mode,
      variant: current.variant,
      seed: seed,
    );
  }

  /// 手动模式：立即应用种子色 (持久化由调用方经 updateConfig 落盘)
  void applyManualSeed(Color seed) {
    final current = state.value;
    state.value = AccentThemeState(
      mode: AppAccentMode.manual,
      variant: current.variant,
      seed: seed,
    );
  }

  /// 测试辅助：复位为出厂默认蓝
  @visibleForTesting
  void resetForTest() {
    state.value = const AccentThemeState(
      mode: AppAccentMode.defaultBlue,
      variant: AppAccentVariant.tonalSpot,
    );
  }
}
