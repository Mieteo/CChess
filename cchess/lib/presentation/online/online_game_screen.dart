import 'dart:async';

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
import '../profile/profile_controller.dart';
import 'online_match_controller.dart';
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

  OnlineMatchController get _ctrl =>
      ref.read(onlineMatchControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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
  int? _remainingGraceSec(OnlineMatchState s) {
    if (s.phase != OnlineMatchPhase.peerDisconnected) return null;
    final start = s.peerDisconnectedAtMs;
    final grace = s.peerDisconnectGraceMs;
    if (start == null || grace == null) return null;
    final elapsed = DateTime.now().millisecondsSinceEpoch - start;
    final remaining = grace - elapsed;
    if (remaining <= 0) return 0;
    return (remaining / 1000).ceil();
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

    // Start/stop countdown ticker based on current phase
    _ensureCountdown(state.phase == OnlineMatchPhase.peerDisconnected);

    // Pop screen when game ends + show result dialog + refresh profile from cloud
    ref.listen<OnlineMatchState>(onlineMatchControllerProvider, (prev, next) {
      if (next.phase == OnlineMatchPhase.ended &&
          prev?.phase != OnlineMatchPhase.ended) {
        _showResultDialog();
        if (next.myColor != null) {
          // Step Group-1 polish: ELO + win/loss counters đã update trên cloud,
          // pull về local để Profile screen hiển thị ngay sau dialog dismiss.
          () async {
            await ref.read(cloudSyncServiceProvider).refreshFromCloud();
            if (mounted) {
              await ref.read(profileControllerProvider.notifier).refresh();
            }
          }();
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
                ? 'Xem ván ${state.roomId ?? ""}'
                : 'Online ${state.roomId ?? ""}',
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
                  isMyTurn: state.currentTurn == bottomColor,
                ),
                AppSpacing.vGapSm,
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: Text(
                          'Chat${state.chatMessages.isNotEmpty ? " (${state.chatMessages.length})" : ""}',
                        ),
                        onPressed: state.canChat ? _showChatSheet : null,
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
                if (state.phase == OnlineMatchPhase.peerDisconnected) ...[
                  AppSpacing.vGapSm,
                  Builder(
                    builder: (_) {
                      final sec = _remainingGraceSec(state);
                      final String label;
                      if (sec == null) {
                        label = 'Đối thủ mất kết nối — chờ reconnect…';
                      } else if (sec > 0) {
                        label =
                            'Đối thủ mất kết nối — còn ${sec}s để reconnect';
                      } else {
                        // Local countdown finished; server's grace timer fires
                        // ~ within seconds. Avoid showing a stale "0s".
                        label = 'Hết thời gian chờ — đang xác nhận kết quả…';
                      }
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.accentGold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.accentGold),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wifi_off,
                              size: 16,
                              color: AppColors.accentGold,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                label,
                                style: AppTextStyles.captionSm.copyWith(
                                  color: AppColors.accentGold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
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

  String _resultTitle(OnlineMatchState state) {
    final myColor = state.myColor;
    if (state.result == 'draw') return 'Hòa';
    if (myColor != null) {
      final iWon =
          (state.result == 'red-win' && myColor == PieceColor.red) ||
          (state.result == 'black-win' && myColor == PieceColor.black);
      return iWon ? 'Bạn thắng!' : 'Bạn thua';
    }
    return switch (state.result) {
      'red-win' => 'Đỏ thắng',
      'black-win' => 'Đen thắng',
      'draw' => 'Hòa',
      _ => 'Kết quả: ${state.result}',
    };
  }

  String _reasonLabel(String? reason) {
    return switch (reason) {
      'timeout' => 'Hết giờ',
      'resign' => 'Xin thua',
      'disconnect' => 'Đối thủ mất kết nối',
      'checkmate' => 'Chiếu bí',
      'stalemate' => 'Hết nước đi (thua)',
      null => '—',
      _ => reason,
    };
  }

  /// Step A2: my-side ELO change widget, or null if server didn't send ELO.
  Widget? _buildEloWidget(OnlineMatchState state) {
    final myColor = state.myColor;
    final eloUpdate = state.eloUpdate;
    if (eloUpdate == null || myColor == null) return null;
    final myEloSide = myColor == PieceColor.red
        ? eloUpdate['red'] as Map<String, dynamic>?
        : eloUpdate['black'] as Map<String, dynamic>?;
    if (myEloSide == null) return null;
    final delta = (myEloSide['delta'] as num?)?.toInt() ?? 0;
    final newElo = (myEloSide['new'] as num?)?.toInt();
    final isUp = delta > 0;
    final isFlat = delta == 0;
    final color = isFlat
        ? AppColors.parchmentTan
        : (isUp ? AppColors.tealSuccess : AppColors.vermilionRed);
    final sign = isUp ? '+' : '';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            isFlat
                ? Icons.remove
                : (isUp ? Icons.trending_up : Icons.trending_down),
            color: color,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            'ELO: $sign$delta${newElo != null ? "  →  $newElo" : ""}',
            style: AppTextStyles.headingMd.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  /// Highlighted info tile inside the result dialog for rematch status.
  Widget _rematchTile(String text, IconData icon, {bool showSpinner = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.accentGold.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accentGold),
        ),
        child: Row(
          children: [
            if (showSpinner)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accentGold,
                ),
              )
            else
              Icon(icon, size: 16, color: AppColors.accentGold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.accentGold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

            // Opponent already gone (left/disconnected) → rematch impossible.
            // `opponentLeftRoom` flips the moment the server broadcasts
            // peer-left (R9), so the dialog reacts without a failed offer.
            final opponentGone =
                state.endReason == 'disconnect' || state.opponentLeftRoom;
            final meOffered = state.rematchOfferedByMe;
            final oppOffered = state.rematchOfferedByOpponent;
            // Spectators (myColor == null) get a read-only dialog: a single
            // "Thoát" button. If the players start a rematch, phase flips to
            // spectating and the auto-close above resumes watching.
            final watching = state.myColor == null;

            final content = <Widget>[
              Text('Lý do: ${_reasonLabel(state.endReason)}'),
            ];
            final eloWidget = _buildEloWidget(state);
            if (eloWidget != null) content.add(eloWidget);

            if (watching) {
              content.add(
                state.opponentLeftRoom
                    ? _rematchTile(
                        'Một kỳ thủ đã rời — trận đấu khép lại.',
                        Icons.person_off_outlined,
                      )
                    : _rematchTile(
                        'Nếu hai kỳ thủ đấu lại, ván mới sẽ tự mở.',
                        Icons.visibility_outlined,
                      ),
              );
              return AlertDialog(
                title: Text(_resultTitle(state)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content,
                ),
                actions: [
                  TextButton(
                    onPressed: () => _leaveToCompete(dialogCtx),
                    child: const Text('Thoát'),
                  ),
                ],
              );
            }

            if (opponentGone) {
              content.add(
                _rematchTile(
                  'Đối thủ đã rời — không thể đấu lại.',
                  Icons.person_off_outlined,
                ),
              );
            } else if (meOffered) {
              content.add(
                _rematchTile(
                  'Đang chờ đối thủ đồng ý đấu lại…',
                  Icons.hourglass_top,
                  showSpinner: true,
                ),
              );
            } else if (oppOffered) {
              content.add(
                _rematchTile('Đối thủ muốn đấu lại!', Icons.sports_kabaddi),
              );
            }
            if (state.errorMessage != null) {
              content.add(
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    state.errorMessage!,
                    style: AppTextStyles.captionSm.copyWith(
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              );
            }

            final leaveButton = TextButton(
              onPressed: () => _leaveToCompete(dialogCtx),
              child: const Text('Về Đối Đầu'),
            );

            final List<Widget> actions;
            if (opponentGone) {
              actions = [leaveButton];
            } else if (meOffered) {
              // Waiting for opponent — allow retracting or leaving.
              actions = [
                TextButton(
                  onPressed: _ctrl.declineRematch,
                  child: const Text('Hủy'),
                ),
                leaveButton,
              ];
            } else if (oppOffered) {
              // Opponent offered — accept (→ restart) or decline.
              actions = [
                TextButton(
                  onPressed: _ctrl.declineRematch,
                  child: const Text('Từ chối'),
                ),
                FilledButton(
                  onPressed: _ctrl.offerRematch,
                  child: const Text('Đồng ý'),
                ),
              ];
            } else {
              actions = [
                leaveButton,
                FilledButton.icon(
                  onPressed: _ctrl.offerRematch,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Đấu lại'),
                ),
              ];
            }

            return AlertDialog(
              title: Text(_resultTitle(state)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
              actions: actions,
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
    required this.isMyTurn,
  });
  final String label;
  final PieceColor color;
  final int clockMs;
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
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppTextStyles.bodyMd)),
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
