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
    _sub = channel.stream.listen(
      (data) {
        try {
          final raw = data is String ? data : (data as List<int>).toString();
          final msg = jsonDecode(raw) as Map<String, dynamic>;
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
            case 'left-room':
            case 'spectate-stopped':
            case 'game-ended':
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
      },
      onDone: () {
        _authedUid = null;
        _currentRoomId = null;
        final c = _controller;
        _controller = null;
        _channel = null;
        c?.close();
      },
    );
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

  void createRoom({int? clockMs}) {
    final message = <String, dynamic>{'type': 'create-room'};
    if (clockMs != null) message['clockMs'] = clockMs;
    send(message);
  }

  /// Step A3: enter matchmaking queue. Server pairs by ELO tolerance that
  /// widens as players wait, then creates a room automatically.
  void findMatch({int? clockMs}) {
    final message = <String, dynamic>{'type': 'find-match'};
    if (clockMs != null) message['clockMs'] = clockMs;
    send(message);
  }

  void cancelMatching() => send({'type': 'cancel-matching'});

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

  /// Step 4: send a Xiangqi move in UCI format (e.g. "e2e4").
  /// Server validates format + turn + clock + Xiangqi legality.
  void sendMove(String uci) =>
      send({'type': 'move', 'uci': uci.trim().toLowerCase()});

  /// Step 6: resign current game. Sender loses; server broadcasts `game-ended`.
  void resign() => send({'type': 'resign'});

  Future<void> disconnect() async {
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
