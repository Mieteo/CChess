import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../datasources/local/achievement_definitions.dart';
import '../models/achievement.dart';

class AchievementRepository {
  static const String _boxName = 'cchess_achievements';

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  /// Static list of all achievement definitions.
  List<Achievement> all() => kAchievements;

  Future<Map<String, AchievementProgress>> getAllProgress() async {
    final box = await _openBox();
    final out = <String, AchievementProgress>{};
    for (final a in kAchievements) {
      final raw = box.get(a.id);
      out[a.id] = raw is Map
          ? AchievementProgress.fromJson(raw)
          : AchievementProgress(id: a.id);
    }
    return out;
  }

  Future<AchievementProgress> getProgress(String id) async {
    final box = await _openBox();
    final raw = box.get(id);
    return raw is Map
        ? AchievementProgress.fromJson(raw)
        : AchievementProgress(id: id);
  }

  Future<void> markUnlocked(String id) async {
    final box = await _openBox();
    final progress = AchievementProgress(
      id: id,
      unlocked: true,
      unlockedAt: DateTime.now(),
    );
    await box.put(id, progress.toJson());
  }

  Future<void> clear() async {
    final box = await _openBox();
    await box.clear();
  }
}

final achievementRepositoryProvider =
    Provider<AchievementRepository>((ref) => AchievementRepository());

/// Pure engine that takes current stats + previous progress and computes
/// which achievements should be newly unlocked. Returns the list of
/// newly-unlocked Achievement objects (UI can show toasts for each).
class AchievementEngine {
  AchievementEngine._();

  static List<Achievement> newlyUnlocked({
    required AchievementStats stats,
    required Map<String, AchievementProgress> currentProgress,
  }) {
    final newlyUnlocked = <Achievement>[];
    for (final achievement in kAchievements) {
      final progress = currentProgress[achievement.id];
      if (progress?.unlocked == true) continue;
      final value = stats.statValue(achievement.statKey);
      if (value >= achievement.target) {
        newlyUnlocked.add(achievement);
      }
    }
    return newlyUnlocked;
  }
}
