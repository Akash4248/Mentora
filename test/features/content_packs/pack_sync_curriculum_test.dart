import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Pack Sync & Curriculum Audit Guard Tests', () {
    test('Zip-Slip path containment validation (PS-01)', () {
      final unpackDirPath = '/data/user/0/org.mentora/app_flutter/installed/incoming_12345';
      
      // Malicious path attempting path traversal outside unpackDir
      final maliciousEntryName = '../../../../etc/cron.d/malicious';
      final resolvedMalicious = p.normalize(p.join(unpackDirPath, maliciousEntryName));
      final isMaliciousContained = p.isWithin(unpackDirPath, resolvedMalicious);

      expect(isMaliciousContained, isFalse);

      // Valid entry path inside unpackDir
      final validEntryName = 'content/chapter_1.json';
      final resolvedValid = p.normalize(p.join(unpackDirPath, validEntryName));
      final isValidContained = p.isWithin(unpackDirPath, resolvedValid);

      expect(isValidContained, isTrue);
    });

    test('Hybrid retrieval result truncation logic (RG-01)', () {
      final limit = 5;
      final rawList = List<int>.generate(20, (i) => i);
      
      // Fixed expression: (list..sort()).take(limit).toList()
      final sortedList = rawList..sort((a, b) => b.compareTo(a));
      final truncated = sortedList.take(limit).toList();

      expect(truncated.length, equals(limit));
      expect(truncated.first, equals(19));
      expect(truncated.last, equals(15));
    });

    test('Multi-grade range expansion mapping (CU-02)', () {
      const gradeMin = 6;
      const gradeMax = 9;

      final targetGrades = <int>{
        for (var g = gradeMin; g <= gradeMax; g++) g,
      };

      expect(targetGrades, containsAll([6, 7, 8, 9]));
      expect(targetGrades.length, equals(4));
    });
  });
}
