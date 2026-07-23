import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/elo_constants.dart';
import '../../core/matchmaking/bot_matchmaker.dart';
import '../../core/matchmaking/elo_scoring.dart';
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

  /// ELO-ladder standard play: the matched bot's hidden ELO and the bracket it
  /// landed in (used for asymmetric scoring + the end-of-game reveal). Null for
  /// Cờ Úp and legacy difficulty-tier games.
  final int? botElo;
  final EloBracket? bracket;

  /// Color the bot plays. Defaults to Black so the human starts.
  final PieceColor cpuColor;

  const GameScreen({
    super.key,
    this.mode = 'local',
    this.botDifficulty,
    this.engineLevel,
    this.botElo,
    this.bracket,
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
  // Countdown for the current side to move; reset each move to
  // min(90s, that side's remaining total) — see [_moveClockFor].
  late Duration _moveTime;
  // Move count already reflected in [_moveTime]. The game session is a single
  // MUTABLE instance, so prev/next GameUiState share the same `game` object —
  // we can't detect a new move by comparing prev.game vs next.game, so we
  // track the count here and reset the per-move clock when it changes.
  int _lastMoveCount = 0;
  Timer? _ticker;
  DateTime? _gameStartedAt;
  bool _soundOn = true;
  late final GameControllerArgs _args;
  bool _resultPersisted = false;
  final CupBotEngine _cupBot = CupBotEngine();

  @override
  void initState() {
    super.initState();
    final mode = switch (widget.mode) {
      'bot' => GameMode.vsBot,
      'cup' => GameMode.cupLocal,
      'cupbot' => GameMode.cupVsBot,
      _ => GameMode.localTwoPlayer,
    };
    final isBot = mode == GameMode.vsBot || mode == GameMode.cupVsBot;
    _args = GameControllerArgs(
      mode: mode,
      cpuColor: isBot ? widget.cpuColor : null,
      botDifficulty: isBot
          ? (widget.botDifficulty ?? BotDifficulty.medium)
          : null,
      botElo: widget.botElo,
    );
    _redTime = _gameClock;
    _blackTime = _gameClock;
    _moveTime = _moveClockFor(PieceColor.red);
    _lastMoveCount = 0;
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

  /// ELO-ladder standard bot game (a botElo was matched). Cờ Úp and legacy
  /// difficulty-tier games are not matchmaking and keep eloDelta 0.
  bool get _isStandardMatchmaking =>
      widget.mode == 'bot' && widget.botElo != null;

  /// Remaining total-game time for [color].
  Duration _totalTimeFor(PieceColor color) =>
      color == PieceColor.red ? _redTime : _blackTime;

  /// Per-move clock value at the start of [color]'s turn: a fresh 90s, but
  /// never more than that side's remaining total (e.g. total 70s → 70s).
  Duration _moveClockFor(PieceColor color) {
    final total = _totalTimeFor(color);
    return total < _moveClock ? total : _moveClock;
  }

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

        // Per-move clock — applies to BOTH sides, including the bot, so the
        // chip counts down on every turn. Expiry = the side to move loses,
        // like online. Re-check status: the total clock above may have just
        // ended the game.
        if (!_state.game.status.isOver) {
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
    if (!state.isVsBot) return;
    if (state.game.status.isOver) return;
    if (state.cpuThinking) return;
    if (state.turn != state.cpuColor) return;

    _controller.setBotThinking(true);
    final difficulty = state.botDifficulty ?? BotDifficulty.medium;
    final game = state.game;

    Position? from;
    Position? to;
    if (game is XiangqiCupGame) {
      // Cờ Úp can't use Pikafish / the standard minimax (hidden identities) —
      // run the cup-aware bot, which sees only covers + revealed pieces.
      final move = await _cupBot.chooseMove(game, difficulty);
      if (move != null) {
        from = move.from;
        to = move.to;
      }
    } else {
      final engine = ref.read(engineRouterProvider);
      // ELO ladder: derive the strength config from the matched bot ELO. Legacy
      // difficulty-tier games (config == null) keep the level-based behaviour.
      final config = _isStandardMatchmaking
          ? configForElo(widget.botElo!)
          : null;
      final result = await engine.bestMove(
        game.toFen(),
        level: config != null
            ? _engineLevelForElo(widget.botElo!)
            : (widget.engineLevel ?? _engineLevelForDifficulty(difficulty)),
        useCase: EngineUseCase.bot,
        config: config,
      );
      if (result != null) {
        from = result.move.from;
        to = result.move.to;
      }
    }
    if (!mounted) return;
    if (from == null || to == null) {
      _controller.setBotThinking(false);
      return;
    }
    // The game might have been reset / undone while the bot was thinking.
    final current = _state;
    if (current.game.turn != state.cpuColor) {
      _controller.setBotThinking(false);
      return;
    }
    _controller.applyBotMove(from, to);
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
      final quotaHit = result.fallbackKind == EngineFallbackKind.quotaExceeded;
      // Offline Pikafish keeps full strength — no need to warn about quality,
      // only about the quota when that's what triggered the fallback.
      final viaPikafish = result.source == EngineSource.localPikafish;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            quotaHit
                ? (viaPikafish
                      ? 'Đã hết lượt gợi ý server hôm nay — đang dùng Pikafish '
                            'Offline trên máy bạn.'
                      : 'Đã hết lượt gợi ý AI miễn phí hôm nay — đang dùng gợi ý '
                            'cơ bản. Nâng cấp VIP để gợi ý Đại Sư không giới hạn.')
                : (viaPikafish
                      ? 'Gợi ý bằng Pikafish Offline — máy chủ chưa sẵn sàng.'
                      : 'Gợi ý offline (minimax) — máy chủ chưa sẵn sàng.'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      // Refresh the cached quota snapshot so any quota UI reflects the spend.
      ref.invalidate(engineQuotaProvider);
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
      _moveTime = _moveClockFor(PieceColor.red);
      _lastMoveCount = 0;
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

    final humanColor = state.isVsBot
        ? (state.cpuColor == PieceColor.red ? PieceColor.black : PieceColor.red)
        : null;
    final won =
        humanColor != null &&
        ((game.status == GameStatus.redWin && humanColor == PieceColor.red) ||
            (game.status == GameStatus.blackWin &&
                humanColor == PieceColor.black));
    final drew = game.status == GameStatus.draw;

    // ELO-ladder reward (0 for local / Cờ Úp / legacy games).
    final delta = _eloDeltaFor(humanColor, game.status);

    // 1. Save a kỳ phổ record. The bot ELO is only revealed post-game.
    final repo = ref.read(gameHistoryRepositoryProvider);
    final opponentLabel = _isStandardMatchmaking
        ? 'Bot ELO ${widget.botElo}'
        : state.isVsBot
        ? _botOpponentLabel(state.botDifficulty ?? BotDifficulty.medium)
        : 'Người Chơi 2';
    final duration = _gameStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_gameStartedAt!);
    // Cờ Úp: persist the shuffled deal + per-move reveal log so the replay
    // screen can reconstruct the exact game (P3, doc 14 §4.3).
    final cupGame = game is XiangqiCupGame ? game : null;
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
        eloDelta: delta,
        duration: duration,
        endedAt: DateTime.now(),
        cupHiddenFen: cupGame == null
            ? null
            : CupRecordCodec.encodeHiddenMap(cupGame.initialHiddenAssignments),
        cupReveals: cupGame == null
            ? null
            : CupRecordCodec.deriveReveals(
                cupGame.initialHiddenAssignments,
                cupGame.history,
              ),
      ),
    );

    // 2. Apply to the practice/bot pool (never ranked — ranked stats are
    // server-authoritative). Standard matchmaking moves eloBot; local / Cờ Úp
    // / legacy bot games keep eloBot unchanged (delta == 0) but still count.
    if (humanColor != null || state.isLocalHotseat) {
      if (humanColor != null) {
        await ref
            .read(profileControllerProvider.notifier)
            .applyGameResult(eloDelta: delta, won: won, drew: drew);
      } else {
        // Local 2-player: bump the offline game count only (no win/loss credit).
        await ref
            .read(profileControllerProvider.notifier)
            .update(
              (p) => p.copyWith(
                botGames: p.botGames + 1,
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

    // Achievements count ranked + bot play together so offline players still
    // progress; ELO milestones use whichever pool is higher.
    final totalGames = profile.totalGames + profile.botGames;
    final totalWins = profile.wins + profile.botWins;
    final stats = AchievementStats(
      totalGames: totalGames,
      wins: totalWins,
      // Win streak not tracked yet — derive a crude approximation from
      // total wins / games ratio. Refine in Sprint 10.
      winStreak: totalWins > 0 ? 1 : 0,
      eloChess: profile.eloChess > profile.eloBot
          ? profile.eloChess
          : profile.eloBot,
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
    // Finished game → nothing at stake, leave without the scary confirm.
    if (_state.game.status.isOver) {
      _exitGame();
      return;
    }

    final state = _state;
    // Bot game with moves on the board: leaving counts as a resignation, so
    // the warning is real and quitting is not an ELO-dodge. A bot game with no
    // moves yet, or a local/hotseat game, has nothing at stake — be honest.
    final leavingResigns = state.isVsBot && state.game.history.isNotEmpty;
    final confirmed = await CChessDialog.confirm(
      context,
      title: 'Rời ván đấu?',
      message: leavingResigns
          ? 'Rời ván bây giờ sẽ bị tính là xin thua.'
          : 'Ván đang chơi sẽ không được lưu.',
      confirmLabel: 'Rời ván',
      cancelLabel: 'Ở lại',
      icon: Icons.warning_amber,
    );
    if (!mounted || !confirmed) return;
    if (leavingResigns) {
      final loser = state.cpuColor == PieceColor.red
          ? PieceColor.black
          : PieceColor.red;
      _controller.resign(loser);
      // Persist before navigating — the build-listener that normally saves the
      // result dies with this screen.
      await _persistGameResult();
      if (!mounted) return;
    }
    _exitGame();
  }

  /// Leave the game route: pop back to where it was pushed from (Home tab,
  /// Đối Đầu tab or bot select), or Home when the game is the stack root.
  void _exitGame() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppConstants.routeHome);
    }
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
    final loser = state.isVsBot
        ? (state.cpuColor == PieceColor.red ? PieceColor.black : PieceColor.red)
        : state.turn;
    _controller.resign(loser);
  }

  void _onDraw() async {
    final state = _state;
    if (state.isLocalHotseat) {
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
      // played by either side, undone, or the board reset). NOTE: prev.game and
      // next.game alias the SAME mutable session, so comparing prev.game vs
      // next.game would never differ and the clock would never reset — we
      // compare against our own tracked count instead. The reset value is
      // min(90s, the new side-to-move's remaining total).
      final moveCount = next.game.history.length;
      if (moveCount != _lastMoveCount) {
        _lastMoveCount = moveCount;
        setState(() => _moveTime = _moveClockFor(next.turn));
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

    final humanColor = state.isVsBot
        ? (state.cpuColor == PieceColor.red ? PieceColor.black : PieceColor.red)
        : null;

    // Matchmade bots show only "Bot" with their ELO hidden until the result.
    final opponentLabel = _isStandardMatchmaking
        ? 'Bot'
        : state.isVsBot
        ? _botOpponentLabel(state.botDifficulty ?? BotDifficulty.medium)
        : 'Người Chơi 2';
    final opponentElo = state.botDifficulty?.estimatedElo ?? 1500;
    // Only bot opponents have a meaningful ELO to show ("Người Chơi 2" was
    // getting a made-up 1500); matchmade bots stay hidden until the reveal.
    final showOpponentElo = state.isVsBot && !_isStandardMatchmaking;
    // Bot matches show the player's bot-pool ELO (the ladder they're climbing).
    final profile = ref.watch(profileControllerProvider).valueOrNull;
    final playerElo =
        (_isStandardMatchmaking ? profile?.eloBot : profile?.eloChess) ??
        EloConstants.initialElo;

    // PopScope routes the SYSTEM back gesture through the same leave logic as
    // the in-app back arrow. Without it the pop falls through to the OS (this
    // route is the whole stack), backgrounding the app mid-game and losing the
    // board on relaunch.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onLeave();
      },
      child: Scaffold(
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
                      showElo: showOpponentElo,
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
                      // Hotseat: the bottom seat is just "player 1" — no fake
                      // personal ELO on a shared-device game.
                      displayName: state.isVsBot ? 'Bạn' : 'Người Chơi 1',
                      elo: playerElo,
                      showElo: state.isVsBot,
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
                      // No take-backs in ELO-rated matchmaking games; practice
                      // modes (local / Cờ Úp / legacy tiers) keep undo.
                      canUndo:
                          game.history.isNotEmpty &&
                          !state.cpuThinking &&
                          !_isStandardMatchmaking,
                      canHint: state.acceptsInput && !state.isCup,
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
                  eloDelta: _eloDeltaFor(humanColor, game.status),
                  botElo: _isStandardMatchmaking ? widget.botElo : null,
                  bracket: widget.bracket,
                  duration: _gameStartedAt == null
                      ? Duration.zero
                      : DateTime.now().difference(_gameStartedAt!),
                  onPlayAgain: _onNewGame,
                  onClose: () => context.go(AppConstants.routeHome),
                ),
            ],
          ),
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

  /// ELO delta for a finished standard-matchmaking game; 0 otherwise (local /
  /// Cờ Úp / legacy). Pure — safe to call from both build() and persist.
  int _eloDeltaFor(PieceColor? humanColor, GameStatus status) {
    final bracket = widget.bracket;
    if (!_isStandardMatchmaking || bracket == null || humanColor == null) {
      return 0;
    }
    final won =
        (status == GameStatus.redWin && humanColor == PieceColor.red) ||
        (status == GameStatus.blackWin && humanColor == PieceColor.black);
    final drew = status == GameStatus.draw;
    return eloDelta(bracket: bracket, won: won, drew: drew);
  }

  /// Coarse ELO → [EngineLevel] map. Only affects cosmetic minimum think time
  /// and the minimax fallback difficulty; the real strength comes from
  /// [configForElo].
  EngineLevel _engineLevelForElo(int elo) {
    if (elo < 1300) return EngineLevel.veryEasy;
    if (elo < 1500) return EngineLevel.easy;
    if (elo < 1700) return EngineLevel.medium;
    if (elo < 2000) return EngineLevel.hard;
    if (elo < 2400) return EngineLevel.veryHard;
    return EngineLevel.grandmaster;
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
      case GameMode.cupVsBot:
        return 'Cờ Úp với Máy';
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
