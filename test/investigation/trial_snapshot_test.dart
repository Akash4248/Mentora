import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/investigation/models/trial_snapshot.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  test(
    'TrialSnapshot captures variables, measurements, observations, graphs',
    () {
      final world = RuntimeLoader.loadFromManifest({
        'metadata': {'title': 'Snapshot Test'},
        'scene': {
          'sceneId': 'snapshot_test',
          'name': 'Snapshot Test',
          'variables': [
            {
              'id': 'var_temp',
              'name': 'Temperature',
              'type': 'number',
              'value': 75,
            },
          ],
          'objects': [
            {
              'id': 'graph_1',
              'type': 'lineGraph',
              'properties': <String, dynamic>{},
            },
          ],
          'rules': const [],
        },
      });
      world.recordObservation();

      final snapshot = TrialSnapshot.fromWorld(world);

      expect(snapshot.variables['var_temp'], 75);
      expect(snapshot.observations.length, 1);
      expect(snapshot.graphs.length, 1);

      world.dispose();
    },
  );
}
