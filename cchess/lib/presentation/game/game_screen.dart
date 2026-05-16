import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/chess/chess_board.dart';
import '../../widgets/common/common.dart';
import 'game_controller.dart';
import 'widgets/game_action_bar.dart';
import 'widgets/game_result_overlay.dart';
import 'widgets/player_info_panel.dart';

class GameScreen extends ConsumerStatefulWidget {
  /// Mode flag accepted from the router (`local` / `bot`).
  final String mode;
  final BotDifficulty? botDifficulty;

  /// Color the bot plays. Defaults to Black so the human starts.
  final PieceColor cpuColor;

  const GameScreen({
    super.key,
    this.mode = 'local',
    this.botDifficulty,
    this.cpuColor = PieceColor.black,
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  static const Duration _gameClock = Duration(minutes: 15);

  late Duration _redTime;
  late Duration _blackTime;
  Timer? _ticker;
  DateTime? _gameStartedAt;
  bool _soundOn = true;
  final BotEngine _botEngine = BotEngine();
  late final GameControllerArgs _args;

  @override
  void initState() {
    super.initState();
    final mode = widget.mode == 'bot' ? GameMode.vsBot : GameMode.localTwoPlayer;
    _args = GameControllerArgs(
      mode: mode,
      cpuColor: mode == GameMode.vsBot ? widget.cpuColor : null,
      botDifficulty:
          mode == GameMode.vsBot ? (widget.botDifficulty ?? BotDifficulty.medium) : null,
    );
    _redTime = _gameClock;
    _blackTime = _gameClock;
    _gameStartedAt = DateTime.now();
    _startTicker();

    // If the bot plays first (cpuColor == red), kick off its first move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePlayBotMove();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  GameController get _controller =>
      ref.read(gameControllerProvider(_args).notifier);

  GameUiState get _state => ref.read(gameControllerProvider(_args));

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final state = _state;
      if (state.game.status.isOver) {
        _ticker?.cancel();
        return;
      }
      if (state.game.history.isEmpty) return;
      setState(() {
        if (state.turn == PieceColor.red) {
          _redTime -= const Duration(seconds: 1);
          if (_redTime.isNegative) {
            _redTime = Duration.zero;
            _controller.resign(PieceColor.red);
            _ticker?.cancel();
          }
        } else {
          _blackTime -= const Duration(seconds: 1);
          if (_blackTime.isNegative) {
            _blackTime = Duration.zero;
            _controller.resign(PieceColor.black);
            _ticker?.cancel();
          }
        }
      });
    });
  }

  Future<void> _maybePlayBotMove() async {
    final state = _state;
    if (state.mode != GameMode.vsBot) return;
    if (state.game.status.isOver) return;
    if (state.cpuThinking) return;
    if (state.turn != state.cpuColor) return;

    _controller.setBotThinking(true);
    final difficulty = state.botDifficulty ?? BotDifficulty.medium;
    final move = await _botEngine.chooseMove(state.game, difficulty);
    if (!mounted) return;
    if (move == null) {
      _controller.setBotThinking(false);
      return;
    }
    // The game might have been reset / undone while the bot was thinking.
    final current = _state;
    if (current.game.turn != state.cpuColor) {
      _controller.setBotThinking(false);
      return;
    }
    _controller.applyBotMove(move.from, move.to);
  }

  void _onUserTap(int row, int col) {
    _controller.onTap(row, col);
    // Schedule potential bot reply after this frame so the human's move
    // animates first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePlayBotMove();
    });
  }

  void _onNewGame() {
    setState(() {
      _redTime = _gameClock;
      _blackTime = _gameClock;
      _gameStartedAt = DateTime.now();
    });
    _controller.newGame();
    _startTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePlayBotMove();
    });
  }

  void _onLeave() async {
    final confirmed = await CChessDialog.confirm(
      context,
      title: 'Rời ván đấu?',
      message: 'Bạn sẽ bị tính thua nếu rời ván.',
      confirmLabel: 'Rời ván',
      cancelLabel: 'Ở lại',
      icon: Icons.warning_amber,
    );
    if (!mounted) return;
    if (confirmed) context.go(AppConstants.routeHome);
  }

  void _onResign() async {
    final state = _state;
    if (state.game.status.isOver) return;
    final confirmed = await CChessDialog.confirm(
      context,
      title: 'Xin thua?',
      message: 'Đối thủ sẽ giành chiến thắng.',
      confirmLabel: 'Xin thua',
      icon: Icons.flag,
    );
    if (!confirmed) return;
    final loser = state.mode == GameMode.vsBot
        ? (state.cpuColor == PieceColor.red
            ? PieceColor.black
            : PieceColor.red)
        : state.turn;
    _controller.resign(loser);
  }

  void _onDraw() async {
    final state = _state;
    if (state.mode == GameMode.localTwoPlayer) {
      final confirmed = await CChessDialog.confirm(
        context,
        title: 'Đồng ý hòa?',
        message: 'Hai bên đồng ý xử hòa ván cờ.',
        confirmLabel: 'Đồng ý',
        icon: Icons.handshake_outlined,
      );
      if (!confirmed) return;
      _controller.agreeDraw();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bot không chấp nhận cầu hòa. Hãy cố gắng thắng!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameControllerProvider(_args));
    final game = state.game;

    final checkedKing = game.isInCheck(game.turn)
        ? game.board.generalPosition(game.turn)
        : null;

    final captured = _countCaptures(game.history);

    final humanColor = state.mode == GameMode.vsBot
        ? (state.cpuColor == PieceColor.red ? PieceColor.black : PieceColor.red)
        : null;

    final opponentLabel = state.mode == GameMode.vsBot
        ? 'Bot ${(state.botDifficulty ?? BotDifficulty.medium).nameVi}'
        : 'Người Chơi 2';
    final opponentElo =
        state.botDifficulty?.estimatedElo ?? 1500;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: Text(
          state.mode == GameMode.vsBot ? 'Đấu với Bot AI' : 'Đấu cờ',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onLeave,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_android_outlined),
            onPressed: _controller.toggleFlip,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                children: [
                  PlayerInfoPanel(
                    displayName: opponentLabel,
                    elo: opponentElo,
                    color: state.boardFlipped
                        ? PieceColor.red
                        : PieceColor.black,
                    isMyTurn: state.turn ==
                        (state.boardFlipped
                            ? PieceColor.red
                            : PieceColor.black),
                    timeLeft: state.boardFlipped ? _redTime : _blackTime,
                    capturedCount: state.boardFlipped
                        ? captured.byBlack
                        : captured.byRed,
                    topAlign: true,
                  ),
                  AppSpacing.vGapSm,
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 9 / 10,
                      child: ChessBoard(
                        board: game.board,
                        selected: state.selected,
                        validTargets: state.validTargets,
                        lastMove: state.lastMove,
                        checkedKing: checkedKing,
                        flipped: state.boardFlipped,
                        onTap: _onUserTap,
                      ),
                    ),
                  ),
                  AppSpacing.vGapSm,
                  PlayerInfoPanel(
                    displayName: 'Bạn',
                    elo: 1820,
                    color: state.boardFlipped
                        ? PieceColor.black
                        : PieceColor.red,
                    isMyTurn: state.turn ==
                        (state.boardFlipped
                            ? PieceColor.black
                            : PieceColor.red),
                    timeLeft: state.boardFlipped ? _blackTime : _redTime,
                    capturedCount: state.boardFlipped
                        ? captured.byRed
                        : captured.byBlack,
                  ),
                  AppSpacing.vGapSm,
                  GameActionBar(
                    canUndo: game.history.isNotEmpty && !state.cpuThinking,
                    soundOn: _soundOn,
                    onLeave: _onLeave,
                    onUndo: _controller.undo,
                    onDraw: _onDraw,
                    onResign: _onResign,
                    onToggleSound: () =>
                        setState(() => _soundOn = !_soundOn),
                    onFlip: _controller.toggleFlip,
                  ),
                ],
              ),
            ),
            if (state.cpuThinking)
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.charcoalDark.withValues(alpha: 0.92),
                      borderRadius: AppRadius.chip,
                      border: Border.all(color: AppColors.accentGold),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: BrushStrokeSpinner(size: 14),
                        ),
                        SizedBox(width: 8),
                        Text('Bot đang suy nghĩ…'),
                      ],
                    ),
                  ),
                ),
              ),
            if (game.status.isOver)
              GameResultOverlay(
                status: game.status,
                reason: game.endReason,
                humanColor: humanColor,
                duration: _gameStartedAt == null
                    ? Duration.zero
                    : DateTime.now().difference(_gameStartedAt!),
                onPlayAgain: _onNewGame,
                onClose: () => context.go(AppConstants.routeHome),
              ),
          ],
        ),
      ),
    );
  }

  _CaptureCount _countCaptures(List<Move> history) {
    int byRed = 0;
    int byBlack = 0;
    for (final m in history) {
      if (m.captured == null) continue;
      if (m.moved.color == PieceColor.red) {
        byRed++;
      } else {
        byBlack++;
      }
    }
    return _CaptureCount(byRed: byRed, byBlack: byBlack);
  }
}

class _CaptureCount {
  final int byRed;
  final int byBlack;
  const _CaptureCount({required this.byRed, required this.byBlack});
}
