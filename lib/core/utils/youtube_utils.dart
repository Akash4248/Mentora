/// Consolidated utility functions for YouTube URL detection, ID extraction, and thumbnail formatting.
class YouTubeUtils {
  const YouTubeUtils._();

  /// Regex pattern matching standard 11-character YouTube video IDs.
  static final RegExp _videoIdRegex = RegExp(r'^[a-zA-Z0-9_-]{11}$');

  /// Checks if [rawUrl] is a valid YouTube URL or raw 11-char video ID.
  static bool isYouTubeUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    if (_videoIdRegex.hasMatch(trimmed)) return true;

    final lower = trimmed.toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('m.youtube.com') ||
        lower.contains('youtube-nocookie.com') ||
        lower.contains('youtu.be');
  }

  /// Extracts the 11-character YouTube Video ID from [rawUrl].
  ///
  /// Returns `null` if the URL is invalid or cannot be parsed.
  /// (Does NOT mask invalid URLs with a dummy demo ID).
  static String? extractYouTubeId(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    if (_videoIdRegex.hasMatch(trimmed)) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      // 1. Standard URL parameter: ?v=VIDEO_ID
      if (uri.queryParameters.containsKey('v')) {
        final vParam = uri.queryParameters['v']?.trim();
        if (vParam != null && _videoIdRegex.hasMatch(vParam)) {
          return vParam;
        }
      }

      // 2. Shortened URL: youtu.be/VIDEO_ID
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        final idSegment = uri.pathSegments.first.trim();
        if (_videoIdRegex.hasMatch(idSegment)) {
          return idSegment;
        }
      }

      // 3. Embed URL: youtube.com/embed/VIDEO_ID
      if (uri.pathSegments.contains('embed')) {
        final embedIndex = uri.pathSegments.indexOf('embed');
        if (embedIndex + 1 < uri.pathSegments.length) {
          final idSegment = uri.pathSegments[embedIndex + 1].trim();
          if (_videoIdRegex.hasMatch(idSegment)) {
            return idSegment;
          }
        }
      }
    }

    return null;
  }

  /// Returns the high-quality thumbnail image URL for [videoId].
  static String getThumbnailUrl(String videoId) {
    final cleanId = extractYouTubeId(videoId) ?? videoId;
    return 'https://img.youtube.com/vi/$cleanId/hqdefault.jpg';
  }
}
