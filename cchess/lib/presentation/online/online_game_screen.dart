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
        _showResultDialog(next);
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

    return Scaffold(
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
          onPressed: () async {
            if (isSpectating) {
              await _ctrl.leave();
            }
            if (context.mounted) context.go(AppConstants.routeCompete);
          },
        ),
        actions: [
          if (isSpectating)
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
                      label = 'Đối thủ mất kết nối — còn ${sec}s để reconnect';
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

  Future<void> _showResultDialog(OnlineMatchState state) async {
    final myColor = state.myColor;
    String title;
    if (state.result == 'draw') {
      title = 'Hòa';
    } else if (myColor != null) {
      final iWon =
          (state.result == 'red-win' && myColor == PieceColor.red) ||
          (state.result == 'black-win' && myColor == PieceColor.black);
      title = iWon ? 'Bạn thắng!' : 'Bạn thua';
    } else {
      title = switch (state.result) {
        'red-win' => 'Đỏ thắng',
        'black-win' => 'Đen thắng',
        'draw' => 'Hòa',
        _ => 'Kết quả: ${state.result}',
      };
    }

    // Step A2: extract my-side ELO change if available
    Widget? eloWidget;
    final eloUpdate = state.eloUpdate;
    if (eloUpdate != null && myColor != null) {
      final myEloSide = myColor == PieceColor.red
          ? eloUpdate['red'] as Map<String, dynamic>?
          : eloUpdate['black'] as Map<String, dynamic>?;
      if (myEloSide != null) {
        final delta = (myEloSide['delta'] as num?)?.toInt() ?? 0;
        final newElo = (myEloSide['new'] as num?)?.toInt();
        final isUp = delta > 0;
        final isFlat = delta == 0;
        final color = isFlat
            ? AppColors.parchmentTan
            : (isUp ? AppColors.tealSuccess : AppColors.vermilionRed);
        final sign = isUp ? '+' : '';
        eloWidget = Padding(
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
    }

    final resultContent = <Widget>[Text('Lý do: ${state.endReason ?? "—"}')];
    if (eloWidget != null) resultContent.add(eloWidget);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: resultContent,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _ctrl.leave();
              if (mounted) context.go(AppConstants.routeCompete);
            },
            child: const Text('Về Đối Đầu'),
          ),
        ],
      ),
    );
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
