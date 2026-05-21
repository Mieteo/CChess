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
              _currentRoomId = msg['roomId'] as String?;
              break;
            case 'left-room':
              _currentRoomId = null;
              break;
          }
          _controller?.add(msg);
        } catch (e) {
          _controller?.addError('Parse error: $e');
        }
      },
      onError: (Object e, StackTrace st) {
        _controller?.addError(e, st);
      },
      onDone: () {
        _authedUid = null;
        _currentRoomId = null;
        _controller?.close();
        _channel = null;
        _controller = null;
      },
    );
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

  void createRoom() => send({'type': 'create-room'});

  void joinRoom(String roomId) =>
      send({'type': 'join-room', 'roomId': roomId.trim().toUpperCase()});

  void leaveRoom() => send({'type': 'leave-room'});

  void broadcast(Map<String, dynamic> payload) =>
      send({'type': 'broadcast', 'payload': payload});

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
