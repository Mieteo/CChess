import 'package:cchess/data/datasources/local/achievement_definitions.dart';
import 'package:cchess/data/models/achievement.dart';
import 'package:cchess/data/repositories/achievement_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AchievementStats _stats({
  int totalGames = 0,
  int wins = 0,
  int winStreak = 0,
  int eloChess = 1000,
  int puzzlesSolved = 0,
  int loginStreak = 0,
}) {
  return AchievementStats(
    totalGames: totalGames,
    wins: wins,
    winStreak: winStreak,
    eloChess: eloChess,
    puzzlesSolved: puzzlesSolved,
    loginStreak: loginStreak,
  );
}

Map<String, AchievementProgress> _emptyProgress() {
  final m = <String, AchievementProgress>{};
  for (final a in kAchievements) {
    m[a.id] = AchievementProgress(id: a.id);
  }
  return m;
}

void main() {
  group('AchievementEngine.newlyUnlocked', () {
    test('returns empty list at zero stats', () {
      final unlocked = AchievementEngine.newlyUnlocked(
        stats: _stats(),
        currentProgress: _emptyProgress(),
      );
      expect(unlocked, isEmpty);
    });

    test('unlocks first_game after one game', () {
      final unlocked = AchievementEngine.newlyUnlocked(
        stats: _stats(totalGames: 1),
        currentProgress: _emptyProgress(),
      );
      expect(unlocked.map((a) => a.id), contains('first_game'));
    });

    test('unlocks first_win + first_game after one win', () {
      final unlocked = AchievementEngine.newlyUnlocked(
        stats: _stats(totalGames: 1, wins: 1),
        currentProgress: _emptyProgress(),
      );
      expect(
        unlocked.map((a) => a.id),
        containsAll(<String>['first_game', 'first_win']),
      );
    });

    test('does NOT re-unlock already-unlocked achievements', () {
      final progress = _emptyProgress();
      progress['first_win'] = const AchievementProgress(
        id: 'first_win',
        unlocked: true,
      );
      final unlocked = AchievementEngine.newlyUnlocked(
        stats: _stats(totalGames: 5, wins: 5),
        currentProgress: progress,
      );
      expect(unlocked.map((a) => a.id), isNot(contains('first_win')));
      expect(unlocked.map((a) => a.id), contains('first_game'));
    });

    test('elo tier unlocks cumulatively when high enough', () {
      final unlocked = AchievementEngine.newlyUnlocked(
        stats: _stats(eloChess: 2000),
        currentProgress: _emptyProgress(),
      );
      final ids = unlocked.map((a) => a.id).toSet();
      expect(ids, containsAll(<String>['elo_1200', 'elo_1600', 'elo_2000']));
    });

    test('puzzle achievements respect the threshold', () {
      final mid = AchievementEngine.newlyUnlocked(
        stats: _stats(puzzlesSolved: 5),
        currentProgress: _emptyProgress(),
      );
      final ids = mid.map((a) => a.id).toSet();
      expect(ids, contains('puzzle_1'));
      expect(ids, contains('puzzle_5'));
      expect(ids, isNot(contains('puzzle_15')));
    });
  });

  group('Achievement catalog sanity', () {
    test('every achievement has a unique id', () {
      final ids = kAchievements.map((a) => a.id).toSet();
      expect(ids.length, kAchievements.length);
    });

    test('every achievement has a non-empty Vietnamese name + desc', () {
      for (final a in kAchievements) {
        expect(a.nameVi, isNotEmpty, reason: a.id);
        expect(a.descVi, isNotEmpty, reason: a.id);
      }
    });

    test('every achievement statKey is recognised by AchievementStats', () {
      const knownKeys = {
        'wins',
        'totalGames',
        'puzzlesSolved',
        'winStreak',
        'eloChess',
        'loginStreak',
      };
      for (final a in kAchievements) {
        expect(knownKeys, contains(a.statKey), reason: a.id);
      }
    });
  });
}
