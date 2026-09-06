import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/prompt_token_counter_service.dart';
import 'package:novelai_harness/data/services/tokenizers/qwen_prompt_token_encoder.dart';
import 'package:novelai_harness/data/services/tokenizers/t5_prompt_token_encoder.dart';

void main() {
  final service = PromptTokenCounterService.instance;

  late final T5PromptTokenEncoder t5;
  late final QwenPromptTokenEncoder qwen;

  setUpAll(() {
    t5 = T5PromptTokenEncoder.fromBytes(
      File('assets/tokenizers/t5_spiece.model').readAsBytesSync(),
    );
    qwen = QwenPromptTokenEncoder.fromBytes(
      File('assets/tokenizers/qwen35_bpe.txt.gz').readAsBytesSync(),
    );
    service.debugInstallEncoders(t5: t5, qwen: qwen);
  });

  group('分词器官网计数对齐', () {
    test('T5 "hello world" 编码 2 个 token (不含 EOS)', () {
      expect(t5.countTokens('hello world'), 2);
      expect(t5.countTokens(''), 0);
    });

    test('Qwen "hello world" 计 2、"blending" 计 2 (官网实测)', () {
      expect(qwen.countTokens('hello world'), 2);
      expect(qwen.countTokens('blending'), 2);
    });

    test('Qwen 会真实编码权重语法字符: "4::blending::" 计 5 (官网实测)', () {
      expect(qwen.countTokens('4::blending::'), 5);
    });
  });

  group('正向计数', () {
    test('V4.5: 角色正向词并入主提示词计数，明细含角色条目', () {
      final base = NaiGenerationParams(
        model: NaiModel.v45Full,
        prompt: '1girl',
        qualityToggle: false,
        ucPresetKey: 'None',
      );
      final withCharacter = base.copyWith(
        characterPrompts: [
          const NaiCharacterPrompt(
            id: 'aabbccdd',
            name: 'C1',
            prompt: 'girl, red hair',
          ),
        ],
      );

      final usage = service.countPositive(withCharacter);
      final baseline = service.countPositive(base);

      expect(usage.hardLimit, 512);
      expect(usage.softLimit, isNull);
      expect(usage.estimated, isFalse);
      expect(usage.used, greaterThan(baseline.used));
      expect(
        usage.breakdown.any(
          (e) => e.kind == PromptTokenBreakdownKind.characters,
        ),
        isTrue,
      );
      // 明细分和恒等于总量
      expect(
        usage.breakdown.fold<int>(0, (sum, e) => sum + e.tokens),
        usage.used,
      );
    });

    test('V4.5: 质量词计入正向计数', () {
      final noQuality = NaiGenerationParams(
        model: NaiModel.v45Full,
        prompt: '1girl',
        qualityToggle: false,
        ucPresetKey: 'None',
      );
      final withQuality = noQuality.copyWith(qualityToggle: true);

      expect(
        service.countPositive(withQuality).used,
        greaterThan(service.countPositive(noQuality).used),
      );
    });

    test('T5: 权重语法剥离后计数不变', () {
      final plain = NaiGenerationParams(
        model: NaiModel.v45Full,
        prompt: '1girl, solo',
        qualityToggle: false,
        ucPresetKey: 'None',
      );
      final weighted = plain.copyWith(prompt: '1.5::1girl::, solo');
      final braced = plain.copyWith(prompt: '{1girl}, [solo]');

      expect(
        service.countPositive(weighted).used,
        service.countPositive(plain).used,
      );
      expect(
        service.countPositive(braced).used,
        service.countPositive(plain).used,
      );
    });

    test('T5: 非零总量带 +1 EOS 校准 (官网计数条口径)', () {
      final params = NaiGenerationParams(
        model: NaiModel.v45Full,
        prompt: 'hello world',
        qualityToggle: false,
        ucPresetKey: 'None',
      );
      // encoder 裸计数 2，官网计数条显示 3
      expect(service.countPositive(params).used, 3);
    });

    test('V5 Curated: 黄档阈值为 374、硬上限 703', () {
      final params = NaiGenerationParams(
        model: NaiModel.v5Curated,
        prompt: '1girl',
        qualityToggle: false,
        ucPresetKey: 'None',
      );
      final usage = service.countPositive(params);
      expect(usage.hardLimit, 703);
      expect(usage.softLimit, 374);
      expect(usage.estimated, isFalse);
    });
  });

  group('负面计数', () {
    test('UC 预设与 nsfw 前置计入负面计数 (用户负面为空也有量)', () {
      final params = NaiGenerationParams(
        model: NaiModel.v45Full,
        prompt: '1girl',
        negativePrompt: '',
        ucPresetKey: 'Heavy',
        qualityToggle: false,
      );
      final usage = service.countNegative(params);

      expect(usage.used, greaterThan(0));
      expect(
        usage.breakdown.any((e) => e.kind == PromptTokenBreakdownKind.ucPreset),
        isTrue,
      );
    });

    test('角色负面词并入负面计数', () {
      final base = NaiGenerationParams(
        model: NaiModel.v45Full,
        prompt: '1girl',
        negativePrompt: '',
        ucPresetKey: 'None',
        qualityToggle: false,
      );
      final withCharacter = base.copyWith(
        characterPrompts: [
          const NaiCharacterPrompt(
            id: 'aabbccdd',
            name: 'C1',
            prompt: 'girl',
            negativePrompt: 'lowres, aliasing',
          ),
        ],
      );

      final usage = service.countNegative(withCharacter);
      expect(usage.used, greaterThan(service.countNegative(base).used));
      expect(
        usage.breakdown.any(
          (e) => e.kind == PromptTokenBreakdownKind.characterNegatives,
        ),
        isTrue,
      );
    });
  });

  group('档位判定', () {
    test('超过黄档 → featureLimited，超过硬上限 → overLimit', () {
      const v5Full = PromptTokenUsage(
        used: 800,
        hardLimit: 1471,
        softLimit: 750,
      );
      expect(v5Full.level, PromptTokenBudgetLevel.featureLimited);
      expect(v5Full.isOverLimit, isFalse);

      const v5FullOver = PromptTokenUsage(
        used: 1500,
        hardLimit: 1471,
        softLimit: 750,
      );
      expect(v5FullOver.level, PromptTokenBudgetLevel.overLimit);
      expect(v5FullOver.isOverLimit, isTrue);

      const v45 = PromptTokenUsage(used: 300, hardLimit: 512);
      expect(v45.level, PromptTokenBudgetLevel.normal);

      const v45Over = PromptTokenUsage(used: 513, hardLimit: 512);
      expect(v45Over.level, PromptTokenBudgetLevel.overLimit);
    });

    test('黄档阈值恰好等于不算超过', () {
      const usage = PromptTokenUsage(
        used: 750,
        hardLimit: 1471,
        softLimit: 750,
      );
      expect(usage.level, PromptTokenBudgetLevel.normal);
    });
  });

  group('V3 CLIP 启发式', () {
    test('V3 无分词器资产，标记估算且上限 225 无黄档', () {
      final params = NaiGenerationParams(
        model: NaiModel.v3,
        prompt: '1girl, solo, long hair',
        qualityToggle: false,
        ucPresetKey: 'None',
      );
      final usage = service.countPositive(params);

      expect(usage.estimated, isTrue);
      expect(usage.hardLimit, 225);
      expect(usage.softLimit, isNull);
      expect(usage.used, greaterThan(0));
    });

    test('启发式估算: 逗号分段计数', () {
      expect(PromptTokenCounterService.estimatePromptTokens(''), 0);
      // "1girl, solo" 2 段 → round(2 * 1.35) = 3
      expect(PromptTokenCounterService.estimatePromptTokens('1girl, solo'), 3);
    });
  });
}
