sealed class TutorStreamEvent {
  const TutorStreamEvent();
}

/// An incremental token or text chunk emitted during generation.
final class TutorStreamChunkEvent extends TutorStreamEvent {
  const TutorStreamChunkEvent(this.chunk);

  final String chunk;
}

/// An intent from the model to execute a registered tool.
final class TutorStreamToolCallEvent extends TutorStreamEvent {
  const TutorStreamToolCallEvent({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// Emitted when the model completes its response successfully.
final class TutorStreamCompletedEvent extends TutorStreamEvent {
  const TutorStreamCompletedEvent({
    required this.fullText,
    required this.source,
    this.hasAudio = false,
    this.toolCalls = const [],
  });

  final String fullText;
  final String source;
  final bool hasAudio;
  final List<TutorStreamToolCallEvent> toolCalls;
}

/// Emitted when an error or cancellation abort occurs during generation.
final class TutorStreamErrorEvent extends TutorStreamEvent {
  const TutorStreamErrorEvent(this.error, {this.aborted = false});

  final String error;
  final bool aborted;
}
