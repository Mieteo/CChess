import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the room ID + last activity timestamp so the app can attempt
/// reconnect when reopened within the server's grace window.
///
/// Should mirror server's `RECONNECT_GRACE_MS` in match.ts (60s currently);
/// we use a slightly larger window client-side to account for round-trip.
class ReconnectStore {
  static const String _kRoomId = 'cchess_online_room_id';
  static const String _kLastActivityMs = 'cchess_online_last_activity_ms';

  /// Slightly larger than server grace (60s) — if we're past this on app
  /// open, no point trying to reconnect.
  static const Duration freshness = Duration(seconds: 70);

  Future<void> save(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRoomId, roomId);
    await prefs.setInt(
      _kLastActivityMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRoomId);
    await prefs.remove(_kLastActivityMs);
  }

  /// Returns the saved room ID regardless of age. Used for MID-GAME reconnect,
  /// where we know we just dropped — the server's grace window (60s) is the
  /// real bound, so we don't apply the relaunch freshness gate here. Returns
  /// null only if nothing was ever saved.
  Future<String?> readRoomId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kRoomId);
  }

  /// Returns the saved room ID if it's still fresh enough to attempt a
  /// reconnect; otherwise clears stale entries and returns null.
  Future<String?> readFresh() async {
    final prefs = await SharedPreferences.getInstance();
    final roomId = prefs.getString(_kRoomId);
    final lastMs = prefs.getInt(_kLastActivityMs);
    if (roomId == null || lastMs == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - lastMs;
    if (age > freshness.inMilliseconds) {
      await clear();
      return null;
    }
    return roomId;
  }
}

final reconnectStoreProvider =
    Provider<ReconnectStore>((ref) => ReconnectStore());
