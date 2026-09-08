import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offline_tutor_app/features/network/application/pi_hub_discovery_coordinator.dart';
import 'package:offline_tutor_app/features/network/application/backend_url_manager.dart';
import 'package:offline_tutor_app/features/network/domain/backend_config.dart';
import 'package:offline_tutor_app/features/network/data/backend_api_service.dart';
import 'package:offline_tutor_app/features/educational/application/sync_manager.dart';
import 'package:offline_tutor_app/config/app_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  testWidgets('Runtime Failure Investigation', (tester) async {
    print('\n--- START RUNTIME INVESTIGATION ---');
    
    // Setup typical .env
    dotenv.loadFromString(envString: '''
DISCOVERY_IGNORE_ENV=false
BACKEND_BASE_URL=http://10.28.73.193
''');
    AppEnvironment.initialize();

    // Mock an active PiHub backend on localhost 8080
    final server = await HttpServer.bind('127.0.0.1', 8080);
    server.listen((HttpRequest request) {
      if (request.uri.path == '/health') {
        request.response
          ..statusCode = 200
          ..write('{"status":"healthy","service":"gateway"}')
          ..close();
      } else if (request.uri.path.contains('/packs/sync')) {
        request.response
          ..statusCode = 200
          ..write('{"packs": [{"packId": "demo-pack", "version": "2"}]}')
          ..close();
      } else {
        request.response..statusCode = 404..close();
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pihub_last_known_ip', '127.0.0.1');
    await prefs.setInt('pihub_last_known_port', 8080);

    final config = BackendConfig.fromEnvironment()!;
    final backendService = BackendApiService(config: config);
    
    final urlManager = BackendUrlManager(initialUrl: config.baseUrl);
    urlManager.urlChanges.listen((newUrl) {
      config.updateUrl(newUrl);
    });

    final discovery = PiHubDiscoveryCoordinator();
    
    // Simulate what DiscoverySyncBridge does
    discovery.discoveryUpdates.listen((nodes) {
      if (nodes.isNotEmpty) {
        urlManager.updateUrl(nodes.first.baseUrl);
      }
    });

    // Run discovery
    await discovery.discover();
    
    // Check health
    await backendService.isBackendAvailable();

    // Trigger sync check
    await SyncManager().checkForPackUpdates();

    await server.close(force: true);
    print('--- END RUNTIME INVESTIGATION ---\n');
  });
}
