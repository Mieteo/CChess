// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/models/daily_quest.dart';
import 'package:cchess/data/repositories/daily_quest_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??=
        Directory.systemTemp.createTempSync('cchess_quest_test_').path;
    return _dir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() => _ensureDir();
  @override
  Future<String?> getApplicationSupportPath() => _ensureDir();
  @override
  Future<String?> getTemporaryPath() => _ensureDir();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    final box = await Hive.openBox<dynamic>('cchess_daily_quests');
    await box.clear();
  });

  group('DailyQuestRepository', () {
    test('getToday creates fresh state when nothing stored', () async {
      final repo = DailyQuestRepository();
      final state = await repo.getToday();
      expect(state.day, DailyQuestRepository.todayKey());
      expect(state.gamesPlayed, 0);
      expect(state.claimedQuestIds, isEmpty);
    });

    test('save + getToday round-trips the state', () async {
      final repo = DailyQuestRepository();
      final state = await repo.getToday();
      final updated = state.copyWith(
        gamesPlayed: 3,
        gamesWon: 1,
        puzzlesSolved: 2,
        claimedQuestIds: {'q_login'},
      );
      await repo.save(updated);
      final back = await DailyQuestRepository().getToday();
      expect(back.gamesPlayed, 3);
      expect(back.gamesWon, 1);
      expect(back.puzzlesSolved, 2);
      expect(back.claimedQuestIds, {'q_login'});
    });

    test('getToday resets state when day rolls over', () async {
      final repo = DailyQuestRepository();
      // Manually save state under yesterday's key.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final stale = DailyQuestState(
        day: DailyQuestRepository.todayKey(yesterday),
        gamesPlayed: 5,
        gamesWon: 2,
        claimedQuestIds: const {'q_login', 'q_play_1'},
      );
      await repo.save(stale);

      final fresh = await DailyQuestRepository().getToday();
      expect(fresh.day, DailyQuestRepository.todayKey(),
          reason: 'day should reset to today');
      expect(fresh.gamesPlayed, 0);
      expect(fresh.claimedQuestIds, isEmpty);
    });
  });

  group('DailyQuestState.isComplete / isClaimed', () {
    const playOne = DailyQuest(
      id: 'q_play_1',
      kind: QuestKind.playGames,
      titleVi: 'Chơi 1 ván',
      descVi: '',
      target: 1,
      rewardCoins: 50,
    );

    test('not complete when below target', () {
      final s = DailyQuestState(day: '2026-05-16');
      expect(s.isComplete(playOne), isFalse);
    });

    test('complete when at or above target', () {
      final s = DailyQuestState(day: '2026-05-16', gamesPlayed: 1);
      expect(s.isComplete(playOne), isTrue);
    });

    test('claimed flag works independently', () {
      final s = DailyQuestState(
        day: '2026-05-16',
        gamesPlayed: 1,
        claimedQuestIds: const {'q_play_1'},
      );
      expect(s.isComplete(playOne), isTrue);
      expect(s.isClaimed(playOne), isTrue);
    });
  });
}
