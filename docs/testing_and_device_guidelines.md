# Testing & Mobile Device Testing Guidelines

## Mandatory Device Testing Policy
All AI agents working on Mentora must adhere to the following protocol:

1. **Physical / Emulator Mobile Device Verification Required:**
   - Unit tests run on host Linux desktop are NOT sufficient to declare mobile features complete.
   - You MUST run integration tests on the connected Android mobile device using `flutter test integration_test/... -d <device_id>` or `flutter run -d <device_id>`.

2. **Connected Devices Check:**
   - Run `flutter devices` or `adb devices` to detect active target mobile hardware (e.g. `moto g34 5G` - `ZA222JN8FQ`).

3. **Validation Areas:**
   - Mobile UI layout & responsive rendering.
   - On-device JNI / `LlamaEngine.kt` local LLM inference.
   - Auto-scrolling and gesture interactions.
