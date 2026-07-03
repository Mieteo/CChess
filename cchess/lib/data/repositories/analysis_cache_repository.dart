import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../models/game_record.dart';

/// Local cache of finished AI game reviews, keyed by [GameRecord.id].
///
/// A strong analysis costs real resources (server quota or minutes of
/// on-device engine time), so it is computed once and replayed for free.
/// Weak minimax results are deliberately not cached — the user should get a
/// real review on the next attempt, not a frozen shallow one.
class AnalysisCacheRepository {
  static const int _codecVersion = 1;

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(AppConstants.boxGameAnalysis);
    _box = box;
    return box;
  }

  /// Cached analysis for [record], or null when absent/stale/undecodable.
  Future<GameAnalysis?> get(GameRecord record) async {
    final box = await _openBox();
    final raw = box.get(record.id);
    if (raw is! Map) return null;
    try {
      return decodeGameAnalysis(
        Map<String, dynamic>.from(raw),
        startingFen: record.startingFen,
        moveUcis: record.moves,
      );
    } catch (_) {
      // Corrupt/legacy payload — drop it so the next analysis overwrites.
      await box.delete(record.id);
      return null;
    }
  }

  /// Persist [analysis] for [record]. Only strong sources are worth keeping.
  Future<void> put(GameRecord record, GameAnalysis analysis) async {
    if (record.id.isEmpty) return;
    final source = analysis.source;
    if (source != EngineSource.remotePikafish &&
        source != EngineSource.localPikafish) {
      return;
    }
    final box = await _openBox();
    await box.put(record.id, encodeGameAnalysis(analysis));
  }

  Future<void> delete(String recordId) async {
    final box = await _openBox();
    await box.delete(recordId);
  }

  /// Serialize to a plain JSON-ish map. Moves are stored as UCI + grades;
  /// the Move objects are rebuilt against the record when decoding.
  static Map<String, dynamic> encodeGameAnalysis(GameAnalysis analysis) => {
        'version': _codecVersion,
        'source': analysis.source?.name,
        'redAccuracy': analysis.redAccuracy,
        'blackAccuracy': analysis.blackAccuracy,
        'redBlunders': analysis.redBlunders,
        'blackBlunders': analysis.blackBlunders,
        'redMistakes': analysis.redMistakes,
        'blackMistakes': analysis.blackMistakes,
        'moves': [
          for (final m in analysis.moves)
            {
              'i': m.moveIndex,
              'uci': m.move.toUci(),
              'bestUci': m.recommendedMove?.toUci(),
              'bestEval': m.bestEval,
              'actualEval': m.actualEval,
              'evalAfterCp': m.evalAfterCp,
              'cpLoss': m.centipawnLoss,
              'quality': m.quality.name,
            },
        ],
      };

  /// Rebuild a [GameAnalysis] by replaying the record's moves to recover the
  /// piece/capture info the compact payload doesn't carry. Throws on version
  /// mismatch or when the payload no longer matches the record's moves.
  static GameAnalysis decodeGameAnalysis(
    Map<String, dynamic> json, {
    required String startingFen,
    required List<String> moveUcis,
  }) {
    if (json['version'] != _codecVersion) {
      throw const FormatException('Unsupported analysis codec version');
    }
    final rawMoves = json['moves'];
    if (rawMoves is! List) throw const FormatException('Missing moves');

    final game = XiangqiGame.fromFen(startingFen);
    final analyses = <MoveAnalysis>[];
    for (final raw in rawMoves) {
      final item = Map<String, dynamic>.from(raw as Map);
      final index = item['i'] as int;
      final uci = item['uci'] as String;
      if (index >= moveUcis.length || moveUcis[index] != uci) {
        throw const FormatException('Analysis does not match the record');
      }
      final coords = Move.parseUciCoords(uci);
      final piece = coords == null ? null : game.board.at(coords.$1);
      if (coords == null || piece == null) {
        throw const FormatException('Unreplayable analysed move');
      }
      final (from, to) = coords;

      Move? recommended;
      final bestUci = item['bestUci'] as String?;
      if (bestUci != null) {
        final bestCoords = Move.parseUciCoords(bestUci);
        final bestPiece =
            bestCoords == null ? null : game.board.at(bestCoords.$1);
        if (bestCoords != null && bestPiece != null) {
          recommended = Move(
            from: bestCoords.$1,
            to: bestCoords.$2,
            moved: bestPiece,
            captured: game.board.at(bestCoords.$2),
          );
        }
      }

      analyses.add(
        MoveAnalysis(
          moveIndex: index,
          move: Move(
            from: from,
            to: to,
            moved: piece,
            captured: game.board.at(to),
          ),
          mover: game.turn,
          recommendedMove: recommended,
          bestEval: item['bestEval'] as int? ?? 0,
          actualEval: item['actualEval'] as int? ?? 0,
          centipawnLoss: item['cpLoss'] as int? ?? 0,
          quality: _qualityFromName(item['quality'] as String?),
          evalAfterCp: item['evalAfterCp'] as int?,
        ),
      );

      if (!game.isValidMove(from, to)) {
        throw const FormatException('Analysis does not match the record');
      }
      game.makeMove(from, to);
    }

    return GameAnalysis(
      moves: analyses,
      redAccuracy: (json['redAccuracy'] as num?)?.toDouble() ?? 0,
      blackAccuracy: (json['blackAccuracy'] as num?)?.toDouble() ?? 0,
      redBlunders: json['redBlunders'] as int? ?? 0,
      blackBlunders: json['blackBlunders'] as int? ?? 0,
      redMistakes: json['redMistakes'] as int? ?? 0,
      blackMistakes: json['blackMistakes'] as int? ?? 0,
      source: _sourceFromName(json['source'] as String?),
    );
  }

  static MoveQuality _qualityFromName(String? name) {
    for (final quality in MoveQuality.values) {
      if (quality.name == name) return quality;
    }
    return MoveQuality.good;
  }

  static EngineSource? _sourceFromName(String? name) {
    for (final source in EngineSource.values) {
      if (source.name == name) return source;
    }
    return null;
  }
}

final analysisCacheRepositoryProvider = Provider<AnalysisCacheRepository>(
  (ref) => AnalysisCacheRepository(),
);
