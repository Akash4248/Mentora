import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/unit_validator.dart';
import 'package:mentora/features/chat/domain/physical_dimension.dart';

void main() {
  group('UnitValidator', () {
    const validator = UnitValidator();

    group('dimension mapping', () {
      test('maps physical quantities to correct dimensions', () {
        expect(validator.dimensionForQuantity('distance'), PhysicalDimension.length);
        expect(validator.dimensionForQuantity('height'), PhysicalDimension.length);
        expect(validator.dimensionForQuantity('time elapsed'), PhysicalDimension.time);
        expect(validator.dimensionForQuantity('mass of block'), PhysicalDimension.mass);
        expect(validator.dimensionForQuantity('velocity'), PhysicalDimension.speed);
        expect(validator.dimensionForQuantity('acceleration'), PhysicalDimension.acceleration);
        expect(validator.dimensionForQuantity('gravity (g)'), PhysicalDimension.acceleration);
        expect(validator.dimensionForQuantity('net force'), PhysicalDimension.force);
        expect(validator.dimensionForQuantity('linear momentum'), PhysicalDimension.momentum);
        expect(validator.dimensionForQuantity('kinetic energy'), PhysicalDimension.workEnergy);
        expect(validator.dimensionForQuantity('power'), PhysicalDimension.power);
        expect(validator.dimensionForQuantity('pressure'), PhysicalDimension.pressure);
      });

      test('maps standard and formatted unit strings to dimensions', () {
        expect(validator.dimensionForUnit('m'), PhysicalDimension.length);
        expect(validator.dimensionForUnit('km'), PhysicalDimension.length);
        expect(validator.dimensionForUnit('s'), PhysicalDimension.time);
        expect(validator.dimensionForUnit('hr'), PhysicalDimension.time);
        expect(validator.dimensionForUnit('kg'), PhysicalDimension.mass);
        expect(validator.dimensionForUnit('m/s'), PhysicalDimension.speed);
        expect(validator.dimensionForUnit('m s^-1'), PhysicalDimension.speed);
        expect(validator.dimensionForUnit('km/h'), PhysicalDimension.speed);
        expect(validator.dimensionForUnit('m/s^2'), PhysicalDimension.acceleration);
        expect(validator.dimensionForUnit('m s^-2'), PhysicalDimension.acceleration);
        expect(validator.dimensionForUnit('N'), PhysicalDimension.force);
        expect(validator.dimensionForUnit('newtons'), PhysicalDimension.force);
        expect(validator.dimensionForUnit('kg m/s'), PhysicalDimension.momentum);
        expect(validator.dimensionForUnit('J'), PhysicalDimension.workEnergy);
        expect(validator.dimensionForUnit('W'), PhysicalDimension.power);
        expect(validator.dimensionForUnit('Pa'), PhysicalDimension.pressure);
      });
    });

    group('validation and dimensional consistency', () {
      test('approves dimensionally compatible quantity and unit', () {
        final report = validator.validate(
          quantity: 'force',
          unit: 'N',
          value: 50.0,
        );

        expect(report.isValid, isTrue);
        expect(report.dimension, PhysicalDimension.force);
        expect(report.errorMessage, isNull);
      });

      test('rejects dimensional mismatches (e.g., force in m/s)', () {
        final report = validator.validate(
          quantity: 'force',
          unit: 'm/s',
          value: 10.0,
        );

        expect(report.isValid, isFalse);
        expect(report.dimension, PhysicalDimension.force);
        expect(report.errorMessage, contains('Dimensional mismatch'));
        expect(report.errorMessage, contains('force'));
        expect(report.errorMessage, contains('speed'));
      });

      test('rejects physical violations (negative mass, negative elapsed time)', () {
        final massReport = validator.validate(
          quantity: 'mass',
          unit: 'kg',
          value: -5.0,
        );
        expect(massReport.isValid, isFalse);
        expect(massReport.errorMessage, contains('Mass must be strictly positive'));

        final timeReport = validator.validate(
          quantity: 'time',
          unit: 's',
          value: -1.5,
        );
        expect(timeReport.isValid, isFalse);
        expect(timeReport.errorMessage, contains('Elapsed time cannot be negative'));
      });

      test('rejects superluminal speed', () {
        final lightReport = validator.validate(
          quantity: 'velocity',
          unit: 'm/s',
          value: 4e8,
        );
        expect(lightReport.isValid, isFalse);
        expect(lightReport.errorMessage, contains('cannot exceed speed of light'));
      });
    });

    group('ground truth kinematics calculation', () {
      test('computes velocity v = d / t', () {
        final v = validator.calculateKinematics(
          formula: 'v = d / t',
          parameters: {'d': 100.0, 't': 5.0},
        );
        expect(v, 20.0);
      });

      test('computes acceleration v = u + at', () {
        final v = validator.calculateKinematics(
          formula: 'v = u + at',
          parameters: {'u': 0.0, 'a': 9.8, 't': 1.5},
        );
        expect(v, closeTo(14.7, 1e-4));
      });

      test('computes displacement s = ut + 0.5at^2 for projectile peak', () {
        // u = 14.7 m/s upward, g = -9.8 m/s^2, t = 1.5 s
        final hPeak = validator.calculateKinematics(
          formula: 's = ut + 0.5at^2',
          parameters: {'u': 14.7, 'a': -9.8, 't': 1.5},
        );
        // Correct peak height is exactly 11.025 m (NOT 11.25 m)
        expect(hPeak, closeTo(11.025, 1e-4));
      });

      test('computes dynamic force F = m * a (not a fixed 9.8 N)', () {
        final f10kg = validator.calculateKinematics(
          formula: 'F = m * a',
          parameters: {'m': 10.0, 'a': 9.8},
        );
        expect(f10kg, 98.0);

        final f1kg = validator.calculateKinematics(
          formula: 'F = m * a',
          parameters: {'m': 1.0, 'a': 9.8},
        );
        expect(f1kg, 9.8);
      });

      test('computes kinetic energy KE = 0.5 m v^2', () {
        final ke = validator.calculateKinematics(
          formula: 'ke = 0.5mv^2',
          parameters: {'m': 2.0, 'v': 3.0},
        );
        expect(ke, 9.0);
      });
    });
  });
}
