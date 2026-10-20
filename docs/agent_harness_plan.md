# Agent Harness & Chat UX Plan

## Executive recommendation

Score for the current direction: 8.5/10.

Why not 10/10:
- The direction is strong and aligned to product reality, but it still needs a tighter runtime boundary and a clearer product contract.
- The app should use the shared `flutter_agent_harness`/AgentLib boundary as the runtime adapter, not build a second bespoke loop.
- The first implementation should be harness-first, with the app owning policy, memory, and UI, while the harness handles model execution, tool orchestration, session state, and provider abstraction.

Final decision:
- Do not create a custom harness by copying harness logic.
- Use the shared agent harness as the execution runtime.
- Wrap it behind a Mentora-specific session/service layer.
- Keep the real product logic in the Flutter app, not inside the harness.

This is the correct architecture for Mentora because it keeps the app online/offline capable, model-agnostic, and easier to evolve without locking us into one backend or one future model family.

## Product goals

1. Deliver a production-grade tutor chat with structured explanation, not raw model dumps.
2. Keep the app offline-first while supporting online inference when connectivity is available.
3. Support text, image, and future document/file input without rewriting the UX layer.
4. Preserve context across sessions using memory, summaries, and retrieval.
5. Keep model routing model-agnostic and provider-switchable.
6. Make tool usage, citations, and reasoning visible in a controlled, safe way.

## Non-goals for v1

- Building a custom reasoning engine in Flutter.
- Hard-coding a single model, backend, or provider.
- Making the UI depend directly on a model runtime class.
- Shipping unbounded or ungoverned tool execution.

## System architecture

### 1. App layer

Responsible for:
- UI rendering
- user actions and gestures
- session state in Flutter
- auth / profile / user settings
- tool approval policies
- per-screen workflow orchestration

This layer must not execute inference directly. It interacts with a stable Mentora session service.

### 2. Mentora session layer

This is the app-facing adapter that sits between Flutter screens and the harness runtime.

Responsibilities:
- create and manage one user session
- maintain a session ID and conversation transcript
- bind model config and chosen provider
- enforce tool authorization rules
- convert harness events into UI events
- persist memory metadata for later recall

This is the critical architecture boundary. The app should talk to `MentoraAgentSession`, not to the model layer directly.

### 3. Agent harness/runtime layer

This is the orchestration runtime, provided by the agent harness / AgentLib.

Responsibilities:
- coordinate model prompts and provider streaming
- run tool calls
- maintain turn lifecycle
- enforce system prompt and guardrails
- handle sequential or constrained tool execution
- aggregate model output and stop states

This is the orchestration boundary; it is not itself a GGUF inference engine or
the product policy layer. The Mentora provider adapter calls the selected
inference route.

### 4. Inference gateway / backend adapter

The runtime must not care whether inference is:
- local on-device GGUF / Llama.cpp / compatible runtime
- a remote hosted model endpoint
- a hybrid route where the app prefers local then falls back online

The key is a single adapter contract:
- `ModelProvider`
- `InferenceRequest`
- `InferenceResponse`
- `ProviderHealth`

The front-end and harness do not change when the backend changes.

### 5. Memory layer

Memory must be split into layers:

1. Short-term memory
   - current conversation transcript
   - current turn context
   - active tool outputs
   - recent reasoning and citations

2. Session memory
   - per-session summary
   - unresolved task state
   - facts extracted during the session
   - tool result cache

3. Long-term memory
   - user profile / learning preferences
   - persistent concepts and prior lesson summaries
   - retrieval-indexed notes and tutoring history

4. Retrieval layer
   - semantic search over user memory
   - document retrieval for course material
   - vector embedding and summary lookup

Memory contract:
- User message -> context assembly
- context assembly -> candidate memory retrieval
- retrieval -> prompt augmentation
- final answer -> memory commit

This keeps the app from becoming a raw chat transcript dump.

## Required capabilities before moving to implementation

### Functional requirements
- Text chat with streaming responses
- model/tool status updates in UI
- safe tool authorization before execution
- retry / regenerate / continue actions
- structured explanation cards
- citations / references / lesson links
- support for images in prompts
- support for future file upload inputs
- offline-first fallback

### Non-functional requirements
- low memory footprint on mobile devices
- graceful degradation when no model is available
- timeouts on model and tools
- cancel support for active turns
- session persistence and recovery
- deterministic policy flow for safety and approvals

### Product constraints
- UI must not expose raw provider payloads
- the app must feel like an assistant, not a debug console
- the app should remain understandable to a user who is not technical
- the experience must remain consistent online/offline

## Chat UI design direction

The UI should behave like a modern assistant interface, but remain teacher-focused rather than generic chat-only UI.

### Layout
- top bar with session status, model/provider status, connectivity indicator, and memory banner
- main conversation area with message bubbles
- right-side or bottom panel for structured artifacts when needed
- tool status strip for actions like Search, Recall, Solve, Explain

### Message rendering
Each assistant turn should support multiple display blocks:

1. Primary answer block
   - friendly explanation in plain language
   - not too long unless the user asks for detail

2. Reasoning / steps card
   - numbered or grouped steps
   - “How I solved this” panel
   - can be collapsed or expanded

3. Evidence / concept card
   - retrieved lesson references
   - textbook or lesson mapping
   - concept tags

4. Tool status card
   - what the system checked
   - whether it called a tool
   - whether actions were approved

5. Visual artifact area
   - chart, diagram, formula preview, screenshot annotation, answer card, or concept map

### Interaction patterns
- “Explain step by step”
- “Show the derivation”
- “Give me the simpler version”
- “Use the previous lesson context”
- “Retry with more detail”

### Future input types
The composer should be designed now for:
- text
- image attachment
- document attachment
- file / screenshot drag-and-drop
- voice input later

This should be built as a composer shell that accepts an `InputAttachment` abstraction instead of hard-coded text-only inputs.

## How the LLM output should be visualized

The product should not render raw output only. It should render a structured response model.

Recommended output schema:

```json
{
  "type": "assistant_turn",
  "status": "complete",
  "answer": {
    "text": "...",
    "summary": "..."
  },
  "steps": [
    { "title": "Identify the concept", "detail": "..." },
    { "title": "Apply the formula", "detail": "..." }
  ],
  "artifacts": [
    { "kind": "chart", "data": {} },
    { "kind": "formula", "value": "E = mc^2" },
    { "kind": "concept-card", "title": "Kinematics" }
  ],
  "citations": ["Lesson 3.2", "NCERT Chapter 2"],
  "tool_activity": ["retrieved_notes", "solved_equation"],
  "confidence": 0.88
}
```

The UI then maps this to cards, step lists, and visuals instead of a flat text blob.

## Backend inference strategy

Mentora must not make model calls directly from the UI. Use a stable backend or runtime boundary.

Recommended route:
- Flutter app calls the Mentora session service.
- session service calls the agent harness runtime.
- harness runtime calls either:
  - local provider when offline
  - remote provider when online and allowed
  - fallback provider when local fails or is degraded

This keeps the client clean and makes one provider switch a configuration change rather than a product rewrite.

### Online backend design
For a connected app, use a backend gateway with:
- user/session auth
- model routing rules
- quotas and safety controls
- tool-call policy enforcement
- cost controls and observability
- prompt/context assembly

The app does not need to know the provider internals. It sends a high-level request and receives a normalized response.

### Offline design
For local devices, use a local inference adapter:
- GGUF or on-device compatible runtime
- strict memory caps
- minimal context size and fallback modes
- local caching for raw model outputs when allowed

The same app contract should work in both modes.

## Final architecture decision

Adopt a layered model:

- UI layer: Flutter app
- orchestration layer: Mentora session / agent adapter
- runtime layer: `flutter_agent_harness` / AgentLib
- inference layer: local, online, or hybrid provider adapter
- memory layer: short-term + session + long-term retrieval

This is the cleanest product-ready solution and the one we should move forward with.

## Implementation sequence

### Phase 1: runtime contract
- finalize the session contract
- define message/event schema
- define tool authorization contract
- define memory interfaces

### Phase 2: harness integration
- wire MentoraAgentSession to the harness
- validate text streaming
- add cancel and timeout handling
- add provider switch logic

### Phase 3: memory
- store session transcript
- add short-term memory and summary layer
- add retrieval step for lesson context

### Phase 4: UI polish
- structured answer cards
- step-by-step renderer
- tool status UI
- image/file composer support

### Phase 5: online/offline backend integration
- backend gateway
- local fallback route
- provider health checks and recovery

### Phase 6: production hardening
- telemetry
- observability
- safety review
- mobile device validation

## Acceptance criteria for v1

- user can chat with the tutor in text mode
- streaming response appears in the chat UI
- model and tool status are visible but not noisy
- tool calls require authorization
- the app can switch between local and online inference without UI rewrite
- memory persists across the same session
- future image + file input is supported by the composer shell
- the UI displays structured answers instead of raw text only

## Summary

The final plan is not to invent another custom harness. It is to standardize on the agent harness as the execution runtime, wrap it in a Mentora-specific session boundary, and make the UI evolve around a structured assistant experience.

This gives us:
- a production-grade product flow
- stable memory and orchestration
- robust offline + online inference
- a cleaner mobile experience
- future support for multimodal inputs without reworking the whole app

This is the correct product and engineering direction for Mentora.

## Current implementation status

The first harness-to-inference vertical slice is now wired:

- The chapter tutor screen sends turns through `MentoraAgentSession` and maps
  harness events into the existing chat transcript UI.
- `MentoraTutorAgentProvider` adapts harness context to Mentora's tutor query
  contract. The backend remains the preferred inference route, with the
  existing local fallback used when the backend is unavailable.
- Linux local inference can launch a compatible `llama-server`, wait for its
  health endpoint, consume `/completion` server-sent events, and terminate the
  server and HTTP client on completion or cancellation. Runtime discovery
  prefers newer LM Studio backends when present; unsupported GGUF type 41 from
  an older CLI can fall back to the detected server. This path currently uses
  a 2K context and two CPU threads; it does not enforce a hard process-RAM cap.
- The provider currently returns the completed tutor answer as a harness event.
  Although the Linux gateway reads token events from `llama-server`, those
  tokens are not yet streamed incrementally into the visible chat bubble.
- The harness keeps bounded in-memory conversation context for the active
  session. Persistent session summaries, long-term learner memory, retrieval,
  structured answer/artifact rendering, and image/file input remain follow-up
  work; they are not complete merely because the harness is integrated.
- Linux server execution remains a local Bonsai compatibility path.
  Android now builds its JNI runner against the pinned PrismML llama.cpp release
  `prism-b10777-e3de715`. The model selector uses the Bonsai 2 4B Q2_0 base
  model by default and rejects standalone DFlash2 drafter files. On-device
  generation and memory use still require verification on the target phone.

The next implementation gate is to verify model loading and cancellation
through the app's Linux gateway and surface the token stream through the
provider/UI, then validate Android runtime compatibility before treating local
model execution as cross-platform complete.
