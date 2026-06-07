import '../../core/constants/app_constants.dart';

/// A6 Spectate share link — pure helpers to build and parse shareable room
/// links and invite text. Kept free of Flutter/platform imports so it can be
/// unit-tested in isolation (see `test/online/room_share_test.dart`).
///
/// Canonical link shape:
///   `https://<base>/r/<ROOMID>`            → default = spectate (watch)
///   `https://<base>/r/<ROOMID>?mode=join`  → join as a player
///
/// The backend serves a small landing page at `/r/:id` so the link is useful
/// when opened in a browser. Inside the app, [roomIdFromLink] extracts the room
/// id and the lobby deep-links straight into spectate/join.
class RoomShare {
  RoomShare._();

  /// Room ids are 6 chars from an unambiguous uppercase alphabet on the server.
  /// We validate a slightly looser `[A-Z0-9]{6}` so user-typed/scanned codes
  /// still pass after normalization.
  static final RegExp _roomIdPattern = RegExp(r'^[A-Z0-9]{6}$');

  /// Trim + uppercase a raw room id (matches server-side normalization).
  static String normalizeRoomId(String raw) => raw.trim().toUpperCase();

  /// Whether [raw] looks like a valid room id once normalized.
  static bool isValidRoomId(String raw) =>
      _roomIdPattern.hasMatch(normalizeRoomId(raw));

  /// Canonical shareable HTTPS link for [roomId].
  ///
  /// [spectate] true (default) builds a watch link; false builds a join link
  /// (`?mode=join`). [base] overrides [AppConstants.shareLinkBase] for tests.
  static String linkFor(
    String roomId, {
    bool spectate = true,
    String? base,
  }) {
    final id = normalizeRoomId(roomId);
    final origin = (base ?? AppConstants.shareLinkBase).replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final query = spectate ? '' : '?mode=join';
    return '$origin/r/$id$query';
  }

  /// Vietnamese invite message including the link. Suitable for the native
  /// share sheet or clipboard.
  static String inviteText(
    String roomId, {
    bool spectate = true,
    String? base,
  }) {
    final id = normalizeRoomId(roomId);
    final link = linkFor(id, spectate: spectate, base: base);
    if (spectate) {
      return 'Vào xem ván Cờ Tướng của mình trên CChess nhé!\n'
          'Mã phòng: $id\n'
          '$link';
    }
    return 'Vào đấu Cờ Tướng với mình trên CChess nhé!\n'
        'Mã phòng: $id\n'
        '$link';
  }

  /// Extract a room id from a shared link or raw input. Accepts:
  ///   - `https://host/r/ABC123` (with optional `?mode=...`)
  ///   - `cchess://spectate/ABC123` / `cchess://join/ABC123` (OS deep link)
  ///   - `...online-lobby?spectate=ABC123` / `?join=ABC123`
  ///   - a bare `ABC123` code
  ///
  /// Returns the normalized room id, or null if none found.
  static String? roomIdFromLink(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    // Bare code fast-path.
    if (isValidRoomId(raw)) return normalizeRoomId(raw);

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      // Query params: ?spectate=ID / ?join=ID / ?room=ID
      for (final key in const ['spectate', 'join', 'room', 'roomId']) {
        final v = uri.queryParameters[key];
        if (v != null && isValidRoomId(v)) return normalizeRoomId(v);
      }
      // Path segments: /r/ID, /spectate/ID, /join/ID, or host = ID
      // (cchess://spectate/ID parses host='spectate', segment='ID').
      final segments = [
        if (uri.host.isNotEmpty) uri.host,
        ...uri.pathSegments,
      ];
      for (final seg in segments.reversed) {
        if (isValidRoomId(seg)) return normalizeRoomId(seg);
      }
    }
    return null;
  }

  /// Whether a shared link/input requests joining as a player rather than
  /// spectating. Defaults to false (spectate) when ambiguous.
  static bool isJoinLink(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    if (uri.queryParameters['mode'] == 'join') return true;
    if (uri.queryParameters.containsKey('join')) return true;
    final segs = [uri.host, ...uri.pathSegments];
    return segs.any((s) => s.toLowerCase() == 'join');
  }
}
