import 'package:equatable/equatable.dart';

import '../../core/chess_engine/chess_engine.dart';

/// Snapshot of a single finished game, persisted to local Hive storage.
///
/// We don't store the live [XiangqiGame] (which carries a mutable board);
/// instead we keep the starting FEN + the list of UCI moves so the game
/// can be re-built deterministically when the user wants to replay.
class GameRecord extends Equatable {
  /// Unique record id (generated when saving).
  final String id;

  /// Display label for the opponent ("Bot Trung Cấp", "Người Chơi 2", …).
  final String opponentLabel;

  /// Mode this game was played in.
  final GameMode mode;

  /// Color the human ("you") played. Null when the game is local 2-player.
  final PieceColor? humanColor;

  /// Starting position. Standard initial FEN for full games, custom for
  /// puzzles or scenarios.
  final String startingFen;

  /// Move list in UCI notation.
  final List<String> moves;

  /// Final lifecycle status.
  final GameStatus result;

  /// Why the game ended (checkmate, resignation, timeout, draw, …).
  final EndReason? endReason;

  /// ELO points the human gained (positive) or lost (negative). Zero for
  /// local games and bot games (no ranked play yet).
  final int eloDelta;

  /// Total play duration.
  final Duration duration;

  /// Wall-clock time the game ended.
  final DateTime endedAt;

  /// Marked by the user.
  final bool isFavorite;

  const GameRecord({
    required this.id,
    required this.opponentLabel,
    required this.mode,
    required this.humanColor,
    required this.startingFen,
    required this.moves,
    required this.result,
    required this.endReason,
    required this.eloDelta,
    required this.duration,
    required this.endedAt,
    this.isFavorite = false,
  });

  /// Whether the human won this game. Always false for local 2-player.
  bool get humanWon {
    if (humanColor == null) return false;
    if (result == GameStatus.redWin && humanColor == PieceColor.red) {
      return true;
    }
    if (result == GameStatus.blackWin && humanColor == PieceColor.black) {
      return true;
    }
    return false;
  }

  bool get isDraw => result == GameStatus.draw;
  bool get isFinished => result.isOver;

  Map<String, dynamic> toJson() => {
    'id': id,
    'opponentLabel': opponentLabel,
    'mode': mode.name,
    'humanColor': humanColor?.name,
    'startingFen': startingFen,
    'moves': moves,
    'result': result.name,
    'endReason': endReason?.name,
    'eloDelta': eloDelta,
    'durationSeconds': duration.inSeconds,
    'endedAt': endedAt.toIso8601String(),
    'isFavorite': isFavorite,
  };

  factory GameRecord.fromJson(Map<dynamic, dynamic> json) {
    return GameRecord(
      id: json['id'] as String,
      opponentLabel: json['opponentLabel'] as String,
      mode: GameMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => GameMode.localTwoPlayer,
      ),
      humanColor: json['humanColor'] == null
          ? null
          : PieceColor.values.firstWhere(
              (c) => c.name == json['humanColor'],
              orElse: () => PieceColor.red,
            ),
      startingFen: json['startingFen'] as String,
      moves: List<String>.from(json['moves'] as List? ?? const []),
      result: GameStatus.values.firstWhere(
        (s) => s.name == json['result'],
        orElse: () => GameStatus.draw,
      ),
      endReason: json['endReason'] == null
          ? null
          : EndReason.values.firstWhere(
              (r) => r.name == json['endReason'],
              orElse: () => EndReason.drawAgreed,
            ),
      eloDelta: json['eloDelta'] as int? ?? 0,
      duration: Duration(seconds: json['durationSeconds'] as int? ?? 0),
      endedAt: DateTime.parse(json['endedAt'] as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }

  GameRecord copyWith({bool? isFavorite}) => GameRecord(
    id: id,
    opponentLabel: opponentLabel,
    mode: mode,
    humanColor: humanColor,
    startingFen: startingFen,
    moves: moves,
    result: result,
    endReason: endReason,
    eloDelta: eloDelta,
    duration: duration,
    endedAt: endedAt,
    isFavorite: isFavorite ?? this.isFavorite,
  );

  @override
  List<Object?> get props => [
    id,
    opponentLabel,
    mode,
    humanColor,
    startingFen,
    moves,
    result,
    endReason,
    eloDelta,
    duration,
    endedAt,
    isFavorite,
  ];
}

/// Mode the game was played in. Mirrors [GameMode] in game_controller so we
/// can persist without coupling the data layer to presentation.
enum GameMode { localTwoPlayer, vsBot, vsOnline, cupLocal, cupVsBot, onlineCasual }

extension GameModeX on GameMode {
  String get nameVi {
    switch (this) {
      case GameMode.localTwoPlayer:
        return 'Đấu tại chỗ';
      case GameMode.vsBot:
        return 'Đấu với Bot';
      case GameMode.vsOnline:
        return 'Đấu online';
      case GameMode.cupLocal:
        return 'Cờ Úp';
      case GameMode.cupVsBot:
        return 'Cờ Úp với Máy';
      case GameMode.onlineCasual:
        return 'Đấu casual';
    }
  }
}
