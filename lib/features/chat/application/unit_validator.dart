import '../domain/physical_dimension.dart';

/// Validation report produced by [UnitValidator].
final class UnitValidationReport {
  const UnitValidationReport({
    required this.isValid,
    required this.dimension,
    this.errorMessage,
    this.warningMessage,
  });

  final bool isValid;
  final PhysicalDimension dimension;
  final String? errorMessage;
  final String? warningMessage;

  @override
  String toString() =>
      'UnitValidationReport(isValid: $isValid, dimension: ${dimension.name}, error: $errorMessage)';
}

/// Validates physical units, dimensions, and physical constraints for NCERT science.
final class UnitValidator {
  const UnitValidator();

  /// Maps a quantity name to its corresponding [PhysicalDimension].
  PhysicalDimension dimensionForQuantity(String quantity) {
    final clean = quantity.toLowerCase().trim();
    if (clean.contains('distance') ||
        clean.contains('displacement') ||
        clean.contains('height') ||
        clean.contains('radius') ||
        clean.contains('length')) {
      return PhysicalDimension.length;
    }
    if (clean.contains('time') || clean.contains('period') || clean.contains('duration')) {
      return PhysicalDimension.time;
    }
    if (clean.contains('mass')) {
      return PhysicalDimension.mass;
    }
    if (clean.contains('speed') || clean.contains('velocity')) {
      return PhysicalDimension.speed;
    }
    if (clean.contains('acceleration') || clean.contains('gravity') || clean == 'g' || clean == 'a') {
      return PhysicalDimension.acceleration;
    }
    if (clean.contains('force') || clean.contains('weight') || clean.contains('thrust') || clean.contains('tension')) {
      return PhysicalDimension.force;
    }
    if (clean.contains('momentum')) {
      return PhysicalDimension.momentum;
    }
    if (clean.contains('energy') || clean.contains('work') || clean.contains('kinetic') || clean.contains('potential')) {
      return PhysicalDimension.workEnergy;
    }
    if (clean.contains('power')) {
      return PhysicalDimension.power;
    }
    if (clean.contains('pressure')) {
      return PhysicalDimension.pressure;
    }
    return PhysicalDimension.unknown;
  }

  /// Maps a unit string to its corresponding [PhysicalDimension].
  PhysicalDimension dimensionForUnit(String unit) {
    var u = unit.toLowerCase().trim().replaceAll('²', '^2').replaceAll('⁻¹', '^-1').replaceAll('⁻²', '^-2');

    // Length
    if (u == 'm' || u == 'meter' || u == 'meters' || u == 'km' || u == 'cm' || u == 'mm') {
      return PhysicalDimension.length;
    }
    // Time
    if (u == 's' || u == 'sec' || u == 'second' || u == 'seconds' || u == 'min' || u == 'minute' || u == 'minutes' || u == 'hr' || u == 'hour' || u == 'hours' || u == 'h') {
      return PhysicalDimension.time;
    }
    // Mass
    if (u == 'kg' || u == 'kilogram' || u == 'kilograms' || u == 'g' || u == 'gram' || u == 'grams') {
      return PhysicalDimension.mass;
    }
    // Speed / Velocity
    if (u == 'm/s' || u == 'm s^-1' || u == 'm*s^-1' || u == 'km/h' || u == 'km/hr') {
      return PhysicalDimension.speed;
    }
    // Acceleration
    if (u == 'm/s^2' || u == 'm/s2' || u == 'm s^-2' || u == 'm*s^-2') {
      return PhysicalDimension.acceleration;
    }
    // Force
    if (u == 'n' || u == 'newton' || u == 'newtons' || u == 'kg m/s^2' || u == 'kg*m/s^2') {
      return PhysicalDimension.force;
    }
    // Momentum
    if (u == 'kg m/s' || u == 'kg*m/s' || u == 'n s' || u == 'n*s') {
      return PhysicalDimension.momentum;
    }
    // Work / Energy
    if (u == 'j' || u == 'joule' || u == 'joules' || u == 'n m' || u == 'n*m') {
      return PhysicalDimension.workEnergy;
    }
    // Power
    if (u == 'w' || u == 'watt' || u == 'watts' || u == 'j/s') {
      return PhysicalDimension.power;
    }
    // Pressure
    if (u == 'pa' || u == 'pascal' || u == 'pascals' || u == 'n/m^2') {
      return PhysicalDimension.pressure;
    }

    return PhysicalDimension.unknown;
  }

  /// Validates that the stated unit matches the physical dimension of the quantity,
  /// and performs sanity checks on the value.
  UnitValidationReport validate({
    required String quantity,
    required String unit,
    double? value,
  }) {
    final quantityDim = dimensionForQuantity(quantity);
    final unitDim = dimensionForUnit(unit);

    if (quantityDim != PhysicalDimension.unknown && unitDim != PhysicalDimension.unknown) {
      if (quantityDim != unitDim) {
        return UnitValidationReport(
          isValid: false,
          dimension: quantityDim,
          errorMessage: 'Dimensional mismatch: "$quantity" has dimension ${quantityDim.name}, but unit "$unit" represents ${unitDim.name}.',
        );
      }
    }

    // Physical bounds sanity checks
    if (value != null) {
      if (quantityDim == PhysicalDimension.mass && value <= 0) {
        return UnitValidationReport(
          isValid: false,
          dimension: PhysicalDimension.mass,
          errorMessage: 'Physical violation: Mass must be strictly positive (was: $value).',
        );
      }
      if (quantityDim == PhysicalDimension.time && value < 0) {
        return UnitValidationReport(
          isValid: false,
          dimension: PhysicalDimension.time,
          errorMessage: 'Physical violation: Elapsed time cannot be negative (was: $value).',
        );
      }
      if (quantityDim == PhysicalDimension.speed && value > 3e8) {
        return const UnitValidationReport(
          isValid: false,
          dimension: PhysicalDimension.speed,
          errorMessage: 'Relativistic violation: Speed cannot exceed speed of light (3e8 m/s).',
        );
      }
    }

    return UnitValidationReport(
      isValid: true,
      dimension: quantityDim,
    );
  }

  /// Calculates derived ground truth values for standard kinematics formulas:
  /// - Velocity: v = d / t
  /// - Acceleration: a = (v - u) / t
  /// - Force: F = m * a
  /// - Kinetic Energy: KE = 0.5 * m * v^2
  double calculateKinematics({
    required String formula,
    required Map<String, double> parameters,
  }) {
    final normalized = formula.toLowerCase().replaceAll(' ', '');
    switch (normalized) {
      case 'v=d/t':
      case 'speed=distance/time':
        final d = parameters['d'] ?? parameters['distance']!;
        final t = parameters['t'] ?? parameters['time']!;
        if (t == 0) throw ArgumentError('Time cannot be zero.');
        return d / t;

      case 'v=u+at':
      case 'v=u+a*t':
        final u = parameters['u'] ?? 0.0;
        final a = parameters['a']!;
        final t = parameters['t']!;
        return u + (a * t);

      case 's=ut+0.5at^2':
      case 's=ut+0.5*a*t^2':
      case 's=ut+1/2at^2':
      case 's=ut+1/2*a*t^2':
      case 's=u*t+0.5*a*t^2':
      case 's=u*t+1/2*a*t^2':
        final u = parameters['u'] ?? 0.0;
        final a = parameters['a']!;
        final t = parameters['t']!;
        return (u * t) + (0.5 * a * t * t);

      case 'f=ma':
      case 'f=m*a':
      case 'force=ma':
      case 'force=m*a':
      case 'force=mass*acceleration':
        final m = parameters['m'] ?? parameters['mass']!;
        final a = parameters['a'] ?? parameters['acceleration']!;
        return m * a;

      case 'ke=0.5mv^2':
      case 'ke=0.5*m*v^2':
      case 'ke=1/2mv^2':
      case 'ke=1/2*m*v^2':
        final m = parameters['m']!;
        final v = parameters['v']!;
        return 0.5 * m * v * v;

      default:
        throw UnsupportedError('Unsupported kinematics formula: $formula');
    }
  }
}
