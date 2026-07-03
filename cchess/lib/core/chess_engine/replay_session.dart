import '../constants/piece_constants.dart';
import 'board.dart';
import 'cup_record_codec.dart';
import 'move.dart';
import 'piece.dart';
import 'position.dart';
import 'xiangqi_cup_game.dart';
import 'xiangqi_game.dart';

/// One replay position: the board after N applied moves, which squares are
/// still face-down (Cờ Úp only), and the move that produced the position.
class ReplayFrame {
  final Board board;
  final Set<Position> hiddenPositions;
  final Move? lastMove;

  const ReplayFrame({
    required this.board,
    this.hiddenPositions = const {},
    this.lastMove,
  });
}

/// Variant-aware playback of a saved game (P3).
///
/// Frames are precomputed once at construction: seeks become O(1) lookups and
/// — crucially — an invalid move stops the frame list right there instead of
/// letting the move-list cursor run past a frozen board. [playableMoves] is
/// how far the board can actually go; a record whose data is intact has
/// `playableMoves == moves.length`.
abstract class ReplaySession {
  final List<ReplayFrame> _frames;

  ReplaySession._(this._frames);

  /// Number of leading moves that could be applied on the board.
  int get playableMoves => _frames.length - 1;

  /// Position after [ply] applied moves (0 = start). [ply] is clamped.
  ReplayFrame frameAt(int ply) => _frames[ply.clamp(0, playableMoves)];

  /// Build the right session for a record's variant + data completeness.
  factory ReplaySession.build({
    required bool isCupGame,
    required String startingFen,
    required List<String> moveUcis,
    String? cupHiddenFen,
    List<String?>? cupReveals,
  }) {
    if (!isCupGame) {
      return StandardReplaySession(
        startingFen: startingFen,
        moveUcis: moveUcis,
      );
    }
    final hidden = cupHiddenFen == null
        ? null
        : CupRecordCodec.decodeHiddenMap(cupHiddenFen);
    if (hidden == null) {
      // Legacy Cờ Úp record: the deal was never saved, an accurate replay is
      // impossible (doc 14 §4.2) — show the untouched starting position only.
      return LegacyCupReplaySession(startingFen: startingFen);
    }
    return CupReplaySession(
      startingFen: startingFen,
      initialHidden: hidden,
      moveUcis: moveUcis,
      expectedReveals: cupReveals,
    );
  }
}

/// Standard (full-information) games: replay with [XiangqiGame] rules.
class StandardReplaySession extends ReplaySession {
  StandardReplaySession({
    required String startingFen,
    required List<String> moveUcis,
  }) : super._(_build(startingFen, moveUcis));

  static List<ReplayFrame> _build(String startingFen, List<String> moveUcis) {
    final game = XiangqiGame.fromFen(startingFen);
    final frames = <ReplayFrame>[ReplayFrame(board: game.board.copy())];
    for (final uci in moveUcis) {
      final coords = Move.parseUciCoords(uci);
      if (coords == null || !game.isValidMove(coords.$1, coords.$2)) break;
      final move = game.makeMove(coords.$1, coords.$2);
      frames.add(ReplayFrame(board: game.board.copy(), lastMove: move));
    }
    return frames;
  }
}

/// Cờ Úp games saved with the full deal ([cupHiddenFen]): replay with the real
/// cup rules so each ply shows exactly which pieces are still face-down and
/// what each reveal turned out to be.
class CupReplaySession extends ReplaySession {
  CupReplaySession({
    required String startingFen,
    required Map<Position, Piece> initialHidden,
    required List<String> moveUcis,
    List<String?>? expectedReveals,
  }) : super._(_build(startingFen, initialHidden, moveUcis, expectedReveals));

  static List<ReplayFrame> _build(
    String startingFen,
    Map<Position, Piece> initialHidden,
    List<String> moveUcis,
    List<String?>? expectedReveals,
  ) {
    final game = XiangqiCupGame.debug(
      board: Board.fromFen(startingFen),
      hiddenAssignments: initialHidden,
    );
    final frames = <ReplayFrame>[
      ReplayFrame(
        board: game.board.copy(),
        hiddenPositions: game.hiddenPositions,
      ),
    ];
    for (var i = 0; i < moveUcis.length; i++) {
      final coords = Move.parseUciCoords(moveUcis[i]);
      if (coords == null || !game.isValidMove(coords.$1, coords.$2)) break;
      final moverWasHidden = game.isHidden(coords.$1);
      final move = game.makeMove(coords.$1, coords.$2);
      // Cross-check against the recorded reveal log: a mismatch means the
      // stored deal and the move list disagree — stop rather than show a
      // divergent game.
      if (expectedReveals != null && i < expectedReveals.length) {
        final reveal = moverWasHidden ? move.moved.fenChar : null;
        if (expectedReveals[i] != reveal) break;
      }
      frames.add(
        ReplayFrame(
          board: game.board.copy(),
          hiddenPositions: game.hiddenPositions,
          lastMove: move,
        ),
      );
    }
    return frames;
  }
}

/// Pre-P3 Cờ Úp records carry no reveal data: board playback is disabled
/// (playableMoves == 0) and the start position is shown with every
/// non-general piece face-down — exactly how the table looked at move 0.
class LegacyCupReplaySession extends ReplaySession {
  LegacyCupReplaySession({required String startingFen})
      : super._(_build(startingFen));

  static List<ReplayFrame> _build(String startingFen) {
    final board = Board.fromFen(startingFen);
    final hidden = <Position>{
      for (final (pos, piece) in board.occupied())
        if (piece.type != PieceType.general) pos,
    };
    return [ReplayFrame(board: board, hiddenPositions: hidden)];
  }
}
