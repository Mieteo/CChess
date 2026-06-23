import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../data/services/cloud_sync_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/chess/chess_board.dart';
import '../../widgets/common/common.dart';
import '../profile/profile_controller.dart';
import 'online_game_widgets.dart';
import 'online_match_controller.dart';
import 'online_result_format.dart';
import 'share_room_sheet.dart';

/// Quick-chat presets (A5). Sent as plain `chat-message` text — the server's
/// 120-char cap and rate limit apply unchanged.
const List<String> _quickChatPresets = [
  'Chào bạn! 👋',
  'Chúc may mắn 🍀',
  'Nước hay đấy! 🔥',
  'Suýt nữa thì… 😅',
  'Đánh hay lắm 👏',
  'Hẹn gặp lại 🤝',
];

class OnlineGameScreen extends ConsumerStatefulWidget {
  const OnlineGameScreen({super.key});

  @override
  ConsumerState<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends ConsumerState<OnlineGameScreen>
    with WidgetsBindingObserver {
  Position? _selected;
  List<Position> _validTargets = const [];
  Timer? _countdownTimer;
  final _chatCtrl = TextEditingController();
  bool _resultDialogOpen = false;
  // D1 fix: reconnect the instant the OS reports the network is back.
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  OnlineMatchController get _ctrl =>
      ref.read(onlineMatchControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // D1 fix: flag the screen as open so the lobby doesn't push a second copy
    // when a mid-game reconnect transitions the phase back to `playing`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(onlineGameOpenProvider.notifier).state = true;
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) _ctrl.onNetworkAvailable();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    ref.read(onlineGameOpenProvider.notifier).state = false;
    _countdownTimer?.cancel();
    _chatCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _ensureCountdown(bool needed) {
    if (needed && _countdownTimer == null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {}); // trigger rebuild to update display
      });
    } else if (!needed && _countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
    }
  }

  /// Seconds remaining in peer-disconnect grace, or null if not in that phase.
  int? _remainingGraceSec(OnlineMatchState s) =>
      onlineRemainingGraceSec(s, DateTime.now().millisecondsSinceEpoch);

  int _moveClockMs(OnlineMatchState s) {
    final updatedAt = s.moveClockUpdatedAtMs;
    if (updatedAt == null) return s.moveClockRemainingMs;
    final elapsed = DateTime.now().millisecondsSinceEpoch - updatedAt;
    final remaining = s.moveClockRemainingMs - elapsed;
    return remaining <= 0 ? 0 : remaining;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifeState) {
    // Chỉ tiến hành disconnect khi `detached` (app sắp bị OS hủy hẳn — vd
    // swipe-up kill). `paused`/`hidden` (home/menu button) giữ kết nối để user
    // quay lại trong vài giây mà không bị mất game.
    //
    // Step 8: dùng `disconnectKeepingReconnectState()` thay vì `leave()` —
    // socket đóng (server vào grace 60s) nhưng `ReconnectStore` vẫn giữ
    // roomId. Nếu user mở app lại trong khung 60s → auto-reconnect ở Lobby.
    if (lifeState == AppLifecycleState.detached) {
      final s = ref.read(onlineMatchControllerProvider);
      if (s.isPlaying) {
        _ctrl.disconnectKeepingReconnectState();
      }
    }
  }

  void _onTap(int row, int col) {
    final state = ref.read(onlineMatchControllerProvider);
    final game = state.game;
    if (game == null || !state.isPlaying || !state.isMyTurn) return;
    final tapped = Position(row, col);

    if (_selected == null) {
      // Try select own piece
      final piece = game.board.at(tapped);
      if (piece != null && piece.color == state.myColor) {
        setState(() {
          _selected = tapped;
          _validTargets = game.getValidMoves(tapped);
        });
      }
      return;
    }

    // Already selected — try to move or change selection
    if (_validTargets.contains(tapped)) {
      _ctrl.attemptMove(_selected!, tapped);
      setState(() {
        _selected = null;
        _validTargets = const [];
      });
      return;
    }

    // Tap on another own piece → switch selection
    final newPiece = game.board.at(tapped);
    if (newPiece != null && newPiece.color == state.myColor) {
      setState(() {
        _selected = tapped;
        _validTargets = game.getValidMoves(tapped);
      });
      return;
    }

    // Otherwise → deselect
    setState(() {
      _selected = null;
      _validTargets = const [];
    });
  }

  /// Single exit path for app-bar back AND the system back gesture (R9):
  /// always tell the server we're leaving so the opponent's UI reacts
  /// immediately (peer-left) instead of waiting for heartbeat timeout.
  Future<void> _onBackPressed() async {
    final state = ref.read(onlineMatchControllerProvider);
    if (state.isPlaying) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rời ván đấu?'),
          content: const Text('Rời ván giữa chừng sẽ bị xử thua.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ở lại'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rời ván'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      _ctrl.resign();
    }
    await _ctrl.leave();
    if (mounted) context.go(AppConstants.routeCompete);
  }

  Future<void> _confirmResign() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xin thua?'),
        content: const Text(
          'Xin thua sẽ kết thúc ván, đối thủ thắng. Bạn chắc chứ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xin thua'),
          ),
        ],
      ),
    );
    if (res == true) _ctrl.resign();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onlineMatchControllerProvider);

    // Start/stop ticker for reconnect countdown and the per-move clock.
    _ensureCountdown(state.isPlaying || state.isSpectating);

    // Pop screen when game ends + show result dialog + refresh profile from cloud
    ref.listen<OnlineMatchState>(onlineMatchControllerProvider, (prev, next) {
      if (next.phase == OnlineMatchPhase.ended &&
          prev?.phase != OnlineMatchPhase.ended) {
        _showResultDialog();
        if (next.myColor != null && !next.isCasual) {
          // G5: ELO + win/loss counters đã update trên cloud, pull về local để
          // Profile screen hiển thị ngay sau dialog dismiss (guard unmount).
          refreshProfileAfterRankedGame(
            refreshFromCloud: () =>
                ref.read(cloudSyncServiceProvider).refreshFromCloud(),
            refreshProfile: () =>
                ref.read(profileControllerProvider.notifier).refresh(),
            stillMounted: () => mounted,
          );
        }
      }
      // Sprint 12 rematch: both sides accepted → server restarted the room and
      // a fresh game-start moved us back to `playing`. The result dialog closes
      // itself (it watches the phase); here we just clear any stale board
      // selection from the previous game.
      if (next.phase == OnlineMatchPhase.playing &&
          prev?.phase == OnlineMatchPhase.ended) {
        setState(() {
          _selected = null;
          _validTargets = const [];
        });
      }
    });

    final game = state.game;
    final isSpectating = state.isSpectating;
    final flipped = !isSpectating && state.myColor == PieceColor.black;
    final checkedKing = _findCheckedKing(game);
    final topColor = isSpectating
        ? PieceColor.black
        : (state.myColor == PieceColor.red ? PieceColor.black : PieceColor.red);
    final bottomColor = isSpectating
        ? PieceColor.red
        : (state.myColor ?? PieceColor.red);
    final topLabel = isSpectating
        ? 'Đen ${_shortUid(state.blackUid)}'
        : (state.opponentUid != null
              ? _shortUid(state.opponentUid)
              : 'Đối thủ');
    final bottomLabel = isSpectating ? 'Đỏ ${_shortUid(state.redUid)}' : 'Bạn';

    final moveClockMs = _moveClockMs(state);

    // PopScope routes the SYSTEM back gesture through the same leave logic
    // as the app-bar arrow — otherwise Android back exits the screen while
    // the socket silently stays in the room (R9).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.woodDark,
          title: Text(
            isSpectating
                ? '${state.isCasual ? "Xem casual" : "Xem ván"} ${state.roomId ?? ""}'
                : '${state.isCasual ? "Casual" : "Online"} ${state.roomId ?? ""}',
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBackPressed,
          ),
          actions: [
            // Spectator count — players see it too (server broadcasts
            // spectator-joined/left to everyone in the room).
            if (isSpectating || state.isPlaying || state.isEnded)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_outlined, size: 18),
                    const SizedBox(width: 4),
                    Text('${state.spectatorCount}'),
                  ],
                ),
              ),
            if ((state.isPlaying || isSpectating) && state.roomId != null)
              IconButton(
                tooltip: 'Mời xem (link / QR)',
                icon: const Icon(Icons.share),
                onPressed: () => ShareRoomSheet.show(
                  context,
                  roomId: state.roomId,
                  spectate: true,
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: [
                _PlayerStrip(
                  label: topLabel,
                  color: topColor,
                  clockMs: topColor == PieceColor.red
                      ? state.redClockMs
                      : state.blackClockMs,
                  moveClockMs: moveClockMs,
                  isMyTurn: state.currentTurn == topColor,
                ),
                AppSpacing.vGapSm,
                if (game != null)
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 9 / 10,
                      child: ChessBoard(
                        board: game.board,
                        selected: _selected,
                        validTargets: _validTargets,
                        lastMove: game.lastMove,
                        checkedKing: checkedKing,
                        flipped: flipped,
                        onTap: _onTap,
                      ),
                    ),
                  )
                else
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                AppSpacing.vGapSm,
                _PlayerStrip(
                  label: bottomLabel,
                  color: bottomColor,
                  clockMs: bottomColor == PieceColor.red
                      ? state.redClockMs
                      : state.blackClockMs,
                  moveClockMs: moveClockMs,
                  isMyTurn: state.currentTurn == bottomColor,
                ),
                AppSpacing.vGapSm,
                Row(
                  children: [
                    Expanded(
                      child: OnlineChatButton(
                        messageCount: state.chatMessages.length,
                        canChat: state.canChat,
                        onPressed: _showChatSheet,
                      ),
                    ),
                    if (!isSpectating) ...[
                      AppSpacing.hGapSm,
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('Xin thua'),
                          onPressed: state.isPlaying ? _confirmResign : null,
                        ),
                      ),
                    ],
                  ],
                ),
                OnlineReconnectBanner(
                  phase: state.phase,
                  remainingGraceSec: _remainingGraceSec(state),
                ),
                if (state.errorMessage != null) ...[
                  AppSpacing.vGapSm,
                  Text(
                    state.errorMessage!,
                    style: AppTextStyles.captionSm.copyWith(
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Position? _findCheckedKing(XiangqiGame? game) {
    if (game == null) return null;
    for (final color in PieceColor.values) {
      if (!game.isInCheck(color)) continue;
      for (final (pos, piece) in game.board.occupied()) {
        if (piece.color == color && piece.type == PieceType.general) {
          return pos;
        }
      }
    }
    return null;
  }

  String _shortUid(String? uid) {
    if (uid == null || uid.isEmpty) return '—';
    return uid.length > 8 ? uid.substring(0, 8) : uid;
  }

  void _showChatSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerHigh,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final state = ref.watch(onlineMatchControllerProvider);
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SafeArea(
                child: FractionallySizedBox(
                  heightFactor: 0.62,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Chat ván đấu',
                              style: AppTextStyles.headingMd,
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        AppSpacing.vGapSm,
                        Expanded(
                          child: state.chatMessages.isEmpty
                              ? Center(
                                  child: Text(
                                    'Chưa có tin nhắn',
                                    style: AppTextStyles.captionSm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  reverse: true,
                                  itemCount: state.chatMessages.length,
                                  separatorBuilder: (context, _) =>
                                      AppSpacing.vGapXs,
                                  itemBuilder: (context, index) {
                                    final message =
                                        state.chatMessages[state
                                                .chatMessages
                                                .length -
                                            1 -
                                            index];
                                    final isMine =
                                        message.fromUid == state.myUid;
                                    return _ChatBubble(
                                      message: message,
                                      isMine: isMine,
                                    );
                                  },
                                ),
                        ),
                        AppSpacing.vGapSm,
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _quickChatPresets.length,
                            separatorBuilder: (context, _) => AppSpacing.hGapXs,
                            itemBuilder: (context, index) {
                              final preset = _quickChatPresets[index];
                              return ActionChip(
                                label: Text(
                                  preset,
                                  style: AppTextStyles.captionSm,
                                ),
                                backgroundColor:
                                    AppColors.surfaceContainerHighest,
                                side: const BorderSide(
                                  color: AppColors.outlineVariant,
                                ),
                                onPressed: state.canChat
                                    ? () => _ctrl.sendChatMessage(preset)
                                    : null,
                              );
                            },
                          ),
                        ),
                        AppSpacing.vGapSm,
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chatCtrl,
                                maxLength: 120,
                                minLines: 1,
                                maxLines: 3,
                                textInputAction: TextInputAction.send,
                                decoration: const InputDecoration(
                                  hintText: 'Nhắn trong ván...',
                                  counterText: '',
                                  prefixIcon: Icon(Icons.chat_outlined),
                                ),
                                onSubmitted: (_) => _sendChatMessage(),
                              ),
                            ),
                            AppSpacing.hGapSm,
                            IconButton.filled(
                              icon: const Icon(Icons.send),
                              onPressed: state.canChat
                                  ? _sendChatMessage
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _sendChatMessage() {
    final text = _chatCtrl.text;
    _ctrl.sendChatMessage(text);
    _chatCtrl.clear();
  }

  Future<void> _leaveToCompete(BuildContext dialogCtx) async {
    Navigator.pop(dialogCtx);
    await _ctrl.leave();
    if (mounted) context.go(AppConstants.routeCompete);
  }

  /// Result dialog with reactive rematch flow. The content/actions rebuild as
  /// the rematch offer state changes; when both sides accept, the server sends
  /// a fresh `game-start` (phase → playing) and the dialog auto-closes.
  Future<void> _showResultDialog() async {
    if (_resultDialogOpen) return;
    _resultDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final state = ref.watch(onlineMatchControllerProvider);

            // Rematch accepted (phase → playing) or we left — close the dialog.
            if (state.phase != OnlineMatchPhase.ended) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(dialogCtx).canPop()) {
                  Navigator.of(dialogCtx).pop();
                }
              });
              return const SizedBox.shrink();
            }

            return OnlineResultDialog(
              state: state,
              onLeave: () => _leaveToCompete(dialogCtx),
              onOfferRematch: _ctrl.offerRematch,
              onDeclineRematch: _ctrl.declineRematch,
            );
          },
        );
      },
    );
    _resultDialogOpen = false;
  }
}

class _PlayerStrip extends StatelessWidget {
  const _PlayerStrip({
    required this.label,
    required this.color,
    required this.clockMs,
    required this.moveClockMs,
    required this.isMyTurn,
  });
  final String label;
  final PieceColor color;
  final int clockMs;
  final int moveClockMs;
  final bool isMyTurn;

  String _formatClock(int ms) {
    if (ms <= 0) return '0:00';
    final s = (ms / 1000).floor();
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final accent = color == PieceColor.red
        ? AppColors.vermilionRed
        : AppColors.inkBlack;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isMyTurn
            ? AppColors.accentGold.withValues(alpha: 0.18)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMyTurn ? AppColors.accentGold : AppColors.outlineVariant,
          width: isMyTurn ? 2 : 1,
        ),
      ),
      // Name · move clock · total clock on ONE row. The move-clock chip always
      // reserves its slot (Visibility.maintainSize), so the strip height is
      // identical whether or not it's this side's turn — no board jitter (S-fix).
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppTextStyles.bodyMd)),
          MoveClockChip(
            timeLeft: Duration(milliseconds: moveClockMs),
            visible: isMyTurn,
          ),
          const SizedBox(width: 8),
          Text(
            _formatClock(clockMs),
            style: AppTextStyles.monoTimer.copyWith(
              color: isMyTurn ? AppColors.accentGold : AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isMine});

  final OnlineChatMessage message;
  final bool isMine;

  String _timeLabel(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final bg = isMine
        ? AppColors.accentGold.withValues(alpha: 0.22)
        : AppColors.surfaceContainer;
    final border = isMine ? AppColors.accentGold : AppColors.outlineVariant;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final shortUid = message.fromUid.length > 8
        ? message.fromUid.substring(0, 8)
        : message.fromUid;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border.withValues(alpha: 0.65)),
          ),
          child: Column(
            crossAxisAlignment: align,
            children: [
              Text(
                isMine ? 'Bạn' : shortUid,
                style: AppTextStyles.captionSm.copyWith(
                  color: isMine
                      ? AppColors.accentGold
                      : AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(message.text, style: AppTextStyles.bodyMd),
              const SizedBox(height: 2),
              Text(
                _timeLabel(message.sentAtMs),
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
