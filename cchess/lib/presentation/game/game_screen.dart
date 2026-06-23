import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/achievement.dart';
import '../../data/models/game_record.dart';
import '../../data/repositories/achievement_repository.dart';
import '../../data/repositories/daily_quest_repository.dart';
import '../../data/repositories/game_history_repository.dart';
import '../../data/repositories/puzzle_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/chess/chess_board.dart';
import '../../widgets/common/common.dart';
import '../profile/profile_controller.dart';
import 'game_controller.dart';
import 'widgets/game_action_bar.dart';
import 'widgets/game_result_overlay.dart';
import 'widgets/player_info_panel.dart';

class GameScreen extends ConsumerStatefulWidget {
  /// Mode flag accepted from the router (`local` / `bot`).
  final String mode;
  final BotDifficulty? botDifficulty;
  final EngineLevel? engineLevel;

  /// Color the bot plays. Defaults to Black so the human starts.
  final PieceColor cpuColor;

  const GameScreen({
    super.key,
    this.mode = 'local',
    this.botDifficulty,
    this.engineLevel,
    this.cpuColor = PieceColor.black,
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  static const Duration _gameClock = Duration(minutes: 15);
  // Per-move limit (90s), matching online's onlineDefaultMoveClockMs.
  static const Duration _moveClock = Duration(seconds: 90);

  late Duration _redTime;
  late Duration _blackTime;
  // Countdown for the current side to move; reset to _moveClock each move.
  late Duration _moveTime;
  Timer? _ticker;
  DateTime? _gameStartedAt;
  bool _soundOn = true;
  late final GameControllerArgs _args;
  bool _resultPersisted = false;

  @override
  void initState() {
    super.initState();
    final mode = switch (widget.mode) {
      'bot' => GameMode.vsBot,
      'cup' => GameMode.cupLocal,
      _ => GameMode.localTwoPlayer,
    };
    _args = GameControllerArgs(
      mode: mode,
      cpuColor: mode == GameMode.vsBot ? widget.cpuColor : null,
      botDifficulty: mode == GameMode.vsBot
          ? (widget.botDifficulty ?? BotDifficulty.medium)
          : null,
    );
    _redTime = _gameClock;
    _blackTime = _gameClock;
    _moveTime = _moveClock;
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

        // Per-move clock (90s). Skip the bot's turn so engine latency never
        // costs it the game; expiry = the side to move loses, like online.
        // Re-check status: the total clock above may have just ended the game.
        final isCpuTurn =
            state.mode == GameMode.vsBot && state.turn == state.cpuColor;
        if (!isCpuTurn && !_state.game.status.isOver) {
          _moveTime -= const Duration(seconds: 1);
          if (_moveTime.isNegative) {
            _moveTime = Duration.zero;
            _controller.resign(state.turn);
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
    final engine = ref.read(engineRouterProvider);
    final result = await engine.bestMove(
      state.game.toFen(),
      level: widget.engineLevel ?? _engineLevelForDifficulty(difficulty),
      useCase: EngineUseCase.bot,
    );
    if (!mounted) return;
    if (result == null) {
      _controller.setBotThinking(false);
      return;
    }
    // The game might have been reset / undone while the bot was thinking.
    final current = _state;
    if (current.game.turn != state.cpuColor) {
      _controller.setBotThinking(false);
      return;
    }
    _controller.applyBotMove(result.move.from, result.move.to);
  }

  /// Ask the engine router for a hint (remote Pikafish when online, local
  /// minimax fallback) and surface it on the board.
  Future<void> _onHint() async {
    final state = _state;
    if (state.mode == GameMode.cupLocal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gợi ý AI chưa hỗ trợ Cờ Úp.')),
      );
      return;
    }
    if (!state.acceptsInput || state.hintThinking) return;
    final turnAtRequest = state.turn;
    _controller.setHintThinking(true);
    EngineMove? result;
    try {
      final engine = ref.read(engineRouterProvider);
      result = await engine.bestMove(
        state.game.toFen(),
        level: EngineLevel.grandmaster,
        useCase: EngineUseCase.hint,
      );
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    // Position may have changed while the engine was thinking.
    final current = _state;
    if (current.game.status.isOver || current.turn != turnAtRequest) {
      _controller.clearHint();
      return;
    }
    if (result == null) {
      _controller.clearHint();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm được gợi ý lúc này.')),
      );
      return;
    }
    _controller.showHint(result.move.from, result.move.to);
    if (result.usedFallback) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gợi ý offline (minimax) — máy chủ chưa sẵn sàng.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
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
      _moveTime = _moveClock;
      _gameStartedAt = DateTime.now();
      _resultPersisted = false;
    });
    _controller.newGame();
    _startTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePlayBotMove();
    });
  }

  /// When the game ends, persist a [GameRecord], update profile stats,
  /// bump daily quest counters, and check for newly unlocked achievements.
  Future<void> _persistGameResult() async {
    if (_resultPersisted) return;
    _resultPersisted = true;
    final state = _state;
    final game = state.game;
    if (!game.status.isOver) return;

    final humanColor = state.mode == GameMode.vsBot
        ? (state.cpuColor == PieceColor.red ? PieceColor.black : PieceColor.red)
        : null;
    final won =
        humanColor != null &&
        ((game.status == GameStatus.redWin && humanColor == PieceColor.red) ||
            (game.status == GameStatus.blackWin &&
                humanColor == PieceColor.black));
    final drew = game.status == GameStatus.draw;

    // 1. Save a kỳ phổ record.
    final repo = ref.read(gameHistoryRepositoryProvider);
    final opponentLabel = state.mode == GameMode.vsBot
        ? _botOpponentLabel(state.botDifficulty ?? BotDifficulty.medium)
        : 'Người Chơi 2';
    final duration = _gameStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_gameStartedAt!);
    await repo.save(
      GameRecord(
        id: '',
        opponentLabel: opponentLabel,
        mode: state.mode,
        humanColor: humanColor,
        startingFen: kInitialFen,
        moves: game.history.map((m) => m.toUci()).toList(),
        result: game.status,
        endReason: game.endReason,
        eloDelta: 0,
        duration: duration,
        endedAt: DateTime.now(),
      ),
    );

    // 2. Apply to profile stats (no ELO change for local / bot games yet).
    if (humanColor != null ||
        state.mode == GameMode.localTwoPlayer ||
        state.mode == GameMode.cupLocal) {
      // For local 2-player we still bump totalGames but no win/loss credit.
      if (humanColor != null) {
        await ref
            .read(profileControllerProvider.notifier)
            .applyGameResult(eloDelta: 0, won: won, drew: drew);
      } else {
        await ref
            .read(profileControllerProvider.notifier)
            .update(
              (p) => p.copyWith(
                totalGames: p.totalGames + 1,
                lastActiveAt: DateTime.now(),
              ),
            );
      }
    }

    // 3. Bump today's quest progress.
    if (humanColor != null) {
      await ref
          .read(dailyQuestControllerProvider.notifier)
          .recordGamePlayed(won: won);
    } else {
      await ref
          .read(dailyQuestControllerProvider.notifier)
          .recordGamePlayed(won: false);
    }

    // 4. Check achievements & toast each newly-unlocked one.
    await _checkAchievements();
  }

  Future<void> _checkAchievements() async {
    final profile = ref.read(profileControllerProvider).valueOrNull;
    if (profile == null) return;
    final achRepo = ref.read(achievementRepositoryProvider);
    final puzzleRepo = ref.read(puzzleRepositoryProvider);
    final allPuzzleProgress = await puzzleRepo.getAllProgress();
    final puzzlesSolved = allPuzzleProgress.values
        .where((p) => p.solved)
        .length;

    final stats = AchievementStats(
      totalGames: profile.totalGames,
      wins: profile.wins,
      // Win streak not tracked yet — derive a crude approximation from
      // total wins / games ratio. Refine in Sprint 10.
      winStreak: profile.wins > 0 ? 1 : 0,
      eloChess: profile.eloChess,
      puzzlesSolved: puzzlesSolved,
      loginStreak: 1,
    );

    final progress = await achRepo.getAllProgress();
    final unlocked = AchievementEngine.newlyUnlocked(
      stats: stats,
      currentProgress: progress,
    );
    for (final a in unlocked) {
      await achRepo.markUnlocked(a.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accentGold.withValues(alpha: 0.95),
            content: Row(
              children: [
                Icon(a.icon, color: AppColors.inkBlack, size: 22),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    'Huy chương mới: ${a.nameVi}',
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.inkBlack,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
        ? (state.cpuColor == PieceColor.red ? PieceColor.black : PieceColor.red)
        : state.turn;
    _controller.resign(loser);
  }

  void _onDraw() async {
    final state = _state;
    if (state.mode == GameMode.localTwoPlayer ||
        state.mode == GameMode.cupLocal) {
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
    // Persist exactly once when the game transitions to a finished status.
    ref.listen<GameUiState>(gameControllerProvider(_args), (prev, next) {
      if (next.game.status.isOver && !_resultPersisted) {
        _persistGameResult();
      }
      // Reset the per-move clock whenever the move count changes (a move was
      // played by either side, undone, or the board reset) so each turn starts
      // fresh at 90s.
      if (prev?.game.history.length != next.game.history.length) {
        setState(() => _moveTime = _moveClock);
      }
    });

    final state = ref.watch(gameControllerProvider(_args));
    final game = state.game;

    final checkedKing = game.isInCheck(game.turn)
        ? game.board.generalPosition(game.turn)
        : null;

    final captured = _countCaptures(game.history);
    final hiddenPositions = game is XiangqiCupGame
        ? game.hiddenPositions
        : const <Position>{};

    final humanColor = state.mode == GameMode.vsBot
        ? (state.cpuColor == PieceColor.red ? PieceColor.black : PieceColor.red)
        : null;

    final opponentLabel = state.mode == GameMode.vsBot
        ? _botOpponentLabel(state.botDifficulty ?? BotDifficulty.medium)
        : 'Người Chơi 2';
    final opponentElo = state.botDifficulty?.estimatedElo ?? 1500;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: Text(_titleForMode(state.mode)),
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
                    isMyTurn:
                        state.turn ==
                        (state.boardFlipped
                            ? PieceColor.red
                            : PieceColor.black),
                    timeLeft: state.boardFlipped ? _redTime : _blackTime,
                    moveTimeLeft: _moveTime,
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
                        hintMove: state.hintMove,
                        checkedKing: checkedKing,
                        hiddenPositions: hiddenPositions,
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
                    isMyTurn:
                        state.turn ==
                        (state.boardFlipped
                            ? PieceColor.black
                            : PieceColor.red),
                    timeLeft: state.boardFlipped ? _blackTime : _redTime,
                    moveTimeLeft: _moveTime,
                    capturedCount: state.boardFlipped
                        ? captured.byRed
                        : captured.byBlack,
                  ),
                  AppSpacing.vGapSm,
                  GameActionBar(
                    canUndo: game.history.isNotEmpty && !state.cpuThinking,
                    canHint:
                        state.acceptsInput && state.mode != GameMode.cupLocal,
                    hintThinking: state.hintThinking,
                    soundOn: _soundOn,
                    onLeave: _onLeave,
                    onUndo: _controller.undo,
                    onHint: _onHint,
                    onDraw: _onDraw,
                    onResign: _onResign,
                    onToggleSound: () => setState(() => _soundOn = !_soundOn),
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

  EngineLevel _engineLevelForDifficulty(BotDifficulty difficulty) {
    switch (difficulty) {
      case BotDifficulty.veryEasy:
        return EngineLevel.veryEasy;
      case BotDifficulty.easy:
        return EngineLevel.easy;
      case BotDifficulty.medium:
        return EngineLevel.medium;
      case BotDifficulty.hard:
        return EngineLevel.hard;
      case BotDifficulty.veryHard:
        return EngineLevel.veryHard;
    }
  }

  String _botOpponentLabel(BotDifficulty difficulty) {
    if (widget.engineLevel == EngineLevel.grandmaster) {
      return 'Pikafish Đại Sư+';
    }
    return 'Bot ${difficulty.nameVi}';
  }

  String _titleForMode(GameMode mode) {
    switch (mode) {
      case GameMode.vsBot:
        return 'Đấu với Bot AI';
      case GameMode.cupLocal:
        return 'Cờ Úp';
      case GameMode.onlineCasual:
        return 'Đấu casual';
      case GameMode.localTwoPlayer:
      case GameMode.vsOnline:
        return 'Đấu cờ';
    }
  }
}

class _CaptureCount {
  final int byRed;
  final int byBlack;
  const _CaptureCount({required this.byRed, required this.byBlack});
}
