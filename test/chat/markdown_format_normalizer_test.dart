import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tutor_app/features/chat/application/markdown_format_normalizer.dart';

void main() {
  group('MarkdownFormatNormalizer', () {
    test('normalizes unformatted dense GGUF text with glued headers and bullet points', () {
      const raw = 'Chapter4: A Square and A Cube## IntroductionIn this chapter, we will learn about squares and cubes. A square is a two-dimensional shape with four equal sides and four right angles. A cube is a three-dimensional shape with six equal sides and eight vertices.## Properties of a SquareA square has the following properties:- All sides are equal.- All angles are right angles (90°).- The diagonals of a square are equal and bisect each other at right angles.- The area of a square is equal to the square of its side length.- The perimeter of a square is equal to four times its side length.## Properties of a CubeA cube has the following properties:- All sides are equal.- All angles are right angles (90°)';

      final normalized = MarkdownFormatNormalizer.normalize(raw);

      expect(normalized, contains('Chapter 4: A Square and A Cube'));
      expect(normalized, contains('\n\n## Introduction\n\nIn this chapter'));
      expect(normalized, contains('\n\n## Properties of a Square\n\nA square has'));
      expect(normalized, contains('\n- All sides are equal.'));
      expect(normalized, contains('\n- All angles are right angles (90°).'));
      expect(normalized, contains('\n\n## Properties of a Cube\n\nA cube has'));
    });
  });
}
