import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_tutor_app/core/utils/youtube_utils.dart';
import 'package:offline_tutor_app/features/home/data/local/video_resource_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('YouTubeUtils Tests', () {
    test('isYouTubeUrl detects valid YouTube URLs and 11-char IDs', () {
      expect(YouTubeUtils.isYouTubeUrl('https://www.youtube.com/watch?v=EqJnQzD0mpQ'), isTrue);
      expect(YouTubeUtils.isYouTubeUrl('https://youtu.be/EqJnQzD0mpQ'), isTrue);
      expect(YouTubeUtils.isYouTubeUrl('https://m.youtube.com/watch?v=EqJnQzD0mpQ'), isTrue);
      expect(YouTubeUtils.isYouTubeUrl('https://www.youtube-nocookie.com/embed/EqJnQzD0mpQ'), isTrue);
      expect(YouTubeUtils.isYouTubeUrl('EqJnQzD0mpQ'), isTrue);
      expect(YouTubeUtils.isYouTubeUrl('https://example.com/video.mp4'), isFalse);
    });

    test('extractYouTubeId parses 11-char video ID cleanly', () {
      expect(YouTubeUtils.extractYouTubeId('https://www.youtube.com/watch?v=EqJnQzD0mpQ'), equals('EqJnQzD0mpQ'));
      expect(YouTubeUtils.extractYouTubeId('https://youtu.be/Rm7U4ib8qAo'), equals('Rm7U4ib8qAo'));
      expect(YouTubeUtils.extractYouTubeId('https://www.youtube.com/embed/wOLprZLtbgQ'), equals('wOLprZLtbgQ'));
      expect(YouTubeUtils.extractYouTubeId('EqJnQzD0mpQ'), equals('EqJnQzD0mpQ'));
    });

    test('extractYouTubeId returns null on invalid or unparseable URLs (no dummy demo masking)', () {
      expect(YouTubeUtils.extractYouTubeId('invalid_url_text'), isNull);
      expect(YouTubeUtils.extractYouTubeId('https://example.com/test'), isNull);
      expect(YouTubeUtils.extractYouTubeId(''), isNull);
    });

    test('getThumbnailUrl formats high quality thumbnail link', () {
      expect(
        YouTubeUtils.getThumbnailUrl('EqJnQzD0mpQ'),
        equals('https://img.youtube.com/vi/EqJnQzD0mpQ/hqdefault.jpg'),
      );
    });
  });

  group('VideoResourceRepository Tier-3 Fallback Tests', () {
    late VideoResourceRepository repo;

    setUp(() {
      repo = VideoResourceRepository();
    });

    test('Unmatched chapter returns empty list instead of grade-wide video dump', () async {
      final videos = await repo.getVideosForChapter('non_existent_chapter_id_999', grade: 9);
      expect(videos, isEmpty);
    });
  });
}
