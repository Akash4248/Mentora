# Mentora Project Agent Guidelines

## Mobile Testing Requirement
- When validating mobile UI components, chat screens, auto-scroll behaviors, or native `LlamaEngine` JNI inference, always run integration tests directly on attached Android mobile devices (e.g. `flutter test integration_test/mobile_llm_e2e_test.dart -d <device_id>`).
- Do not rely only on Linux desktop host unit tests for mobile platform features.
