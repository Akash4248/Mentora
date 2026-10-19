# Offline Tutor App (Separate Module)

This module is a separate app scaffold from `ai_tutor` and is intended for staged implementation of the full offline tutor platform.

## Flutter SDK

This project is pinned to Flutter **3.47.7** (Dart 3.13.5), as
`flutter_agent_harness` requires Dart 3.12 or newer. Do not lower the Dart SDK
constraint in `pubspec.yaml` to work around a system Flutter installation.

Install FVM once with `dart pub global activate fvm` and ensure
`$HOME/.pub-cache/bin` is on `PATH`. Then run `fvm install` from the project
root. In VS Code, the workspace selects the pinned SDK automatically. For
terminal commands, use `fvm flutter pub get`, `fvm flutter run`, or
`fvm flutter test` rather than system `flutter`.

## Android Bonsai model

The Android JNI runtime is pinned to PrismML llama.cpp release
`prism-b10777-e3de715`. After cloning, initialize the runtime source with
`git submodule update --init --recursive`.

In Settings > Local AI Tutor, download the Bonsai 2 4B Q2_0 base model or select
another supported base GGUF. DFlash2 files are speculative draft models and
cannot be loaded as the chat model by themselves. The 4B base is the phone-size
starting point; larger model variants need device-specific memory testing.

## Stage 1 Implemented

- Course -> Subject -> Chapter hierarchy (SQLite-backed)
- Chapter-anchored tutor chat flow
- Prompt builder with student-friendly output format
- Language selector (English/Kannada toggle in UI)
- Inference bridge contract wired to existing native channels:
  - MethodChannel: `offline_tutor/llm`
  - EventChannel: `offline_tutor/llm_stream`

## Stage 2 Implemented (Simple RAG)

- SQLite schema upgraded with `rag_chunks` table
- Seed syllabus chunks added for initial chapters
- Chapter-filtered lexical retrieval service added (`SimpleRagService`)
- Prompt augmentation with retrieved context before inference
- Ingestion API added for future notes/resources:
  - `RagRepository.ingestChapterNotes(...)`

## Stage 3 Implemented (Structured Persistence)

- Chat session persistence tables added:
  - `chat_sessions`
  - `chat_messages`
- Learner progress table added:
  - `learner_progress`
- Chat now resumes from the latest chapter session automatically
- Questions asked counter persists and updates per chapter

## Stage 4 Implemented (Retrieval Upgrade)

- SQLite FTS index added for `rag_chunks` search
- Trigger-based FTS sync added on insert/update/delete
- Retrieval pipeline upgraded to FTS-first + lexical rerank fallback
- Embedding metadata scaffold table added:
  - `rag_chunk_embeddings`
- Ready for your next input resources to begin embedding indexing

## Stage 5 In Progress (Embedding Workflow Scaffold)

- Added chapter-level embedding indexing service
- Added indexing action in chapter chat app bar
- Added live embedding coverage status in chapter header:
  - `Embeddings: indexed/total`
- Notes ingestion now refreshes embedding coverage stats

## Stage 6 Started (P2P Foundation)

- Added Android P2P manager scaffold (`P2PManager`) with offline peer status and discovery flow
- Added Flutter P2P channel service (`offline_tutor/p2p`)
- Added P2P screen with transport status and peer list
- Added Home screen entry point for P2P panel
- Added network permissions for local transfer

Current scope is discovery/status foundation. File transfer handshake and payload sync will be added in the next increment.

## Stage 7 Implemented (Model Selection + Bundle Protocol)

- Added model selection screen with native channel integration:
  - current model path and metadata
  - pick `.gguf` file and apply via `setModelPath`
- Added P2P chapter bundle protocol in Flutter layer:
  - export chapter RAG chunks to JSON bundle
  - manifest with payload hash (SHA-256)
  - import with integrity verification and safe ingestion
- Added Home app bar actions for:
  - model selection
  - P2P sharing

## Stage 8 Implemented (Native Wi-Fi LAN Transfer)

- Replaced Bluetooth transfer with faster Wi-Fi LAN socket transfer:
  - start/stop receiver mode (TCP)
  - UDP broadcast peer discovery on local network
  - send selected bundle file to discovered peer by LAN IP
  - receive incoming bundles into native inbox (`files/p2p_inbox`)
- Extended P2P method channel with transfer APIs:
  - `startReceiver`
  - `stopReceiver`
  - `sendBundle`
  - `listReceivedBundles`
- Upgraded P2P UI with:
  - receiver controls
  - target peer selector
  - send last exported bundle action
  - native inbox listing

## Stage 9 Implemented (Peer Trust Controls)

- Added trusted peers table in SQLite:
  - `trusted_peers`
- Added trusted peer repository for persist/untrust/list operations
- Send flow is now trust-gated:
  - selected peer must be explicitly trusted before bundle transfer
- Added trust/untrust controls in P2P screen for selected LAN peer
- Added trusted status indicator in discovered peer list
- Added one-tap import action for bundles received in native inbox

## Stage 10 Implemented (LAN-First Routing + Wi-Fi Direct Fallback)

- Native peer discovery now routes with policy:
  - LAN first (UDP discovery + TCP transfer)
  - Wi-Fi Direct discovery fallback when LAN peers are unavailable
- Added route visibility in status payload:
  - active transport
  - route decision
  - route policy string
- P2P UI now displays route decision/policy and supports mixed peer transport labels

## Stage 11 Implemented (Runtime Local-Network Permission UX)

- Added Android runtime permission APIs on P2P method channel:
  - `getPermissionStatus`
  - `requestPermissions`
- Added P2P UI permission card for Android 12+/13+ flow:
  - location grant state
  - nearby Wi-Fi grant state
  - one-tap permission request action
- Wi-Fi Direct discovery now checks required runtime permissions before fallback scan

## Stage 12 Implemented (Receiver Approval Gate)

- Receiver now creates a pending incoming transfer request before writing any bytes to inbox
- Incoming transfers require explicit accept/reject decision from app UI
- Added pending transfer APIs on P2P channel:
  - `listPendingIncomingTransfers`
  - `approveIncomingTransfer`
  - `rejectIncomingTransfer`
- Added P2P UI for pending requests:
  - accept/reject actions
  - alert dialog prompt for new pending transfer
- If no decision is provided within timeout window, transfer is rejected automatically

## Stage 13 Implemented (Wi-Fi Direct Handshake Transfer Path)

- Added native Wi-Fi Direct connection handshake during send flow for direct peers
- Added route resolution from Wi-Fi Direct peer address to IPv4 transfer target using:
  - connection info (group owner route)
  - ARP/group lookup fallback when local device is group owner
- Added resolved route caching for Wi-Fi Direct peers
- P2P peer list now shows resolved route when available
- Send flow now supports both:
  - LAN peers (direct IPv4)
  - Wi-Fi Direct peers (auto route resolution + transfer)

## Stage 14 Implemented (Signed Manifest Verification)

- Bundle manifest upgraded with authenticity signature:
  - `payloadSignature` using `HMAC-SHA256(sharedSecret, payloadJson)`
  - `signatureAlgo: hmac-sha256`
- Import now verifies both:
  - payload hash integrity
  - HMAC signature authenticity
- Added shared-secret management in P2P UI for signed export/import workflow

## Stage 15 Implemented (Receiver Trust Policy)

- Added persisted P2P security settings in SQLite (`p2p_settings`):
  - shared secret
  - auto-accept trusted peers policy
- Trusted peer records now support alternate address mapping for direct/LAN route matching
- Receiver pending transfer handler now applies policy:
  - auto-accept trusted senders (when enabled)
  - prompt unknown senders for manual accept/reject

## Stage 16 Implemented (Transfer Progress + Throughput Telemetry)

- Added native transfer telemetry snapshot API:
  - `getTransferTelemetry`
- Added byte-level progress tracking for both send and receive flows:
  - stage (`connecting`, `sending`, `awaiting-approval`, `receiving`, `completed`, `failed`, `rejected`)
  - transferred bytes / total bytes
  - throughput (bytes/sec)
  - ETA estimate (seconds)
- Added live telemetry panel in P2P UI with periodic polling:
  - send progress bar + speed + ETA
  - receive progress bar + speed + ETA
  - error display for failed transfers

## Stage 17 Implemented (Shared-Secret Key Rotation with Grace Period)

- Added key rotation state management in P2P security repository:
  - current shared secret
  - previous shared secret (grace-period tracking)
  - configurable grace window (1-72 hours)
- Receiver/import now verifies against active + grace-period secrets:
  - old bundles signed with previous secret remain valid during grace
  - automatic cleanup of expired previous secret on app refresh
- Added key rotation UI controls in P2P screen:
  - grace window duration selector (1/6/12/24/48/72 hours)
  - rotate button with new secret validation
  - active grace period status display with expiry countdown

## Stage 18 Implemented (Secure Bootstrap Token Exchange with QR/Share)

- Added passcode-encrypted bootstrap token protocol:
  - SHA256 key derivation from passcode + random nonce
  - XOR cipher for secret encryption
  - HMAC-SHA256 integrity verification over token metadata
  - 15-minute TTL default
- Added QR code export flow in P2P UI:
  - generate short-lived bootstrap token from shared secret
  - display as QR code (via qr_flutter package)
  - share via native intent (Gmail, Signal, etc.)
- Added secure import dialog in P2P UI:
  - paste token + passcode recovery
  - automatic expiry + tampering detection via HMAC
  - integrates recovered secret back into rotation system

## Stage 19 Implemented (Progress Dashboard with Chapter Mastery Signals)

- Added learner_progress schema extensions:
  - sessions_engaged: count of distinct tutoring sessions per chapter
  - total_messages: count of messages exchanged in chapter conversations
  - mastery_score: computed metric (0-100) based on engagement
- Added mastery calculation algorithm:
  - 30% weight: questions asked (min 10% per question, max 100%)
  - 30% weight: sessions engaged (min 15% per session, max 100%)
  - 40% weight: message engagement (0.5% per message, max 100%)
  - Formula: 0.3*questionScore + 0.3*sessionScore + 0.4*messageScore
- Added mastery level classification:
  - Beginner: 0-49 (initial engagement phase)
  - Intermediate: 50-79 (active learning phase)
  - Advanced: 80+ (mastery phase)
- Added progress dashboard screen with:
  - overall mastery across all chapters (average %)
  - per-chapter progress cards showing:
    - chapter title + last activity timestamp
    - mastery level badge (color-coded)
    - linear progress bar (animated to mastery score)
    - detailed metrics: questions, messages, sessions
  - chapter list sorted by most recent activity
  - "No progress" state when no chapters engaged
- Added progress tracking integration:
  - recordQuestionAsked() called when user submits question
  - recordChatMessage() called after both user and assistant messages
  - recordNewSession() available for future session tracking
  - automatic mastery score recalculation on each interaction
- Added dashboard entry point in home screen:
  - trending_up icon in AppBar (new progress button)
  - navigates to ProgressDashboardScreen
  - displays alongside model selection + P2P sharing buttons

## Structure

- `lib/features/course` - hierarchy models and local repository
- `lib/features/home` - context selection flow
- `lib/features/chat` - tutor chat, gateway abstraction, prompt builder

## Important Constraint

The optimized runtime architecture is preserved:

Flutter UI -> EventChannel -> Kotlin -> JNI -> C++ (llama.cpp)

No heavy inference logic is moved into Flutter.

## Next Steps (Remaining Learning Intelligence Features)

1. Add actual embedding generation model inference and vector storage
2. Add vector similarity retrieval and hybrid reranking
3. Add multilingual retrieval tuning (English + Kannada term expansion)
4. Add chapter mastery prerequisites enforcement (gated learning paths)
5. Add spaced-repetition scheduling for review chapters
6. Add personalized difficulty adjustment based on mastery progression
