import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/phet/data/phet_catalog_service.dart';
import 'package:mentora/features/experiment/phet/models/experiment_descriptor.dart';

void main() {
  test('parses PiHub PhET catalog and resolves local simulation URL', () {
    final service = PhetCatalogService();
    final experiments = service.parseGatewayCatalog(<String, dynamic>{
      'simulations': <Map<String, dynamic>>[
        <String, dynamic>{
          'slug': 'acid-base-solutions',
          'url':
              'https://phet.colorado.edu/sims/html/acid-base-solutions/latest/acid-base-solutions_en.html',
          'local_url': '/simulations/acid-base-solutions/index.html',
          'manifest': <String, dynamic>{
            'id': 'phet-acid-base-solutions',
            'title': 'Acid Base Solutions',
            'provider': 'phet',
            'type': 'simulation',
          },
        },
      ],
      'total': 45,
    }, baseUrl: 'http://pihub.local');

    expect(experiments, hasLength(1));
    expect(experiments.single.id, 'phet-acid-base-solutions');
    expect(experiments.single.subject, 'Chemistry');
    expect(
      experiments.single.launchLocation,
      'http://pihub.local/simulations/acid-base-solutions/index.html',
    );
    expect(
      experiments.single.launchSource,
      ExperimentLaunchSource.classroomGateway,
    );
  });

  test('parses the manifest-free catalog stored inside the pack', () {
    final descriptor = ExperimentDescriptor.fromPhetCatalog(
      json: <String, dynamic>{
        'slug': 'pendulum-lab',
        'url':
            'https://phet.colorado.edu/sims/html/pendulum-lab/latest/pendulum-lab_en.html',
      },
      launchLocation:
          '/content_packs/phet_simulations_v1/simulations/pendulum-lab/index.html',
      launchSource: ExperimentLaunchSource.installedPack,
    );

    expect(descriptor.id, 'phet-pendulum-lab');
    expect(descriptor.title, 'Pendulum Lab');
    expect(descriptor.subject, 'Physics');
    expect(descriptor.isInstalled, isTrue);
  });
}
