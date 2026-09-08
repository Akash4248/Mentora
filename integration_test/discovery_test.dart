import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offline_tutor_app/features/network/application/pi_hub_discovery_coordinator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Clear shared preferences before each test
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  group('Discovery Validation Matrix', () {
    testWidgets('Test A: Env Enabled, Backend Online', (tester) async {
      print('\n--- START TEST A ---');
      dotenv.loadFromString(envString: '''
DISCOVERY_IGNORE_ENV=false
BACKEND_BASE_URL=http://127.0.0.1:8080
''');

      // Start a mock healthy backend on 8080
      final server = await HttpServer.bind('127.0.0.1', 8080);
      server.listen((HttpRequest request) {
        if (request.uri.path == '/health') {
          request.response
            ..statusCode = 200
            ..write('{"status":"healthy","service":"gateway"}')
            ..close();
        } else {
          request.response..statusCode = 404..close();
        }
      });

      final coordinator = PiHubDiscoveryCoordinator();
      final node = await coordinator.discover();
      
      expect(node, isNotNull);
      expect(node?.source, 'env');
      
      await server.close(force: true);
      print('--- END TEST A ---\n');
    });

    testWidgets('Test B: Ignore Env, Backend Online (Mock LAN)', (tester) async {
      print('\n--- START TEST B ---');
      dotenv.loadFromString(envString: '''
DISCOVERY_IGNORE_ENV=true
''');

      // We bind to 0.0.0.0:80 to mock a LAN backend if the app probes itself.
      // Or we can just let it scan the subnet. Since we don't have a real PiHub running on LAN,
      // it might not find one. Wait, if it scans the subnet, it will scan its own IP too!
      // So if we bind 0.0.0.0:80, the subnet scan will hit the device's own IP and succeed.
      HttpServer? server;
      try {
        server = await HttpServer.bind('0.0.0.0', 80);
        server.listen((HttpRequest request) {
          if (request.uri.path == '/health') {
            request.response
              ..statusCode = 200
              ..write('{"status":"healthy","service":"gateway"}')
              ..close();
          } else {
            request.response..statusCode = 404..close();
          }
        });
      } catch (e) {
        print('Could not bind to port 80: $e');
      }

      final coordinator = PiHubDiscoveryCoordinator();
      final node = await coordinator.discover();
      
      if (server != null) {
        expect(node, isNotNull);
        expect(node?.source, 'scan');
      }
      
      await server?.close(force: true);
      print('--- END TEST B ---\n');
    });

    testWidgets('Test C: Ignore Env, Backend Offline', (tester) async {
      print('\n--- START TEST C ---');
      dotenv.loadFromString(envString: '''
DISCOVERY_IGNORE_ENV=true
''');

      final coordinator = PiHubDiscoveryCoordinator();
      final node = await coordinator.discover();
      
      expect(node, isNull);
      print('--- END TEST C ---\n');
    });

    testWidgets('Test D: Cache Verification', (tester) async {
      print('\n--- START TEST D ---');
      dotenv.loadFromString(envString: '''
DISCOVERY_IGNORE_ENV=false
''');

      // Start mock server
      final server = await HttpServer.bind('127.0.0.1', 8080);
      server.listen((HttpRequest request) {
        if (request.uri.path == '/health') {
          request.response
            ..statusCode = 200
            ..write('{"status":"healthy","service":"gateway"}')
            ..close();
        }
      });

      // Populate Cache artificially
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pihub_last_known_ip', '127.0.0.1');
      await prefs.setInt('pihub_last_known_port', 8080);

      final coordinator = PiHubDiscoveryCoordinator();
      final node = await coordinator.discover();
      
      expect(node, isNotNull);
      expect(node?.source, 'cached');
      
      await server.close(force: true);
      print('--- END TEST D ---\n');
    });
  });
}
