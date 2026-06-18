import '../../core/chess_engine/chess_engine.dart';
import 'online_match_controller.dart';

/// Pure presentation helpers for the online result dialog + reconnect banner.
///
/// Extracted from [OnlineGameScreen] so the G4 result-dialog logic (title /
/// reason / ELO delta) and the D-group grace countdown are unit-testable
/// without pumping the whole screen (which drags in go_router, connectivity_plus
/// and Firebase-backed providers). The widget keeps owning colours/icons; this
/// file owns the *decisions*.

/// G4: dialog title from the server result, relative to my colour.
/// Spectators (myColor == null) see neutral "Đỏ thắng / Đen thắng".
String onlineResultTitle(String? result, PieceColor? myColor) {
  if (result == 'draw') return 'Hòa';
  if (myColor != null) {
    final iWon =
        (result == 'red-win' && myColor == PieceColor.red) ||
        (result == 'black-win' && myColor == PieceColor.black);
    return iWon ? 'Bạn thắng!' : 'Bạn thua';
  }
  return switch (result) {
    'red-win' => 'Đỏ thắng',
    'black-win' => 'Đen thắng',
    'draw' => 'Hòa',
    _ => 'Kết quả: $result',
  };
}

/// G4: Vietnamese label for the end reason. Unknown codes fall through as-is;
/// null (no reason yet) renders as an em dash.
String onlineReasonLabel(String? reason) {
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

/// Direction of my ELO change — drives the colour/icon shown in the dialog.
enum EloDeltaDirection { up, down, flat }

/// G4: my-side ELO change after a ranked game, decoded from the server's
/// `game-ended.elo` map. Null when the server didn't compute ELO (unranked /
/// persist failed) or I'm a spectator (no `myColor`).
class OnlineEloDelta {
  const OnlineEloDelta({
    required this.delta,
    required this.newElo,
    required this.direction,
  });

  final int delta;
  final int? newElo;
  final EloDeltaDirection direction;

  /// "+" for a gain, empty otherwise (the minus sign is part of [delta]).
  String get sign => direction == EloDeltaDirection.up ? '+' : '';

  static OnlineEloDelta? fromUpdate(
    Map<String, dynamic>? eloUpdate,
    PieceColor? myColor,
  ) {
    if (eloUpdate == null || myColor == null) return null;
    final side = myColor == PieceColor.red
        ? eloUpdate['red'] as Map<String, dynamic>?
        : eloUpdate['black'] as Map<String, dynamic>?;
    if (side == null) return null;
    final delta = (side['delta'] as num?)?.toInt() ?? 0;
    final newElo = (side['new'] as num?)?.toInt();
    final direction = delta > 0
        ? EloDeltaDirection.up
        : (delta < 0 ? EloDeltaDirection.down : EloDeltaDirection.flat);
    return OnlineEloDelta(delta: delta, newElo: newElo, direction: direction);
  }
}

/// D-group: seconds left in the peer-disconnect grace window, or null when we
/// aren't waiting for a peer to come back. [nowMs] is injected so the formula
/// is deterministic in tests. Clamps to 0 once the deadline has passed.
int? onlineRemainingGraceSec(OnlineMatchState s, int nowMs) {
  if (s.phase != OnlineMatchPhase.peerDisconnected) return null;
  final start = s.peerDisconnectedAtMs;
  final grace = s.peerDisconnectGraceMs;
  if (start == null || grace == null) return null;
  final remaining = grace - (nowMs - start);
  if (remaining <= 0) return 0;
  return (remaining / 1000).ceil();
}

/// G5: after a ranked game ends, pull fresh ELO/counters from the cloud and
/// then refresh the local profile so the Profile screen is up to date the
/// moment the result dialog is dismissed. The cloud round-trip can outlive the
/// screen, so [stillMounted] guards the second step.
Future<void> refreshProfileAfterRankedGame({
  required Future<void> Function() refreshFromCloud,
  required Future<void> Function() refreshProfile,
  required bool Function() stillMounted,
}) async {
  await refreshFromCloud();
  if (stillMounted()) await refreshProfile();
}
