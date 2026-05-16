import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/daily_quest.dart';

class DailyQuestRepository {
  static const String _boxName = 'cchess_daily_quests';
  static const String _key = 'today';

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  static String todayKey([DateTime? now]) {
    final n = now ?? DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Returns today's quest state, creating a fresh one (and resetting any
  /// stale data) if it's a new day.
  Future<DailyQuestState> getToday() async {
    final box = await _openBox();
    final raw = box.get(_key);
    final today = todayKey();
    if (raw is Map) {
      final state = DailyQuestState.fromJson(raw);
      if (state.day == today) return state;
    }
    final fresh = DailyQuestState(day: today);
    await save(fresh);
    return fresh;
  }

  Future<void> save(DailyQuestState state) async {
    final box = await _openBox();
    await box.put(_key, state.toJson());
  }

  Future<void> clear() async {
    final box = await _openBox();
    await box.clear();
  }
}

final dailyQuestRepositoryProvider =
    Provider<DailyQuestRepository>((ref) => DailyQuestRepository());

/// Central controller that keeps the day's quest state in sync with the
/// rest of the app. Each "record a thing happened today" method also
/// persists immediately.
class DailyQuestController extends StateNotifier<AsyncValue<DailyQuestState>> {
  final DailyQuestRepository _repo;

  DailyQuestController(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await _repo.getToday();
      if (mounted) state = AsyncValue.data(loaded);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> recordGamePlayed({required bool won}) async {
    await _mutate((s) => s.copyWith(
          gamesPlayed: s.gamesPlayed + 1,
          gamesWon: s.gamesWon + (won ? 1 : 0),
        ));
  }

  Future<void> recordPuzzleSolved() async {
    await _mutate((s) => s.copyWith(puzzlesSolved: s.puzzlesSolved + 1));
  }

  /// Returns the rewards the user just earned (or null if quest wasn't
  /// claimable). The caller is expected to apply the reward to the user's
  /// currency totals.
  Future<({int coins, int gems})?> claim(DailyQuest quest) async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (!current.isComplete(quest)) return null;
    if (current.isClaimed(quest)) return null;
    final next = current.copyWith(
      claimedQuestIds: {...current.claimedQuestIds, quest.id},
    );
    state = AsyncValue.data(next);
    await _repo.save(next);
    return (coins: quest.rewardCoins, gems: quest.rewardGems);
  }

  Future<void> _mutate(DailyQuestState Function(DailyQuestState) f) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = f(current);
    state = AsyncValue.data(next);
    await _repo.save(next);
  }
}

final dailyQuestControllerProvider = StateNotifierProvider<
    DailyQuestController, AsyncValue<DailyQuestState>>((ref) {
  return DailyQuestController(ref.watch(dailyQuestRepositoryProvider));
});
