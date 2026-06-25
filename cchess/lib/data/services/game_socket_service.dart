import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal WebSocket client for [cchess-backend].
///
/// Step 2 protocol (auth handshake):
///   - connect(url)
///   - authenticate() → sends current user's Firebase ID token
///   - listen via [messages] stream
///   - send({...})
///   - disconnect()
class GameSocketService {
  GameSocketService(this._auth);
  final FirebaseAuth _auth;

  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  StreamSubscription<dynamic>? _sub;
  String? _authedUid;
  String? _currentRoomId;

  // D1 fix: application-level heartbeat + watchdog. We send {type:'ping'} on a
  // timer and the server answers {type:'pong'}; `_lastInboundAt` tracks the last
  // frame we received from the server. If nothing arrives within `_silenceTimeout`
  // the connection is treated as dead — this detects mobile wifi drops in
  // seconds instead of waiting minutes for the OS TCP timeout to surface via
  // onError/onDone.
  Timer? _heartbeatTimer;
  DateTime? _lastInboundAt;
  bool _lostNotified = false;

  /// Fired once when the socket drops or goes silent past the liveness window.
  /// The controller wires this up to drive mid-game auto-reconnect. NOT fired
  /// for an intentional [disconnect].
  void Function()? onConnectionLost;

  static const Duration _pingInterval = Duration(seconds: 5);
  static const Duration _silenceTimeout = Duration(seconds: 15);

  Stream<Map<String, dynamic>> get messages =>
      _controller?.stream ?? const Stream.empty();
  String? get authedUid => _authedUid;
  String? get currentRoomId => _currentRoomId;
  bool get isConnected => _channel != null;
  bool get isAuthed => _authedUid != null;
  bool get isInRoom => _currentRoomId != null;

  Future<void> connect(String url) async {
    if (_channel != null) {
      throw StateError('Đang kết nối — disconnect trước khi connect lại.');
    }
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    _controller = StreamController<Map<String, dynamic>>.broadcast();
    _lostNotified = false;
    _lastInboundAt = DateTime.now();
    _sub = channel.stream.listen(
      (data) {
        try {
          final raw = data is String ? data : (data as List<int>).toString();
          final msg = jsonDecode(raw) as Map<String, dynamic>;
          _lastInboundAt = DateTime.now();
          // D1 fix: 'pong' is liveness-only — it already refreshed the watchdog
          // above; don't forward it (would flood the controller's event log).
          if (msg['type'] == 'pong') return;
          switch (msg['type']) {
            case 'authed':
              _authedUid = msg['uid'] as String?;
              break;
            case 'room-created':
            case 'room-joined':
            case 'reconnected':
            case 'match-found':
            case 'spectate-started':
              _currentRoomId = msg['roomId'] as String?;
              break;
            // NOTE: 'game-ended' deliberately does NOT clear the room id —
            // the player is still a member of the (finished) room on the
            // server (rematch needs it), and leave() relies on isInRoom to
            // send a proper leave-room. Clearing it here made "Về Đối Đầu"
            // exit silently, so the opponent only learned we were gone after
            // the heartbeat killed the socket (~10s) — bug R9.
            case 'left-room':
            case 'spectate-stopped':
            case 'room-expired':
              _currentRoomId = null;
              break;
          }
          _safeAdd(msg);
        } catch (e) {
          _safeAddError('Parse error: $e');
        }
      },
      onError: (Object e, StackTrace st) {
        _safeAddError(e, st);
        _handleConnectionDown();
      },
      onDone: () {
        _authedUid = null;
        _currentRoomId = null;
        final c = _controller;
        _controller = null;
        _channel = null;
        c?.close();
        _handleConnectionDown();
      },
    );
    _startHeartbeat();
  }

  // ── D1 fix: heartbeat + watchdog ───────────────────────────────────────
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_pingInterval, (_) {
      final last = _lastInboundAt;
      if (last != null && DateTime.now().difference(last) > _silenceTimeout) {
        // Server has gone silent past the liveness window → treat as dropped.
        _handleConnectionDown();
        return;
      }
      try {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {
        // Sink already gone — the watchdog/onDone path will handle teardown.
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Tear down a dead connection and notify [onConnectionLost] exactly once.
  /// Guarded by [_lostNotified] so onError + onDone + watchdog don't multi-fire;
  /// [disconnect] sets the guard up-front so intentional closes stay silent.
  void _handleConnectionDown() {
    if (_lostNotified) return;
    _lostNotified = true;
    _stopHeartbeat();
    try {
      _channel?.sink.close();
    } catch (_) {
      // ignore — may already be half-closed
    }
    final cb = onConnectionLost;
    if (cb != null) cb();
  }

  void _safeAdd(Map<String, dynamic> msg) {
    final c = _controller;
    if (c != null && !c.isClosed) c.add(msg);
  }

  void _safeAddError(Object err, [StackTrace? st]) {
    final c = _controller;
    if (c != null && !c.isClosed) c.addError(err, st);
  }

  Future<void> authenticate() async {
    final channel = _channel;
    if (channel == null) throw StateError('Chưa connect.');
    final user = _auth.currentUser;
    if (user == null) throw StateError('Chưa đăng nhập Firebase.');
    final token = await user.getIdToken();
    channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
  }

  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void createRoom({int? clockMs, bool casual = false, String? variant}) {
    final message = <String, dynamic>{'type': 'create-room'};
    if (clockMs != null) message['clockMs'] = clockMs;
    if (casual) message['mode'] = 'casual';
    if (variant != null) message['variant'] = variant;
    send(message);
  }

  /// Step A3: enter matchmaking queue. Server pairs by ELO tolerance that
  /// widens as players wait, then creates a room automatically. [variant]
  /// `cup` queues in the Cờ Úp pool (never paired against standard players).
  void findMatch({int? clockMs, String? variant}) {
    final message = <String, dynamic>{'type': 'find-match'};
    if (clockMs != null) message['clockMs'] = clockMs;
    if (variant != null) message['variant'] = variant;
    send(message);
  }

  void cancelMatching() => send({'type': 'cancel-matching'});

  void listActiveRooms() => send({'type': 'list-active-rooms'});

  void joinRoom(String roomId) =>
      send({'type': 'join-room', 'roomId': roomId.trim().toUpperCase()});

  void spectateRoom(String roomId) =>
      send({'type': 'spectate-room', 'roomId': roomId.trim().toUpperCase()});

  void stopSpectating() => send({'type': 'stop-spectating'});

  /// Step 8: try to resume an in-progress room after a brief disconnect.
  /// Server verifies uid matches the one stored as `disconnectedUid` and
  /// that we're still within the grace window.
  void reconnectRoom(String roomId) =>
      send({'type': 'reconnect-room', 'roomId': roomId.trim().toUpperCase()});

  void leaveRoom() => send({'type': 'leave-room'});

  void broadcast(Map<String, dynamic> payload) =>
      send({'type': 'broadcast', 'payload': payload});

  void sendChatMessage(String text) =>
      send({'type': 'chat-message', 'text': text.trim()});

  /// Sprint 12 rematch: offer to play again in the same room (colors swap).
  /// When both players offer, the server restarts the game automatically.
  void offerRematch() => send({'type': 'rematch-offer'});

  void declineRematch() => send({'type': 'rematch-decline'});

  /// Step 4: send a Xiangqi move in UCI format (e.g. "e2e4").
  /// Server validates format + turn + clock + Xiangqi legality.
  void sendMove(String uci) =>
      send({'type': 'move', 'uci': uci.trim().toLowerCase()});

  /// Step 6: resign current game. Sender loses; server broadcasts `game-ended`.
  void resign() => send({'type': 'resign'});

  Future<void> disconnect() async {
    // Intentional close — suppress the onConnectionLost path and stop pinging.
    _lostNotified = true;
    _stopHeartbeat();
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _authedUid = null;
    _currentRoomId = null;
    await _controller?.close();
    _controller = null;
  }
}

final gameSocketServiceProvider = Provider<GameSocketService>((ref) {
  final svc = GameSocketService(FirebaseAuth.instance);
  ref.onDispose(svc.disconnect);
  return svc;
});
