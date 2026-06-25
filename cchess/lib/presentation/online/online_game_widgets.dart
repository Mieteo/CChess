import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import 'online_match_controller.dart';
import 'online_result_format.dart';

/// Presentational widgets extracted from [OnlineGameScreen] so the visually
/// stateful pieces — the chat button badge (C2), the reconnect banner (D), and
/// the result dialog (G4) — can be widget-tested in isolation, without pumping
/// the whole screen (which drags in go_router, connectivity_plus and Firebase
/// providers). Each takes plain inputs + callbacks; the screen wires them to the
/// controller. Behaviour is unchanged — the screen now just delegates.

/// C2: the in-game chat button. Shows a "(n)" count once any message has
/// arrived and disables itself while chat isn't allowed (not playing/spectating).
class OnlineChatButton extends StatelessWidget {
  const OnlineChatButton({
    super.key,
    required this.messageCount,
    required this.canChat,
    required this.onPressed,
  });

  final int messageCount;
  final bool canChat;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.chat_bubble_outline),
      label: Text('Chat${messageCount > 0 ? " ($messageCount)" : ""}'),
      onPressed: canChat ? onPressed : null,
    );
  }
}

/// D-group: the gold banner shown while a peer is in the reconnect grace window
/// (countdown) or while WE are reconnecting (spinner). Renders nothing in any
/// other phase. [remainingGraceSec] is precomputed by the screen (it depends on
/// DateTime.now()) so this widget stays deterministic for tests.
class OnlineReconnectBanner extends StatelessWidget {
  const OnlineReconnectBanner({
    super.key,
    required this.phase,
    required this.remainingGraceSec,
  });

  final OnlineMatchPhase phase;
  final int? remainingGraceSec;

  @override
  Widget build(BuildContext context) {
    if (phase == OnlineMatchPhase.peerDisconnected) {
      final sec = remainingGraceSec;
      final String label;
      if (sec == null) {
        label = 'Đối thủ mất kết nối — chờ reconnect…';
      } else if (sec > 0) {
        label = 'Đối thủ mất kết nối — còn ${sec}s để reconnect';
      } else {
        // Local countdown finished; the server's grace timer fires within
        // seconds. Avoid showing a stale "0s".
        label = 'Hết thời gian chờ — đang xác nhận kết quả…';
      }
      return _GoldBanner(
        leading: const Icon(
          Icons.wifi_off,
          size: 16,
          color: AppColors.accentGold,
        ),
        label: label,
      );
    }
    if (phase == OnlineMatchPhase.reconnecting) {
      return const _GoldBanner(
        leading: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accentGold,
          ),
        ),
        label: 'Mất kết nối — đang kết nối lại…',
      );
    }
    return const SizedBox.shrink();
  }
}

/// The shared gold-bordered banner chrome used by both reconnect states.
class _GoldBanner extends StatelessWidget {
  const _GoldBanner({required this.leading, required this.label});

  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
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
            leading,
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
      ),
    );
  }
}

/// G4: the end-of-game result dialog body. Owns the title / reason / ELO delta /
/// rematch presentation; the screen owns the surrounding `showDialog` + the
/// auto-close that fires when a rematch flips the phase away from `ended`.
/// Buttons call back into the controller via the three callbacks.
class OnlineResultDialog extends StatelessWidget {
  const OnlineResultDialog({
    super.key,
    required this.state,
    required this.onLeave,
    required this.onOfferRematch,
    required this.onDeclineRematch,
  });

  final OnlineMatchState state;

  /// "Thoát" / "Về Đối Đầu": leave the room back to the compete screen.
  final VoidCallback onLeave;

  /// "Đấu lại" / "Đồng ý": offer (or accept) a rematch.
  final VoidCallback onOfferRematch;

  /// "Hủy" / "Từ chối": retract my offer or decline the opponent's.
  final VoidCallback onDeclineRematch;

  @override
  Widget build(BuildContext context) {
    // Opponent already gone (left/disconnected) → rematch impossible.
    // `opponentLeftRoom` flips the moment the server broadcasts peer-left (R9),
    // so the dialog reacts without a failed offer round-trip.
    final opponentGone =
        state.endReason == 'disconnect' || state.opponentLeftRoom;
    final meOffered = state.rematchOfferedByMe;
    final oppOffered = state.rematchOfferedByOpponent;
    // Spectators (myColor == null) get a read-only dialog: a single "Thoát".
    final watching = state.myColor == null;

    final content = <Widget>[
      Text('Lý do: ${onlineReasonLabel(state.endReason)}'),
    ];
    // Casual (Cờ giao hữu): no ELO is computed for either side, so make that
    // explicit instead of silently omitting the ELO row. Ranked games fall
    // through to the ELO delta below.
    if (state.isCasual) {
      content.add(
        _rematchTile('Cờ giao hữu — không tính ELO.', Icons.favorite_outline),
      );
    } else {
      final eloWidget = _eloWidget();
      if (eloWidget != null) content.add(eloWidget);
    }

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
        title: Text(onlineResultTitle(state.result, state.myColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: content,
        ),
        actions: [
          TextButton(onPressed: onLeave, child: const Text('Thoát')),
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
            style: AppTextStyles.captionSm.copyWith(color: Colors.redAccent),
          ),
        ),
      );
    }

    final leaveButton = TextButton(
      onPressed: onLeave,
      child: const Text('Về Đối Đầu'),
    );

    final List<Widget> actions;
    if (opponentGone) {
      actions = [leaveButton];
    } else if (meOffered) {
      // Waiting for opponent — allow retracting or leaving.
      actions = [
        TextButton(onPressed: onDeclineRematch, child: const Text('Hủy')),
        leaveButton,
      ];
    } else if (oppOffered) {
      // Opponent offered — accept (→ restart) or decline.
      actions = [
        TextButton(onPressed: onDeclineRematch, child: const Text('Từ chối')),
        FilledButton(onPressed: onOfferRematch, child: const Text('Đồng ý')),
      ];
    } else {
      actions = [
        leaveButton,
        FilledButton.icon(
          onPressed: onOfferRematch,
          icon: const Icon(Icons.refresh),
          label: const Text('Đấu lại'),
        ),
      ];
    }

    return AlertDialog(
      title: Text(onlineResultTitle(state.result, state.myColor)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      ),
      actions: actions,
    );
  }

  /// My-side ELO change row, or null if the server didn't send ELO (unranked /
  /// persist failed / I'm a spectator).
  Widget? _eloWidget() {
    final elo = OnlineEloDelta.fromUpdate(state.eloUpdate, state.myColor);
    if (elo == null) return null;
    final (color, icon) = switch (elo.direction) {
      EloDeltaDirection.up => (AppColors.tealSuccess, Icons.trending_up),
      EloDeltaDirection.down => (AppColors.vermilionRed, Icons.trending_down),
      EloDeltaDirection.flat => (AppColors.parchmentTan, Icons.remove),
    };
    final newElo = elo.newElo;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            'ELO: ${elo.sign}${elo.delta}${newElo != null ? "  →  $newElo" : ""}',
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
}
