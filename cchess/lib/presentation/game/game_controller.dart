import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/models/game_record.dart';

// GameMode lives in [game_record.dart] so the data + presentation layers
// agree on the same enum. Re-exported for convenience.
export '../../data/models/game_record.dart' show GameMode, GameModeX;

/// Family-key for the per-screen game controller. Keeps each navigation to
/// /game with different params isolated.
class GameControllerArgs {
  final GameMode mode;
  final PieceColor? cpuColor;
  final BotDifficulty? botDifficulty;

  const GameControllerArgs({
    required this.mode,
    this.cpuColor,
    this.botDifficulty,
  });

  @override
  bool operator ==(Object other) =>
      other is GameControllerArgs &&
      other.mode == mode &&
      other.cpuColor == cpuColor &&
      other.botDifficulty == botDifficulty;

  @override
  int get hashCode => Object.hash(mode, cpuColor, botDifficulty);
}

/// Snapshot of game state observed by the UI.
class GameUiState {
  final ChessGameSession game;
  final Position? selected;
  final List<Position> validTargets;
  final Move? lastMove;
  final bool boardFlipped;
  final GameMode mode;
  final PieceColor? cpuColor;
  final BotDifficulty? botDifficulty;
  final bool cpuThinking;
  final Move? hintMove;
  final bool hintThinking;

  const GameUiState({
    required this.game,
    required this.selected,
    required this.validTargets,
    required this.lastMove,
    required this.boardFlipped,
    required this.mode,
    required this.cpuColor,
    required this.botDifficulty,
    required this.cpuThinking,
    this.hintMove,
    this.hintThinking = false,
  });

  GameUiState copyWith({
    ChessGameSession? game,
    Position? selected,
    bool clearSelected = false,
    List<Position>? validTargets,
    Move? lastMove,
    bool clearLastMove = false,
    bool? boardFlipped,
    GameMode? mode,
    PieceColor? cpuColor,
    BotDifficulty? botDifficulty,
    bool? cpuThinking,
    Move? hintMove,
    bool clearHint = false,
    bool? hintThinking,
  }) {
    return GameUiState(
      game: game ?? this.game,
      selected: clearSelected ? null : (selected ?? this.selected),
      validTargets: validTargets ?? this.validTargets,
      lastMove: clearLastMove ? null : (lastMove ?? this.lastMove),
      boardFlipped: boardFlipped ?? this.boardFlipped,
      mode: mode ?? this.mode,
      cpuColor: cpuColor ?? this.cpuColor,
      botDifficulty: botDifficulty ?? this.botDifficulty,
      cpuThinking: cpuThinking ?? this.cpuThinking,
      hintMove: clearHint ? null : (hintMove ?? this.hintMove),
      hintThinking: hintThinking ?? this.hintThinking,
    );
  }

  /// Whose turn it is currently.
  PieceColor get turn => game.turn;

  /// Any mode where one seat is the local bot (standard or Cờ Úp).
  bool get isVsBot =>
      mode == GameMode.vsBot || mode == GameMode.cupVsBot;

  /// Any Cờ Úp mode (local hotseat or vs bot).
  bool get isCup =>
      mode == GameMode.cupLocal || mode == GameMode.cupVsBot;

  /// Two humans sharing one device (no bot, no network).
  bool get isLocalHotseat =>
      mode == GameMode.localTwoPlayer || mode == GameMode.cupLocal;

  /// True if the human input should be accepted right now.
  bool get acceptsInput {
    if (game.status.isOver) return false;
    if (cpuThinking) return false;
    if (isVsBot && cpuColor == turn) return false;
    return true;
  }
}

/// Riverpod notifier that wraps [XiangqiGame] for the screen.
///
/// All mutations (tap, makeMove, undo, …) go through here so the UI stays in
/// sync. The notifier intentionally keeps a single XiangqiGame instance and
/// emits a new [GameUiState] after each operation — XiangqiGame itself is
/// mutable for performance.
class GameController extends StateNotifier<GameUiState> {
  GameController({
    GameMode mode = GameMode.localTwoPlayer,
    PieceColor? cpuColor,
    BotDifficulty? botDifficulty,
  }) : super(
         GameUiState(
           game: _newSession(mode),
           selected: null,
           validTargets: const [],
           lastMove: null,
           boardFlipped: false,
           mode: mode,
           cpuColor: cpuColor,
           botDifficulty: botDifficulty,
           cpuThinking: false,
         ),
       );

  /// Reset to the standard starting position.
  void newGame() {
    state = GameUiState(
      game: _newSession(state.mode),
      selected: null,
      validTargets: const [],
      lastMove: null,
      boardFlipped: state.boardFlipped,
      mode: state.mode,
      cpuColor: state.cpuColor,
      botDifficulty: state.botDifficulty,
      cpuThinking: false,
    );
  }

  void toggleFlip() {
    state = state.copyWith(boardFlipped: !state.boardFlipped);
  }

  /// Handle a tap on intersection (row, col).
  void onTap(int row, int col) {
    if (!state.acceptsInput) return;
    final pos = Position(row, col);
    final game = state.game;
    final piece = game.board.at(pos);

    // Case 1: nothing selected yet → try to select.
    if (state.selected == null) {
      if (piece != null && piece.color == game.turn) {
        _select(pos);
      }
      return;
    }

    // Case 2: tapping the same square → deselect.
    if (state.selected == pos) {
      _clearSelection();
      return;
    }

    // Case 3: tapping another own piece → re-select.
    if (piece != null && piece.color == game.turn) {
      _select(pos);
      return;
    }

    // Case 4: tapping a valid move target → make the move.
    if (state.validTargets.contains(pos)) {
      _executeMove(state.selected!, pos);
      return;
    }

    // Otherwise the tap is meaningless — just clear selection.
    _clearSelection();
  }

  void _select(Position pos) {
    final targets = state.game.getValidMoves(pos);
    state = state.copyWith(selected: pos, validTargets: targets);
  }

  void _clearSelection() {
    state = state.copyWith(clearSelected: true, validTargets: const []);
  }

  void _executeMove(Position from, Position to) {
    final move = state.game.makeMove(from, to);
    state = state.copyWith(
      lastMove: move,
      clearSelected: true,
      validTargets: const [],
      clearHint: true,
    );
    // Bot turn is triggered by the screen via [requestBotMove] so the
    // controller stays free of timer/engine dependencies.
  }

  /// Undo the most recent move (and the bot's reply, if applicable).
  void undo() {
    final game = state.game;
    if (game.history.isEmpty) return;
    if (state.cpuThinking) return;
    game.undoMove();
    // In bot mode, also undo the human's last move so they get another try.
    if (state.isVsBot && game.history.isNotEmpty) {
      game.undoMove();
    }
    state = state.copyWith(
      lastMove: game.lastMove,
      clearLastMove: game.history.isEmpty,
      clearSelected: true,
      validTargets: const [],
      clearHint: true,
    );
  }

  void resign(PieceColor color) {
    state.game.resign(color);
    state = state.copyWith(clearSelected: true, validTargets: const []);
  }

  void agreeDraw() {
    state.game.agreeDraw();
    state = state.copyWith(clearSelected: true, validTargets: const []);
  }

  /// Apply a CPU-generated move (called by the screen after running the bot
  /// in an isolate / async future). Skipped if the game state moved on.
  void applyBotMove(Position from, Position to) {
    if (state.game.status.isOver) return;
    if (state.game.turn != state.cpuColor) return;
    if (!state.game.isValidMove(from, to)) return;
    final move = state.game.makeMove(from, to);
    state = state.copyWith(
      lastMove: move,
      cpuThinking: false,
      clearSelected: true,
      validTargets: const [],
      clearHint: true,
    );
  }

  void setBotThinking(bool value) {
    state = state.copyWith(cpuThinking: value);
  }

  void setHintThinking(bool value) {
    state = state.copyWith(hintThinking: value);
  }

  /// Show an engine-suggested move on the board. Rejects suggestions that are
  /// no longer legal (e.g. the position changed while the engine was
  /// thinking).
  void showHint(Position from, Position to) {
    final game = state.game;
    if (game is XiangqiCupGame) return;
    if (game.status.isOver) return;
    final piece = game.board.at(from);
    if (piece == null || piece.color != game.turn) return;
    if (!game.isValidMove(from, to)) return;
    state = state.copyWith(
      hintMove: Move(
        from: from,
        to: to,
        moved: piece,
        captured: game.board.at(to),
      ),
      hintThinking: false,
    );
  }

  void clearHint() {
    state = state.copyWith(clearHint: true, hintThinking: false);
  }
}

ChessGameSession _newSession(GameMode mode) {
  return (mode == GameMode.cupLocal || mode == GameMode.cupVsBot)
      ? XiangqiCupGame.initial()
      : XiangqiGame.initial();
}

/// Family-style provider so each game route gets its own controller.
final gameControllerProvider = StateNotifierProvider.autoDispose
    .family<GameController, GameUiState, GameControllerArgs>((ref, args) {
      return GameController(
        mode: args.mode,
        cpuColor: args.cpuColor,
        botDifficulty: args.botDifficulty,
      );
    });
