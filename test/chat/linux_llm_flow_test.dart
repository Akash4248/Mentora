import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tutor_app/features/chat/application/reasoning_output_filter.dart';
import 'package:offline_tutor_app/features/chat/data/linux_tutor_inference_gateway.dart';
import 'package:offline_tutor_app/features/chat/data/local/linux_llm_config_service.dart';
import 'package:offline_tutor_app/features/network/services/mentora_backend_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Local LLM Architecture & Config Tests', () {
    final configService = LinuxLlmConfigService();

    test('Auto-detects llama-cli / llama-completion executable', () async {
      final detected = await configService.autoDetectExecutable();
      expect(detected, isNotNull);
      expect(File(detected!).existsSync(), isTrue);
      print('Detected executable: $detected');
    });

    test('Validates config with phi-2 GGUF model', () async {
      const modelPath =
          '/home/akash/Desktop/PIHUB/backend/inference-service/models/phi-2.Q4_K_M.gguf';

      final executable = await configService.autoDetectExecutable();
      expect(executable, isNotNull);

      final config = LinuxLlmConfig(
        modelPath: modelPath,
        executablePath: executable!,
        maxTokens: 128,
      );

      final validation = await configService.validate(config);
      expect(validation.ready, isTrue);
      expect(validation.message.toLowerCase(), contains('ready'));
    });

    test('ReasoningOutputFilter cleans stop tokens and reasoning blocks', () {
      final filter = ReasoningOutputFilter();
      const chunk1 = '<think>\nThe user is asking for definition of motion.\n</think>\n';
      const chunk2 = 'Motion is the change in position of an object over time.';

      final p1 = filter.push(chunk1);
      final p2 = filter.push(chunk2);
      final fl = filter.flush();

      final full = p1 + p2 + fl;
      print('Filter test output: "$full"');
      expect(full, isNot(contains('<think>')));
      expect(full, contains('Motion is the change in position of an object over time.'));
    });
  });

  group('Local LLM Subprocess Inference Flow Test', () {
    test('Streams real tokens from local GGUF model via LinuxTutorInferenceGateway', () async {
      const modelPath =
          '/home/akash/Desktop/PIHUB/backend/inference-service/models/phi-2.Q4_K_M.gguf';

      final configService = LinuxLlmConfigService();
      final executable = await configService.autoDetectExecutable();
      expect(executable, isNotNull);

      // Save valid local config
      await configService.save(
        LinuxLlmConfig(
          modelPath: modelPath,
          executablePath: executable!,
          maxTokens: 64,
        ),
      );

      final gateway = LinuxTutorInferenceGateway(configService: configService);
      final stream = gateway.streamResponse(prompt: 'Explain gravity in 1 simple sentence.');

      final outputBuffer = StringBuffer();
      var tokenCount = 0;

      await for (final chunk in stream) {
        outputBuffer.write(chunk);
        tokenCount++;
      }

      final fullOutput = outputBuffer.toString();
      print('\n=== LOCAL LLM STREAMED OUTPUT (${fullOutput.length} chars, $tokenCount chunks) ===');
      print(fullOutput);
      print('========================================================================\n');

      expect(fullOutput.trim(), isNotEmpty);
      expect(tokenCount, greaterThan(0));
    });

    test('MentoraBackendClient automatically falls back to Local LLM when backend is offline', () async {
      const modelPath =
          '/home/akash/Desktop/PIHUB/backend/inference-service/models/phi-2.Q4_K_M.gguf';

      final configService = LinuxLlmConfigService();
      final executable = await configService.autoDetectExecutable();
      expect(executable, isNotNull);

      await configService.save(
        LinuxLlmConfig(
          modelPath: modelPath,
          executablePath: executable!,
          maxTokens: 32,
        ),
      );

      final client = MentoraBackendClient();
      client.setBaseUrl('http://127.0.0.1:9999'); // Unreachable backend port

      final reply = await client.queryAiTutor(
        question: 'What is acceleration?',
        topic: 'Motion',
        grade: 9,
      );

      print('\n=== OFFLINE FALLBACK REPLY ===');
      print('Source: ${reply['source']}');
      print('Answer: ${reply['answer']}');
      print('===============================\n');

      expect(reply['source'], 'on_device_local_llm');
      expect(reply['answer'], contains('On-Device Local AI Tutor'));
    });
  });
}
