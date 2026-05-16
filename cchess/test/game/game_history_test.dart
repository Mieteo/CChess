// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/data/models/game_record.dart';
import 'package:cchess/data/repositories/game_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp.createTempSync('cchess_hist_test_').path;
    return _dir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() => _ensureDir();
  @override
  Future<String?> getApplicationSupportPath() => _ensureDir();
  @override
  Future<String?> getTemporaryPath() => _ensureDir();
}

GameRecord _sample({
  String id = '',
  GameMode mode = GameMode.vsBot,
  PieceColor? human = PieceColor.red,
  GameStatus result = GameStatus.redWin,
  DateTime? endedAt,
}) {
  return GameRecord(
    id: id,
    opponentLabel: 'Bot Trung Cấp',
    mode: mode,
    humanColor: human,
    startingFen: kInitialFen,
    moves: const ['b2e2', 'b7e7'],
    result: result,
    endReason: EndReason.checkmate,
    eloDelta: 0,
    duration: const Duration(minutes: 4, seconds: 30),
    endedAt: endedAt ?? DateTime(2026, 5, 16, 12, 0),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    final box =
        await Hive.openBox<dynamic>('cchess_game_history');
    await box.clear();
  });

  group('GameHistoryRepository', () {
    test('save assigns an id and returns the record', () async {
      final repo = GameHistoryRepository();
      final saved = await repo.save(_sample());
      expect(saved.id, isNotEmpty);

      final back = await repo.getById(saved.id);
      expect(back, isNotNull);
      expect(back!.opponentLabel, saved.opponentLabel);
    });

    test('all() returns records newest-first', () async {
      final repo = GameHistoryRepository();
      await repo.save(_sample(endedAt: DateTime(2026, 5, 1)));
      await repo.save(_sample(endedAt: DateTime(2026, 5, 10)));
      await repo.save(_sample(endedAt: DateTime(2026, 5, 5)));

      final list = await repo.all();
      expect(list, hasLength(3));
      expect(list[0].endedAt.day, 10);
      expect(list[1].endedAt.day, 5);
      expect(list[2].endedAt.day, 1);
    });

    test('toggleFavorite flips the flag', () async {
      final repo = GameHistoryRepository();
      final saved = await repo.save(_sample());
      expect(saved.isFavorite, isFalse);
      await repo.toggleFavorite(saved.id);
      final back = await repo.getById(saved.id);
      expect(back!.isFavorite, isTrue);
    });

    test('delete removes the record', () async {
      final repo = GameHistoryRepository();
      final saved = await repo.save(_sample());
      await repo.delete(saved.id);
      expect(await repo.getById(saved.id), isNull);
    });

    test('humanWon honors the player color', () {
      final r = _sample(human: PieceColor.red, result: GameStatus.redWin);
      expect(r.humanWon, isTrue);
      final l =
          _sample(human: PieceColor.black, result: GameStatus.redWin);
      expect(l.humanWon, isFalse);
      final d = _sample(result: GameStatus.draw);
      expect(d.humanWon, isFalse);
      expect(d.isDraw, isTrue);
    });
  });
}
