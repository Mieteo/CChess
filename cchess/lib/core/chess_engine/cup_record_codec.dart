import 'board.dart';
import 'move.dart';
import 'piece.dart';
import 'position.dart';

/// Serialization of Cờ Úp hidden-piece data for [GameRecord] persistence (P3).
///
/// The hidden deal is stored as an explicit square→identity map — never as a
/// shuffle seed — so replays stay correct even if the shuffle algorithm
/// changes between app versions.
class CupRecordCodec {
  const CupRecordCodec._();

  /// Encode the square→true-identity map as a FEN-placement-style string
  /// (digits count squares WITHOUT a hidden identity). Compact, versionless,
  /// and reuses the battle-tested [Board] FEN reader/writer.
  static String encodeHiddenMap(Map<Position, Piece> hidden) {
    final board = Board.empty();
    hidden.forEach(board.setAt);
    return board.toFenPlacement();
  }

  /// Decode a string produced by [encodeHiddenMap]. Returns null on malformed
  /// input so callers can degrade to the legacy "no replay data" path instead
  /// of crashing on a corrupt record.
  static Map<Position, Piece>? decodeHiddenMap(String encoded) {
    final Board board;
    try {
      board = Board.fromFen(encoded);
    } on FormatException {
      return null;
    }
    return {for (final (pos, piece) in board.occupied()) pos: piece};
  }

  /// Per-move reveal list parallel to the UCI move list: entry i is the FEN
  /// char of the true identity revealed by move i (a face-down piece moving),
  /// or null when move i moved an already-revealed piece.
  ///
  /// Derived purely from the initial deal + move history, so it works no
  /// matter how many undos happened during the game.
  static List<String?> deriveReveals(
    Map<Position, Piece> initialHidden,
    List<Move> history,
  ) {
    final hidden = Set<Position>.from(initialHidden.keys);
    final reveals = <String?>[];
    for (final move in history) {
      final moverWasHidden = hidden.remove(move.from);
      // A captured face-down piece leaves the board; the mover now sits on
      // `to` face-up either way.
      hidden.remove(move.to);
      reveals.add(moverWasHidden ? move.moved.fenChar : null);
    }
    return reveals;
  }
}
