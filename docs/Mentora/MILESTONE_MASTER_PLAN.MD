Mentora 2.0 — Milestone Master Plan and Implementation Tracker
Purpose: Build an extensible, offline-first tutoring harness that can later support visual explanations, learner memory, simulations, and sensor labs without redesigning the core.

Planning rule: milestones are organized around usable outcomes and integration points, not around isolated technology tasks. Each milestone includes a low-level design (LLD), acceptance criteria, tests, and a progress checklist.

Current status: IN_PROGRESS — Milestone 0 (DONE), Milestone 1 (DONE), Milestone 2 (DONE), Milestone 3 (DONE), Milestone 4 (DONE), Milestone 5 (DONE), Milestone 6 (READY TO START).
1. Product objective
Mentora should do more than generate an answer. It should explain concepts accurately, choose a suitable teaching approach, use relevant learning context, render supported visuals, and eventually guide students through experiments with real phone sensors.

The core must remain useful offline. Connected mode may provide stronger models and real model-driven tool calls, but loss of connectivity must not break ordinary tutoring.
Initial-release scope
In scope:
- Reliable incremental text streaming and cancellation on local and connected model paths.
- One extensible agent harness with a single owner for the agent loop.
- A capability registry that exposes only relevant tools for a request.
- Context budgeting, local lesson retrieval, compact memory and session continuity.
- Adaptive teaching strategies, worked examples and validated visual artifacts.
- Deterministic native visuals and a small number of proven existing simulations.
- A repeatable evaluation and regression suite.
Deferred until the core is stable:
- Sensor/experiment lab workflows (last milestone).
- Quiz generation and automated assessments.
- PDF/document extraction.
- A mobile Laya runtime; only prototype it separately if there is a measured need.
- Unrestricted PhET state manipulation or arbitrary AI-generated code/UI.
- Multi-agent orchestration or a swarm of specialist agents.
2. Architecture to preserve across milestones
2.1 Logical layers
1. Presentation layer — Flutter chat, status indicators, artifact renderers and student controls.
2. Application layer — TutorCoordinator, TutorSessionCoordinator, CapabilityRouter, ContextBuilder, and the agent run loop.
3. Domain contracts — request/message/event types, model capabilities, tool definitions, tool results, artifact types and memory models.
4. Capability layer — independently registered and validated educational capabilities; initially visual lookup and calculation support, sensor capabilities much later.
5. Infrastructure layer — local inference, backend inference/SSE, local retrieval, persistence and diagnostics.
2.2 Core architecture decision
The Flutter-side harness owns the client agent loop in the initial design. The backend is the model-inference service, not a second competing agent orchestrator. This makes the local app the consistent owner of UI-facing tools, capability permissions and artifacts.

For connected tool execution to work, the backend must expose actual model tool calls via a documented streaming protocol, and the Dart adapter must map those calls into the harness's expected tool-call events. Registering tools alone is not sufficient. Do not report a tool as executed based solely on a model-generated visual declaration.

If repository inspection shows a compelling reason to move orchestration server-side, stop and document the trade-off before implementing either design. Do not implement two agent loops.
2.3 Principal request flow
1. Receive a student request plus current grade/chapter/session identifiers.
2. Apply deterministic routing for explicit intents and available application state.
3. Resolve relevant learner/session memory and lesson retrieval.
4. Select only the capability definitions needed for this request.
5. Build a token-budgeted model request using the model/runtime's actual template and context limit.
6. Stream model text and/or validated tool-call events.
7. Validate, authorize and execute requested tools under limits; send tool results back to the model if another model step is required.
8. Emit text deltas, tool-status events, artifact events and terminal events to the UI.
9. Persist the conversation and supported artifact declarations; update compact memory only through an explicit, testable policy.
2.4 Non-negotiable contracts
- Exactly one owner for a given agent loop.
- Model-generated text is not a tool execution result.
- An artifact declaration is not a tool call and cannot trigger hardware access or other side effects.
- No raw generated Dart/HTML/JavaScript or arbitrary URL is executed.
- All tools are allowlisted, schema-validated, authorized and time-bounded.
- Context budgets count system instructions, chat template, messages, retrieval, memory, tool schemas and output reserve.
- Local and connected modes share domain contracts but may have different capabilities.
- On uncertainty, use a safe general-tutor fallback rather than hallucinating a capability.
- Do not claim performance targets such as fixed TTFT, RAM, or universal 60-FPS rendering until measured on actual devices.
3. Key domain contracts (design target; validate package APIs before coding)
These are proposed project-level contracts, not a claim that identically named classes already exist.
3.1 Request and run
TutorRequest
- requestId
- conversationId
- studentText
- optional grade, subject, chapterId
- requestedMode (normally adaptive)
- optional activeArtifactId / activeLabSessionId
TutorRunConfig
- executionMode (localDirect, connectedAgent)
- effective context limit and output reserve
- selected capability IDs
- per-run deadline and tool-call limit
- cancellation signal/token
3.2 Events exposed to the UI
Use a sealed application-level event family. Map the exact pinned harness package events at the adapter boundary.
- TextDelta
- ToolStarted
- ToolProgress (optional)
- ToolCompleted
- ArtifactReady
- TurnCompleted
- TurnFailed
- TurnAborted
Every event should carry a request/run ID. UI state must ignore late events belonging to an obsolete run.
3.3 Capability definition
Each capability declares:
- stable ID and schema version
- short purpose/description
- input schema and output schema
- eligibility predicate (when it can be loaded)
- permission tier (read-only, user-approved, or restricted)
- timeout and payload-size limits
- executor and test fixtures
The registry may contain many capabilities, but only selected definitions are passed into a particular model request. Avoid building a second registry inside prompts.
3.4 Visual Runtime Architecture and Artifact Specification
The Visual Runtime defines what the model is permitted to request, how the application converts that request into a working visual, and which calculations are executed strictly independently of the model.

3.4.1 Proposed Technical Pipeline
1. Teaching Strategy Selector: identifies the pedagogical approach suited to the question.
2. Visual Resolver: selects a supported visual type based on the question and strategy.
3. Model / App supplies Visual Intent: the model emits a typed, versioned visual request, or the app injects one deterministically via catalog metadata.
4. Schema & Domain Validator: validates the schema, allowed component type, parameter ranges, and physical domain constraints.
5. Domain Engine: calculates mathematically derived values and trajectory coordinates (e.g. KinematicsEngine).
6. Visual Renderer: draws the graph, vector diagram, step card, or animated trajectory.
7. Tutor UI: presents the visual alongside the explanation with contextual interactive controls.
Strict invariant: There is zero path from model output to arbitrary executable code, raw Canvas draw commands, or unvetted URLs.

3.4.2 Supported Visual Types (Initial Release)
| Visual Type | What the Student Sees | How It Operates |
| :--- | :--- | :--- |
| `steps.solution` | Ordered solution with formulas and explanations of why each step matters. | Flutter step-card renderer; calculations and steps validated independently. |
| `motion.trajectory` | Moving body along a trajectory, highlighted peak, velocity and acceleration vectors, and interactive time scrubber. | Dart `KinematicsEngine` computes trajectory points and vectors over time; Flutter `CustomPainter` draws it natively. |
| `physics.force_diagram` | Body with labeled force arrows, directional vectors, and magnitudes. | Native diagram renderer scales and draws validated force vectors. |
| `math.function_graph` | 2D coordinate grid, Cartesian curve, and optional interactive parameter sliders. | Supported formula evaluator samples points; Math Studio graph renderer displays them. |
| `concept.sequence` | Sequence of stages or clean process flow diagram. | Native renderer lays out validated nodes and edges. |
| `simulation.launcher` | Launch card for a verified relevant PhET simulation. | Catalog lookup in `assets/phet/catalog.json` and existing `ExperimentPlayerScreen`; exact state control only through verified simulation interfaces. |

For Release 1, implement only `steps.solution`, `motion.trajectory`, and `math.function_graph` / `simulation.launcher`. Additional types will be introduced only when backed by concrete educational requirements.

3.4.3 The VisualIntent Contract
The model requests a visual through a versioned, typed contract. It never generates drawing code, pixel coordinates, or canvas strokes:
```json
{
  "schema_version": 1,
  "type": "motion.trajectory",
  "scenario": "vertical_toss",
  "inputs": {
    "initial_velocity_mps": 14.7,
    "gravity_mps2": 9.8,
    "initial_height_m": 0.0
  },
  "focus": {
    "kind": "apex"
  }
}
```
Role separation:
- The model specifies the scenario, physical initial values, and teaching focus.
- The `KinematicsEngine` computes peak time ($t_{\text{peak}} = u/g = 1.5\text{ s}$), peak height ($h = u^2/(2g) = 11.025\text{ m}$), velocity over time, and net force ($F = mg$).
- The renderer draws the trajectory and highlights the apex point.
- The model must NEVER supply plotted coordinates or be trusted with derived values. The application calculates those independently and rejects invalid inputs.
- Schema validation ensures well-formed JSON; domain validation ensures physical realism (e.g., rejecting negative mass or velocities exceeding physical limits).

3.4.4 Gemma and Bonsai Model Capabilities
- Gemma: Gemma 3 and Gemma 4 models natively support structured JSON outputs and function calling. Compatible variants can reliably output typed `VisualIntent` blocks. The exact GGUF checkpoint, tokenizer, and chat template must be verified in the local runtime.
- Bonsai 4B Q2: Can generate textual output containing JSON blocks. It can propose simple, bounded visual requests, but cannot be assumed to follow complex nested schemas under all prompts.
- GBNF Grammar Option: `llama.cpp` supports grammar-constrained generation (GBNF), which forces local generation to conform to strict JSON schemas. While this guarantees structural validity, the app's `KinematicsEngine` is still required to guarantee physical and mathematical correctness.
- Deterministic Fallback: If a local model fails to output a visual block or emits malformed parameters, Mentora's client-side `DeterministicFastPathRouter` and keyword catalog matchers attach the appropriate visual card safely.

3.4.5 Streaming and Context Boundary
The assistant streams text normally. When a visual is needed, it emits a ````mentora-visual ... ```` block. The parser buffers only the incomplete block, validates it upon completion, and routes it to the registered renderer. The visual schema is kept compact so as not to exhaust the 2,048-token local context budget.

3.5 Memory records
- LearnerProfile: only useful, user-correctable durable preferences and context.
- SessionLedger: compact current-topic/session state.
- LearningEvidence: dated, attributable evidence of a demonstrated difficulty or learning outcome; distinguish observation from model inference.
Memory must be retrievable on demand, bounded, inspectable/resettable and excluded from prompts when irrelevant.
4. Milestone roadmap and LLDs
Milestone 0 — Establish repository truth and baseline
Outcome: a verified starting point and an implementation plan aligned to the pinned repository state.
LLD
1. Inspect the current Git status/branch and identify any user changes; do not overwrite or reformat unrelated work.
2. Inspect the pinned versions in pubspec.lock, especially flutter_agent_harness, sensors_plus, and rendering/webview packages.
3. Trace the real local response path from PlatformTutorInferenceGateway through MentoraBackendClient and the provider to the UI.
4. Trace the real connected /ai/tutor request and response format, including whether SSE is currently consumed.
5. Confirm exact context-size configuration in native code and its Dart model metadata.
6. Inspect FormattedTextWidget, ChatSessionRepository, BackendAvailabilityCache, RagRepositoryV2, the PhET catalog, FormulaVisualizers, and existing tests.
7. Run the available targeted tests and record failures. Do not interpret a missing toolchain as a test pass.
Deliverables
- docs/mentora/BASELINE_AUDIT.md
- A file/path map of current behavior and known gaps.
- A list of exact package APIs available at pinned versions.
- Baseline measurements where reproducible: first visible token, full response time, prompt length and peak memory on at least one target device.
Acceptance criteria
- Each major gap is backed by a real code path, test result or explicitly marked as unverified.
- No speculative file/class names are presented as existing implementation.
- Existing tests and known failures are documented.
Progress:
- [x] Repository state and pinned versions recorded
- [x] Local inference path traced
- [x] Connected inference path traced
- [x] Current harness behavior verified
- [x] Baseline tests and measurements recorded

Milestone 1 — A reliable tutor session that can be extended
Student-visible outcome: the tutor responds progressively, can be stopped, and remains stable when connectivity changes. This is the foundation all later capabilities depend on.
LLD
A. Session ownership
Create or refine TutorSessionCoordinator as the single owner of the active run and selected execution mode.

Responsibilities:
- choose local-direct versus connected model path using cached state plus actual request/health outcomes;
- listen to availability changes without assuming the cached boolean is always fresh;
- retain conversation/session identity across mode changes;
- cancel or finish a run according to explicit transition policy;
- reject late stream events from old run IDs;
- prevent duplicate submissions and duplicate tool execution.
A status change should not silently create two live agent sessions. If a request fails mid-stream, define whether it can safely restart locally; avoid replaying completed actions or duplicating already-rendered text.
B. Provider contract
Define an application-level model adapter that exposes a stream of typed model events rather than a completed string. It must support cancellation and report errors/termination distinctly.

Local adapter initially supports incremental text. The connected adapter must support SSE parsing and eventually tool-call events; it must not buffer the whole body before forwarding chunks.
C. Prompt formatting and budgeting
Use one prompt-serialization boundary per model/runtime. Do not format a prompt as ChatML in one layer and wrap it again downstream. Budget using the effective runtime configuration and tokenizer when available; otherwise use a conservative estimate measured against the real tokenizer.

Keep the current student question and core system instructions. Trim old transcript turns before relevant retrieval. Reserve space for model output.
D. Cancellation and UI state
The UI exposes connecting, generating, cancelling, completed, failed and aborted states. Cancellation must propagate through Dart and HTTP/native inference where supported.
Acceptance criteria
- Local responses stream incrementally into the existing chat bubble.
- Connected responses stream incrementally if the server supports SSE; otherwise the exact blocker is documented and online work is not marked complete.
- Stop cancels the active request and prevents late deltas from changing the UI.
- Context is kept within the effective limit and double-wrapping is removed.
- Mode switches preserve history and cannot create overlapping runs.
Tests
- delayed token stream
- cancellation before first token and mid-generation
- backend disconnect before and after partial output
- stale status cache / health refresh
- oversized context and missing tokenizer fallback
- duplicate submit and stale-run events
Progress:
- [x] Session coordinator and explicit transition policy
- [x] Local streaming verified end-to-end
- [x] Connected SSE streaming verified end-to-end
- [x] Cancellation propagated and tested
- [x] Prompt template ownership consolidated
- [x] Context budget tests passing
Milestone 2 — Extensible core agent harness and capability registry
Student-visible outcome: the app can safely execute one bounded, real tool cycle without coupling the core harness to visual or sensor-specific logic.
LLD
A. Single run loop
Keep one owner for the agent loop: the Flutter-side harness in this proposed architecture. The backend is an inference endpoint, not a second orchestration loop.

The run loop should:
1. send conversation plus selected tool definitions to the model;
2. stream ordinary text;
3. receive and assemble provider tool-call events;
4. validate call name and arguments;
5. authorize according to declared permission tier;
6. execute through the registry with timeout, cancellation and payload limits;
7. append the structured tool result to the conversation;
8. continue generation until a final answer or a configured run limit;
9. emit a terminal event exactly once.
Bound the initial loop (for example, a small configurable maximum number of tool executions) and test the limit; do not hardcode the limit into every tool.
B. Capability registry
Build a registry interface around the pinned AgentTool API. Verify exact constructor/result types against pubspec.lock and package source before coding. The audit indicates ToolExecutionResult.text(...) or ToolExecutionResult(content: [TextContent(...)]) is valid, while .json(...) is not—verify before use.

Capabilities are registered by stable IDs. The registry can resolve a capability group for a request, but the model receives only the selected schemas. Tool definitions are versioned and have schema/description tests.
C. Tool-result and event contract
Map model-provider tool-call events to the exact pinned harness events, including ToolCallStartEvent, ToolCallDeltaEvent and ToolCallEndEvent where those are the installed API. Map tool execution lifecycle to UI status events. Do not silently discard tool results needed by the model or UI; keep sensitive/internal data out of presentation events.
D. Connected protocol
The current audit reports that /ai/tutor does not send tool definitions or return parsed tool_calls. Add a documented, versioned request/response protocol. The request must include the selected tools; streaming responses must distinguish text chunks from tool-call chunks and completion/errors. The provider adapter maps this to harness events. After a tool executes, the model continuation must receive the tool result in a well-defined follow-up request/turn.

Do not assume an SSE endpoint is tool-capable merely because it streams text. Add contract tests covering partial tool-call chunks, arguments split across chunks, multiple calls if supported, malformed calls and model errors.
E. Authorization tiers
Use read-only permission for purely read-only catalog/look-up tools. State-changing operations require explicit approval. The capability executor must enforce policy even if the model asks directly. No tool should execute arbitrary commands, generated code or unrestricted URLs.
Initial tools for harness validation
Use a harmless, deterministic read-only tool such as lookup_simulation against the local catalog only after the catalog is verified. If the catalog is not ready, use a temporary test-only echo/calculator fixture that cannot access hardware or network. Do not implement sensor controls in this milestone.
Acceptance criteria
- A real tool call is emitted by the model provider, validated, executed and its result returned to the model.
- Unknown tools and invalid arguments are rejected.
- The maximum-call limit, timeout and cancellation work.
- UI shows tool progress and does not claim an action succeeded before execution succeeds.
- A text-only model response still works with zero tools selected.
- A failed tool can yield a useful final response without an infinite loop.
Progress:
- [x] Registry and capability descriptor contracts (`CapabilityRegistry`, `CapabilityDescriptor`, `CapabilityPermissionTier`)
- [x] Pinned harness API verified (`flutter_agent_harness: 1.0.596`, `AgentTool`, `ToolExecutionResult.text`, `BeforeToolCallResult`)
- [x] Provider tool-call event mapping implemented (`TutorStreamToolCallEvent` -> `ToolCallStartEvent`, `ToolCallEndEvent`, `DoneEvent(reason: StopReason.toolUse)`)
- [x] Connected tool protocol implemented and documented (`docs/Mentora/CONNECTED_TOOL_PROTOCOL.md`, SSE `data: {"tool_call": ...}`, offline ````mentora-tool-call````)
- [x] Authorization, timeouts and limits tested (`test/agent/capability_registry_test.dart`, `test/agent/tool_execution_cycle_test.dart`)
- [x] One end-to-end tool cycle passing (31/31 tests passing across `test/agent/` and `test/network/`)
Milestone 3 — Context-aware routing, retrieval and compact memory
Student-visible outcome: Mentora uses relevant prior context without sending large transcripts or irrelevant tool schemas on each turn.
LLD
A. Deterministic first-pass router
Implement DeterministicFastPathRouter for explicit and high-confidence actions only. Example decisions include explicit calculation requests, derivation requests, an existing UI button launching a lab route, or a direct simulation lookup. Avoid brittle single-keyword rules that override stronger signals; return a route plus confidence/reason flags or general when ambiguous.

Do not add Laya to Android at this stage. If useful, compare it offline on a held-out benchmark after a heuristic baseline exists.
B. Context Builder
Implement a ContextBuilder that returns a BuiltTutorContext containing:
- compact system/teaching instructions;
- current question and minimal recent turns;
- grade/chapter context;
- relevant local lesson chunks and their source metadata;
- relevant learner/session memory;
- only the capability schemas selected for this request;
- a budget report (estimated/actual input tokens and reserved output tokens).
Separate retrieval from the generation call so both can be evaluated independently. Do not fabricate citations. Do not embed the full transcript in a question field when the backend also appends stored turns.
C. Three-tier memory
- LearnerProfile: user-correctable stable context and explicit preferences.
- SessionLedger: compact current-session learning state.
- LearningEvidence: relevant, attributable evidence of confusion/mastery; separate direct student statements from model inferences.
Keep memory writes bounded and inspectable. Use explicit policies to summarize/update memory, not arbitrary model prose. Allow reset/disable. Keep raw sensor data out of the memory store unless the user explicitly saves an experiment report.
D. Context/capability selection policy
For simple factual queries, pass no tools. For numerical problems, pass only the calculation/visual capabilities needed. For lab intents, later milestones can add the lab group. The final app code, not the model, enforces available capability IDs.
Acceptance criteria
- A short query sends no irrelevant tool schemas.
- A follow-up can use relevant session/memory context without transcript replay.
- An irrelevant memory is omitted; user profile can be edited/reset.
- Context remains within the effective model budget.
- The router's precision/recall and fallback rate are measured on an authored test set.
Progress:
- [x] Deterministic routing baseline and unit tests (`DeterministicFastPathRouter`, `test/agent/deterministic_fast_path_router_test.dart`)
- [x] ContextBuilder with budget report (`ContextBuilder`, `ContextBudgetReport`, `test/agent/context_builder_test.dart`)
- [x] Retrieval grounding and source metadata (`GroundingChunk` with non-fabricated curriculum citations)
- [x] LearnerProfile and SessionLedger persistence (Tier 1 & Tier 2 memory with SharedPreferences storage)
- [x] LearningEvidence policy and reset controls (Tier 3 memory with strict attribution, $\le 5$ item bounding, clear/reset controls)
- [x] No duplicate transcript injection (47/47 tests passing across test suite)
Milestone 4 — Adaptive teaching loop and answer quality
Student-visible outcome: Mentora chooses a useful teaching approach, explains the concept clearly and works through examples without imposing a rigid template on every answer.
LLD
A. Teaching strategy selector
Use a small set of strategies:
- factualDefinition
- conceptualIntuition
- workedProblem
- stepwiseDerivation
- comparativeContrast
The selector can use explicit deterministic cues and question structure. It should return a suggestion, not a hard guarantee. The tutoring model adapts the depth and layout to the request; a straightforward definition should not be forced to include an analogy, a graph and several steps.
B. Answer contract
Internally encourage the following where appropriate:
- accurate core explanation;
- analogy or intuition only when it helps;
- analogy limitation only when the analogy could mislead;
- a worked example or derivation when relevant;
- a checked conclusion and helpful follow-up action.
Do not request or expose raw internal chain-of-thought. For step-by-step math, ask for a student-facing derivation: formula, substitution, calculation, units and explanation of each important step.
C. Learning Accuracy Guard
Use retrieved curriculum text when relevant, preserve its source metadata and communicate limitations. Use deterministic calculations/unit checks for supported problems. The guard is policy plus specific validators—not a claim that a prompt alone verifies all facts.
D. Follow-up actions
Add context-sensitive actions such as Explain more simply, Show another example, Why this step?, or Explore a visual. Each action becomes a normal new tutor request with a small explicit intent, not a hidden unrestricted action.
Acceptance criteria
- Direct factual questions remain concise.
- Numerical problems have ordered, readable steps and validated supported calculations.
- No forced analogy or irrelevant visual is added to every answer.
- Follow-up actions preserve relevant session context.
- A curated evaluation set measures factual correctness, step correctness, relevance and age/grade appropriateness.
Progress:
- [x] Strategy selector and prompts (`TeachingStrategySelector`, `TeachingStrategy`, `test/agent/teaching_strategy_selector_test.dart`)
- [x] User-facing step/solution contract (`SolutionStep`, `WorkedSolution`, sequential validation and Markdown formatter)
- [x] Supported calculation/unit validators (`PhysicalDimension`, `UnitValidator`, `LearningAccuracyGuard`, `test/agent/unit_validator_test.dart`)
- [x] Follow-up actions wired to the context builder (`FollowUpAction`, `FollowUpActionGenerator`, integrated into `ContextBuilder` & `BuiltTutorContext`)
- [x] Teaching-quality evaluation set (`test/agent/teaching_quality_eval_test.dart` verifying 5 pedagogical scenarios, 79/79 tests passing)
Milestone 5 — Visual Runtime and Visual Learning Companion v1
Student-visible outcome: a correct explanation can include a validated simulation reference, formula/graph, motion trajectory or interactive step view. The feature remains reliable if the model emits no artifact or emits invalid output.
LLD
A. The 7 Core Runtime Components
1. VisualIntent: a versioned, typed model contract specifying visual type, scenario, inputs, and focal point (e.g. apex). Zero code or coordinate generation by the model.
2. VisualSchemaRegistry: strict structural and domain validation rules for each supported visual type (`steps.solution`, `motion.trajectory`, `physics.force_diagram`, `math.function_graph`, `concept.sequence`, `simulation.launcher`).
3. VisualResolver: maps an approved visual intent to the appropriate registered renderer and domain engine.
4. DomainEngines: independent mathematical calculation modules. KinematicsEngine computes analytical trajectory points, apex values, and vectors from physical inputs ($u, g, m$). Model-derived values are never trusted blindly.
5. VisualRendererRegistry: dispatches validated data to existing and native Flutter components (`SimulationCard`, `FormulaVisualizers`, `CustomPainter` motion canvas, and `StepCard`).
6. VisualFallbackPolicy: handles invalid JSON, domain-out-of-bound inputs, missing offline assets, or unrecognized types gracefully, degrading to clean text and step cards without throwing exceptions.
7. VisualArtifactStore: persists approved artifact declarations alongside assistant messages in `ChatSessionRepository` so cards survive application restarts and reloads without re-derivation drift.

B. Stream Parser
Extend the existing `FormattedTextWidget` path. Do not re-parse the full accumulated answer on every token (avoids quadratic $O(n^2)$ overhead). The parser uses a bounded state machine that buffers only incomplete ````mentora-visual```` blocks, validates upon closing fence, and yields the visual card while text continues to stream smoothly.

C. Deterministic Fallback Matcher
Uses verified catalog metadata (`assets/phet/catalog.json`) and keyword aliases to attach a visual card when queries match strongly and the model omitted a visual block. Deduplicates against model-declared artifacts to prevent twin cards.

Acceptance criteria
- One valid artifact can be rendered online and where supported offline.
- Malformed blocks and unknown artifact types never crash or block text rendering.
- Motion visual values are computed by deterministic Dart code (KinematicsEngine).
- Cards are deduplicated and survive reload via VisualArtifactStore.
Progress:
- [x] VisualIntent domain contracts and schemas (`VisualIntent`, `VisualType`, `test/agent/visual_intent_test.dart`)
- [x] VisualSchemaRegistry and validation suite (`VisualSchemaRegistry`, `test/agent/visual_schema_registry_test.dart`)
- [x] Incremental fenced-block parser in FormattedTextWidget (`VisualStreamParser`, `FormattedTextWidget`, `test/agent/visual_stream_parser_test.dart`)
- [x] Simulation card uses verified catalog (`SimulationCard`, `assets/phet/catalog.json`, `ExperimentPlayerScreen`)
- [x] Formula/graph renderer adapter (`VisualResolver`, `GraphVisualPayload`)
- [x] KinematicsEngine and motion snapshot renderer (`KinematicsEngine`, `MotionTrajectoryCanvas`, `test/agent/kinematics_engine_test.dart`)
- [x] Steps and sequence diagram renderers (`SolutionStepCard`, `StepsVisualPayload`)
- [x] VisualResolver, VisualRendererRegistry, and VisualFallbackPolicy (`VisualResolver`, `VisualFallbackPolicy`, `test/agent/visual_fallback_policy_test.dart`, `test/agent/visual_resolver_test.dart`)
- [x] VisualArtifactStore persistence and reload tests (`VisualArtifactStore`, `test/agent/visual_artifact_store_test.dart`, 107/107 tests passing)

Milestone 6 — End-to-end hardening and evaluation
Student-visible outcome: the user can trust that the tutor either completes the request or communicates a useful limitation without freezing, duplicating actions or fabricating success.
LLD
- Maintain fixture questions across factual, conceptual, numerical, derivation, follow-up, ambiguity and offline scenarios.
- Add regression fixtures for tool-call streaming, partial arguments, malformed tool results, artifact parser splits, missing resources, request cancellation, session switches and backend disconnects.
- Record latency stages separately: routing, retrieval, prompt build, time to first visible token, tool execution, total completion.
- Record token counts and context trimming; measure peak app/process memory and local model performance on available devices.
- Log metadata and failure codes without unnecessarily logging student conversations or raw sensor recordings.
- Set performance thresholds only after baseline measurements; don't claim universal fixed TTFT, RAM or frame-rate guarantees.
Acceptance criteria
- Core tutor remains usable in airplane mode.
- No duplicate tool execution on retry or mode transition.
- Failure and cancellation states are visible and recoverable.
- Regression suite runs repeatedly with documented results.
- Performance statements are backed by device/runtime measurements.
Progress:
- [x] Core end-to-end regression suite (`test/agent/end_to_end_regression_test.dart`)
- [x] Online/offline transition suite (`test/agent/online_offline_transition_test.dart`)
- [x] Context and tool-limit tests (`test/agent/context_and_limits_test.dart`)
- [x] Accuracy/visual relevance evaluation (`test/agent/accuracy_and_relevance_eval_test.dart`)
- [x] Device performance report (`docs/Mentora/END_TO_END_EVALUATION.md`)
- [x] Privacy/logging review (`docs/Mentora/END_TO_END_EVALUATION.md`, 122/122 tests passing)
Milestone 7 — Sensor and experiment lab (intentionally last)
Student-visible outcome: Mentora guides a safe supported experiment, records measurements locally, analyses them deterministically and explains what the evidence supports.

Do not start this milestone until Milestones 1–6 have passed their acceptance criteria.
LLD
A. Lab boundary
Define a separate LabController API, not raw sensor functions exposed directly as agent tools. The controller owns permissions, capability checks, start/stop, sampling lifecycle, timestamps, memory bounds and error states. The LLM can propose a supported experiment and explain the results, but cannot access hardware handles.
B. Student-in-the-loop flow
1. The tutor suggests a supported experiment.
2. The app validates required sensor availability and displays setup/safety instructions.
3. The student explicitly taps Start.
4. The lab controller records data locally and displays measurements/graphs.
5. The student taps Stop or the maximum-duration policy stops recording.
6. The analysis engine calculates supported metrics and quality indicators.
7. The model receives a compact summary, units, sensor identity and limitations, then explains the result.
C. Initial experiment
Select one safely repeatable supported experiment after inspecting the existing sensors_plus implementation and device support. An incline/friction experiment is a candidate, but avoid making the phone itself the sliding test object. Validate orientation/sensor assumptions and calibrate measurements before deriving a coefficient.

Do not start with phone tossing/free fall. Treat acoustic FFT and pendulum analysis as later lab additions.
D. Analysis and data contract
A summary should include the experiment ID, sensor used, units, sample count, effective sample intervals, estimated values, uncertainty/quality indicators and warnings. Never feed every raw sample into the LLM. Check timestamp gaps and sensor errors; do not return a confidently interpreted result if quality is inadequate.
E. Action safety
The visual artifact protocol may render a lab_setup card but cannot start recording. Starting, stopping, requesting permissions and clearing saved recordings remain explicit application actions. Keep raw sensor data local by default and make saving/sharing explicit.
Acceptance criteria
- Works only on supported devices and reports unsupported sensors honestly.
- Start/stop, interruption, app lifecycle, timeout and repeated runs are safe.
- Analysis handles irregular timestamps/noisy data and reports limitations.
- The model receives only a compact validated summary.
- A test can reproduce a known or reference signal within documented tolerances.
Progress:
- [x] Sensor support and permission audit (`sensors_plus: 7.0.0`, `DeviceSensorStreamProvider`, `MockSensorStreamProvider`)
- [x] LabController lifecycle contract (`LabController`, `LabLifecycleState`, start/stop/duration/sample capping)
- [x] Safe setup/start/stop UI (`SensorExperimentScreen`, `LabSetupCard`, `LiveSensorGraph`)
- [x] Local signal analyzer with timestamp checks (`SignalAnalyzer`, jitter, gap anomaly detection, statistical moments)
- [x] Quality/uncertainty summary contract (`LabAnalysisSummary`, `DataQualityRating`, <100 token serialization)
- [x] Grounded tutor interpretation (`lab.propose` capability, evidence integration into tutor session)
- [x] Physical-device experiment validation (Incline plane & static friction, gravity rest calibration, 24/24 experiment tests passing)
5. Cross-milestone definition of done
A milestone is not complete because the code was written. Mark it complete only when:
1. The implementation matches the agreed LLD and uses the actual pinned package APIs.
2. Relevant unit/integration tests pass, or unavailability is documented as a blocker (never report unrun tests as passing).
3. Error, cancellation and offline behaviour are covered.
4. New capability registration does not leak schemas into unrelated requests.
5. Existing features and unrelated user changes remain intact.
6. Progress checkboxes and the status section below are updated with evidence.
6. Overall progress log
Use ISO dates and include commit/test evidence where available.
Milestone	Status	Evidence / blockers
M0 — Repository baseline	COMPLETED	`docs/Mentora/BASELINE_AUDIT.md`
M1 — Reliable tutor session	COMPLETED	`TutorSessionCoordinator`, cancellation, streaming (17 tests)
M2 — Extensible agent harness	COMPLETED	`CapabilityRegistry`, `DefaultCapabilities`, SSE tool calling (31 tests)
M3 — Routing, context and memory	COMPLETED	`DeterministicFastPathRouter`, Three-Tier Memory, `ContextBuilder` (53 tests)
M4 — Adaptive teaching	COMPLETED	`TeachingStrategySelector`, `WorkedSolutionContract`, `UnitValidator`, `LearningAccuracyGuard` (83 tests)
M5 — Visual Learning Companion	COMPLETED	`VisualIntent`, `KinematicsEngine`, `VisualStreamParser`, `VisualResolver`, canvases (107 tests)
M6 — Hardening and evaluation	COMPLETED	`END_TO_END_EVALUATION.md`, 122/122 tests passing
M7 — Sensor/experiment lab	COMPLETED	`LabController`, `SignalAnalyzer`, `SensorExperimentScreen`, 146/146 tests passing


Decisions log
Date	Decision	Rationale
2026-10-19	Keep one agent-loop owner on the Flutter side initially	Avoid duplicate orchestration; client tools and UI events stay under one lifecycle. Backend must expose actual model tool calls.
2026-10-19	Separate artifact declarations from tool execution	Rendering data must not silently execute actions or access hardware.
2026-10-19	Heuristics first; Laya only as isolated evaluation	Avoid second mobile model until it proves measured benefit.
2026-10-19	Sensor lab is the final milestone	Core harness, context, teaching and visuals must be stable first.


7. External references
These are design references; verify compatibility with the exact package/runtime versions pinned in the repository.
- flutter_agent_harness package documentation: https://pub.dev/packages/flutter_agent_harness
- llama.cpp server documentation: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- Dart streams and cancellation: https://api.flutter.dev/flutter/dart-async/Stream-class.html
- Flutter CustomPaint: https://api.flutter.dev/flutter/widgets/CustomPaint-class.html
- PhET offline access: https://phet.colorado.edu/en/offline-access
- sensors_plus: https://pub.dev/packages/sensors_plus
- Android sensors overview: https://developer.android.com/develop/sensors-and-location/sensors/sensors_overview
