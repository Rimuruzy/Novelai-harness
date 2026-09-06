import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';

void main() {
  group('Pi cache accounting', () {
    test(
      'OpenAI input excludes reads and writes; total does not double count',
      () {
        final u = TokenUsage.fromOpenAiJson({
          'prompt_tokens': 1000,
          'completion_tokens': 50,
          'prompt_tokens_details': {
            'cached_tokens': 600,
            'cache_write_tokens': 100,
          },
        });
        expect(u.input, 300);
        expect(u.totalInput, 1000);
        expect(u.total, 1050);
        expect(u.cacheHitRate, 0.6);
        expect(TokenUsage.fromJson(u.toJson()).toJson(), u.toJson());
      },
    );

    for (final field in ['prompt_cache_hit_tokens', 'cached_tokens']) {
      test('reads $field fallback', () {
        final u = TokenUsage.fromOpenAiJson({'prompt_tokens': 100, field: 80});
        expect(u.cacheRead, 80);
        expect(u.input, 20);
        expect(u.cacheReadReported, isTrue);
      });
    }

    test('aliases are not added and explicit zero takes priority', () {
      final u = TokenUsage.fromOpenAiJson({
        'prompt_tokens': 100,
        'prompt_tokens_details': {'cached_tokens': 0},
        'prompt_cache_hit_tokens': 80,
        'cached_tokens': 80,
      });
      expect(u.cacheRead, 0);
      expect(u.cacheHitRate, 0);
      final d = TokenUsage.fromOpenAiJson({
        'prompt_tokens': 100,
        'prompt_cache_hit_tokens': 80,
        'cached_tokens': 80,
      });
      expect(d.cacheRead, 80);
    });

    test('absent, null and invalid values are not reported zeros', () {
      for (final raw in [null, '0', -1, double.nan]) {
        final u = TokenUsage.fromOpenAiJson({
          'prompt_tokens': 100,
          'prompt_tokens_details': {'cached_tokens': raw},
        });
        expect(u.cacheReadReported, isFalse);
        expect(u.cacheHitRate, isNull);
      }
      expect(
        TokenUsage.fromOpenAiJson({'prompt_tokens': 100}).cacheReadReported,
        isFalse,
      );
    });

    test('fully cached input is 100%, not undefined', () {
      final u = TokenUsage.fromOpenAiJson({
        'prompt_tokens': 100,
        'cached_tokens': 100,
      });
      expect(u.input, 0);
      expect(u.cacheHitRate, 1);
    });

    test(
      'completion tokens already include reasoning; reported totals are not a cache hint',
      () {
        final u = TokenUsage.fromOpenAiJson({
          'prompt_tokens': 4017,
          'completion_tokens': 1,
          'total_tokens': 4031,
          'completion_tokens_details': {'reasoning_tokens': 13},
        });
        expect(u.output, 1);
        expect(u.total, 4018);
        expect(u.cacheReadReported, isFalse);
      },
    );

    test('Pi normalized JSON is not summed with API aliases', () {
      final u = TokenUsage.fromJson({
        'input': 5,
        'prompt_tokens': 100,
        'cacheRead': 20,
        'cached_tokens': 30,
      });
      expect(u.input, 70);
      expect(u.cacheRead, 30);
    });

    test(
      'aggregation preserves absent vs zero and empty accumulator is neutral',
      () {
        final hit = TokenUsage.fromOpenAiJson({
          'prompt_tokens': 100,
          'cached_tokens': 80,
        });
        final zero = TokenUsage.fromOpenAiJson({
          'prompt_tokens': 100,
          'cached_tokens': 0,
        });
        final missing = TokenUsage.fromOpenAiJson({'prompt_tokens': 100});
        expect(const TokenUsage().add(hit).cacheHitRate, 0.8);
        expect(hit.add(zero).cacheHitRate, 0.4);
        expect(hit.add(missing).cacheHitRate, isNull);
        expect(hit.add(missing).cacheRead, 80);
        expect(
          TokenUsage.fromJson(hit.add(missing).toJson()).cacheReadReported,
          isFalse,
        );
      },
    );

    test(
      'legacy app migration is idempotent; external Pi JSON is unchanged',
      () {
        final old = {
          'input': 1000,
          'output': 50,
          'cacheRead': 600,
          'cacheWrite': 0,
        };
        final migrated = TokenUsage.fromLegacyAppJson(old);
        expect(migrated.total, 1050);
        expect(TokenUsage.fromLegacyAppJson(migrated.toJson()).total, 1050);
        expect(TokenUsage.fromJson(old).input, 1000);
        expect(
          TokenUsage.fromJson({'input': 100, 'cacheRead': 0}).cacheReadReported,
          isFalse,
        );
      },
    );
  });
}
