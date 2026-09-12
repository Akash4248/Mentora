import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'package:offline_tutor_app/features/math_studio/domain/saved_exploration.dart';

void main() {
  group('Math Studio Symbolic Parser Tests', () {
    test('Evaluates arithmetic expressions with math_expressions', () {
      final parser = Parser();
      final exp = parser.parse('2 * 3 + 4');
      final cm = ContextModel();
      final eval = exp.evaluate(EvaluationType.REAL, cm) as double;
      expect(eval, equals(10.0));
    });

    test('Solves quadratic equation x^2 - 4 = 0', () {
      final query = 'x^2 - 4 = 0';
      final clean = query.replaceAll(' ', '');
      final quadMatch = RegExp(r'^x\^2\-?(\d+)=0$|^x\^2=(\d+)$').firstMatch(clean);
      expect(quadMatch, isNotNull);
      final valStr = quadMatch!.group(1) ?? quadMatch.group(2)!;
      final val = double.parse(valStr);
      final root = math.sqrt(val);
      expect(root, equals(2.0));
    });

    test('Solves linear equation 2x + 5 = 15', () {
      final query = '2x + 5 = 15';
      final clean = query.replaceAll(' ', '');
      final linMatch = RegExp(r'^(\d*)x\+?(\d+)=(\d+)$').firstMatch(clean);
      expect(linMatch, isNotNull);
      final a = double.parse(linMatch!.group(1)!.isEmpty ? '1' : linMatch.group(1)!);
      final b = double.parse(linMatch.group(2)!);
      final c = double.parse(linMatch.group(3)!);
      final ans = (c - b) / a;
      expect(ans, equals(5.0));
    });
  });

  group('Math Studio 3D Canvas Vector Math Tests', () {
    test('Projects 3D origin vector correctly', () {
      final transform = vector.Matrix4.identity()
        ..rotateY(0.5)
        ..rotateX(0.2);
      final p = transform.transform3(vector.Vector3(0, 0, 0));
      expect(p.x, equals(0.0));
      expect(p.y, equals(0.0));
      expect(p.z, equals(0.0));
    });

    test('Computes picking proximity distance under 12px threshold', () {
      final tapPos = const math.Point(100.0, 100.0);
      final targetPos = const math.Point(105.0, 103.0);
      final dist = tapPos.distanceTo(targetPos);
      expect(dist <= 12.0, isTrue);
    });
  });

  group('Saved Exploration Serialization Tests', () {
    test('Serializes and deserializes SavedExploration correctly', () {
      final exp = SavedExploration(
        id: 'test_1',
        title: 'Test Exploration',
        type: ExplorationType.algebra,
        data: {'equation': 'x^2 = 4'},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

      final map = exp.toMap();
      final restored = SavedExploration.fromMap(map);
      expect(restored.id, equals('test_1'));
      expect(restored.title, equals('Test Exploration'));
      expect(restored.type, equals(ExplorationType.algebra));
      expect(restored.data['equation'], equals('x^2 = 4'));
    });
  });
}
