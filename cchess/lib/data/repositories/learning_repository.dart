import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/local/learning_seed.dart' as learning_seed;
import '../models/learning_lesson.dart';

class LearningRepository {
  const LearningRepository();

  List<LearningLesson> beginnerLessons() =>
      List.unmodifiable(learning_seed.beginnerLessons);

  LearningLesson? beginnerLessonById(String id) {
    for (final lesson in beginnerLessons()) {
      if (lesson.id == id) return lesson;
    }
    return null;
  }

  LearningLesson? nextBeginnerLesson(String id) {
    final lessons = beginnerLessons();
    final index = lessons.indexWhere((lesson) => lesson.id == id);
    if (index == -1 || index + 1 >= lessons.length) return null;
    return lessons[index + 1];
  }
}

final learningRepositoryProvider = Provider<LearningRepository>((ref) {
  return const LearningRepository();
});
