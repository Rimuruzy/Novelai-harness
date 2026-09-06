import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/llm_cache_config.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_dropdown.dart';
import 'package:novelai_harness/ui/features/settings/widgets/model_cache_settings.dart';

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets('cache controls render and preserve choices in $language', (
      tester,
    ) async {
      var value = const LlmCacheConfig();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, setState) => ModelCacheSettings(
                      value: value,
                      onChanged: (next) => setState(() => value = next),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDropdown<LlmCacheMode>), findsOneWidget);
      final mode = tester.widget<AppDropdown<LlmCacheMode>>(
        find.byType(AppDropdown<LlmCacheMode>),
      );
      mode.onChanged(LlmCacheMode.anthropic);
      await tester.pumpAndSettle();
      tester
          .widget<AppDropdown<LlmCacheRetention>>(
            find.byType(AppDropdown<LlmCacheRetention>),
          )
          .onChanged(LlmCacheRetention.long);
      await tester.pumpAndSettle();
      tester
          .widget<AppDropdown<LlmCacheAffinity>>(
            find.byType(AppDropdown<LlmCacheAffinity>),
          )
          .onChanged(LlmCacheAffinity.openrouter);
      await tester.pumpAndSettle();
      expect(value.mode, LlmCacheMode.anthropic);
      expect(value.retention, LlmCacheRetention.long);
      expect(value.affinity, LlmCacheAffinity.openrouter);
      tester
          .widget<AppDropdown<LlmCacheMode>>(
            find.byType(AppDropdown<LlmCacheMode>),
          )
          .onChanged(LlmCacheMode.off);
      await tester.pumpAndSettle();
      expect(find.byType(AppDropdown<LlmCacheRetention>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
