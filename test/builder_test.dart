import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/validation/builder_validation_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('Builder Validation Test Runs', () async {
    final testRunner = BuilderValidationTest();
    await testRunner.runTest();
  });
}
