import 'package:cchess/data/datasources/local/learning_seed.dart';
import 'package:cchess/data/repositories/learning_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Beginner lesson seed', () {
    test('contains a complete beginner course', () {
      expect(beginnerLessons, hasLength(greaterThanOrEqualTo(8)));

      for (final lesson in beginnerLessons) {
        expect(lesson.id, isNotEmpty);
        expect(lesson.titleVi, isNotEmpty);
        expect(lesson.subtitleVi, isNotEmpty);
        expect(lesson.sections, isNotEmpty, reason: 'lesson ${lesson.id}');
        expect(lesson.checkpoints, isNotEmpty, reason: 'lesson ${lesson.id}');
      }
    });

    test('ids and order are stable and unique', () {
      final ids = beginnerLessons.map((lesson) => lesson.id).toSet();
      final orders = beginnerLessons.map((lesson) => lesson.order).toSet();

      expect(ids, hasLength(beginnerLessons.length));
      expect(orders, hasLength(beginnerLessons.length));
      expect(beginnerLessons.first.id, 'b001');
    });

    test('covers all basic piece rules from B1', () {
      final covered = beginnerLessons
          .expand((lesson) => lesson.focusPieces)
          .toSet();

      expect(
        covered,
        containsAll(['Xe', 'Pháo', 'Mã', 'Tượng', 'Sĩ', 'Tốt', 'Tướng']),
      );
      expect(covered, contains('Chống Tướng'));
    });

    test('repository can resolve current and next lesson', () {
      const repo = LearningRepository();

      final first = repo.beginnerLessonById('b001');
      final next = repo.nextBeginnerLesson('b001');

      expect(first?.titleVi, 'Làm quen bàn cờ');
      expect(next?.id, 'b002');
      expect(repo.nextBeginnerLesson(beginnerLessons.last.id), isNull);
    });
  });
}
