import 'package:equatable/equatable.dart';

class LessonSection extends Equatable {
  final String title;
  final String body;
  final List<String> bullets;

  const LessonSection({
    required this.title,
    required this.body,
    this.bullets = const [],
  });

  @override
  List<Object?> get props => [title, body, bullets];
}

class LearningLesson extends Equatable {
  final String id;
  final int order;
  final String titleVi;
  final String subtitleVi;
  final String levelLabel;
  final int estimatedMinutes;
  final List<String> focusPieces;
  final List<LessonSection> sections;
  final List<String> checkpoints;
  final List<String> practicePuzzleIds;

  const LearningLesson({
    required this.id,
    required this.order,
    required this.titleVi,
    required this.subtitleVi,
    required this.levelLabel,
    required this.estimatedMinutes,
    required this.focusPieces,
    required this.sections,
    required this.checkpoints,
    this.practicePuzzleIds = const [],
  });

  @override
  List<Object?> get props => [
    id,
    order,
    titleVi,
    subtitleVi,
    levelLabel,
    estimatedMinutes,
    focusPieces,
    sections,
    checkpoints,
    practicePuzzleIds,
  ];
}
