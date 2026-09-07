import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/rgba_pixel_ops.dart';

void main() {
  group('blendAlphaRect source-over', () {
    for (final alpha in [0, 1, 64, 128, 192, 254, 255]) {
      test('不透明底图混合 alpha=$alpha 后仍不透明', () {
        final dst = Uint8List.fromList([0, 0, 0, 255]);
        blendAlphaRect(
          dst,
          1,
          1,
          Uint8List.fromList([255, 255, 255, alpha]),
          1,
          1,
          dstX: 0,
          dstY: 0,
        );
        expect(dst, [alpha, alpha, alpha, 255]);
      });
    }

    test('透明底图不把隐藏颜色带入源颜色', () {
      final dst = Uint8List.fromList([255, 255, 255, 0]);
      blendAlphaRect(
        dst,
        1,
        1,
        Uint8List.fromList([20, 40, 60, 128]),
        1,
        1,
        dstX: 0,
        dstY: 0,
      );
      expect(dst, [20, 40, 60, 128]);
    });

    test('半透明底图正确累积覆盖率并归一化颜色', () {
      final dst = Uint8List.fromList([0, 0, 255, 128]);
      blendAlphaRect(
        dst,
        1,
        1,
        Uint8List.fromList([255, 0, 0, 128]),
        1,
        1,
        dstX: 0,
        dstY: 0,
      );
      expect(dst, [170, 0, 85, 192]);
    });
  });
}
