import 'dart:io';

import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/data/models/game_record.dart';
import 'package:cchess/data/repositories/analysis_cache_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

GameRecord _record({List<String> moves = const ['h2e2', 'h7e7']}) {
  return GameRecord(
    id: 'rec-1',
    opponentLabel: 'Bot',
    mode: GameMode.vsBot,
    humanColor: PieceColor.red,
    startingFen: kInitialFen,
    moves: moves,
    result: GameStatus.redWin,
    endReason: EndReason.checkmate,
    eloDelta: 0,
    duration: const Duration(minutes: 5),
    endedAt: DateTime(2026, 7, 3),
  );
}

/// Build a small real analysis by replaying the record's moves.
GameAnalysis _analysis(GameRecord record, {EngineSource? source}) {
  final game = XiangqiGame.fromFen(record.startingFen);
  final moves = <MoveAnalysis>[];
  for (var i = 0; i < record.moves.length; i++) {
    final (from, to) = Move.parseUciCoords(record.moves[i])!;
    final piece = game.board.at(from)!;
    moves.add(
      MoveAnalysis(
        moveIndex: i,
        move: Move(
          from: from,
          to: to,
          moved: piece,
          captured: game.board.at(to),
        ),
        mover: game.turn,
        recommendedMove: null,
        bestEval: 30 + i,
        actualEval: 25 - i,
        centipawnLoss: 5 + i,
        quality: i == 0 ? MoveQuality.best : MoveQuality.good,
        evalAfterCp: 25 - i,
      ),
    );
    game.makeMove(from, to);
  }
  return GameAnalysis(
    moves: moves,
    redAccuracy: 100,
    blackAccuracy: 80,
    redBlunders: 0,
    blackBlunders: 1,
    redMistakes: 0,
    blackMistakes: 2,
    source: source,
  );
}

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('analysis_cache').path);
  });

  group('GameAnalysis codec', () {
    test('round-trips through encode/decode against the record', () {
      final record = _record();
      final original = _analysis(record, source: EngineSource.remotePikafish);

      final decoded = AnalysisCacheRepository.decodeGameAnalysis(
        AnalysisCacheRepository.encodeGameAnalysis(original),
        startingFen: record.startingFen,
        moveUcis: record.moves,
      );

      expect(decoded.source, EngineSource.remotePikafish);
      expect(decoded.redAccuracy, 100);
      expect(decoded.blackMistakes, 2);
      expect(decoded.moves, hasLength(2));
      expect(decoded.moves[0].quality, MoveQuality.best);
      expect(decoded.moves[0].move.toUci(), 'h2e2');
      expect(decoded.moves[0].mover, PieceColor.red);
      expect(decoded.moves[1].mover, PieceColor.black);
      expect(decoded.moves[1].evalAfterCp, 24);
      expect(decoded.moves[1].centipawnLoss, 6);
    });

    test('rejects a payload that no longer matches the record moves', () {
      final record = _record();
      final encoded = AnalysisCacheRepository.encodeGameAnalysis(
        _analysis(record, source: EngineSource.remotePikafish),
      );
      expect(
        () => AnalysisCacheRepository.decodeGameAnalysis(
          encoded,
          startingFen: record.startingFen,
          moveUcis: const ['b2e2', 'b7e7'], // different game
        ),
        throwsFormatException,
      );
    });
  });

  group('AnalysisCacheRepository', () {
    test('stores strong analyses and replays them', () async {
      final repo = AnalysisCacheRepository();
      final record = _record();

      expect(await repo.get(record), isNull);
      await repo.put(record, _analysis(record, source: EngineSource.localPikafish));

      final cached = await repo.get(record);
      expect(cached, isNotNull);
      expect(cached!.source, EngineSource.localPikafish);
      expect(cached.moves, hasLength(2));

      await repo.delete(record.id);
      expect(await repo.get(record), isNull);
    });

    test('refuses to cache weak minimax results', () async {
      final repo = AnalysisCacheRepository();
      final record = _record();
      await repo.delete(record.id);

      await repo.put(record, _analysis(record, source: EngineSource.localMinimax));
      expect(await repo.get(record), isNull);
    });
  });
}
