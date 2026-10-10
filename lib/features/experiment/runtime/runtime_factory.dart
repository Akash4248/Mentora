import '../domain/enums/experiment_enums.dart';
import '../application/experiment_execution_plan.dart';
import 'base_experiment_runtime.dart';
import 'sensor_runtime.dart';
import 'simulation_runtime.dart';
import 'hybrid_runtime.dart';
import 'observation_runtime.dart';

/// DEPRECATED: Stack B factory. Prefer `RuntimeLoader.loadFromManifest`
/// + [RuntimeWorld] directly. Kept for the legacy orchestrator only.
@deprecated
class RuntimeFactory {
  @deprecated
  static BaseExperimentRuntime createRuntime(ExperimentExecutionPlan plan) {
    switch (plan.selectedMode) {
      case ExperimentExecutionMode.sensor:
        return SensorRuntime(plan);
      case ExperimentExecutionMode.simulation:
        return SimulationRuntime(plan);
      case ExperimentExecutionMode.hybrid:
        return HybridRuntime(plan);
      case ExperimentExecutionMode.observation:
        return ObservationRuntime(plan);
    }
  }
}
