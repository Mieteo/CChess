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

  Stream<Map<String, dynamic>> get messages =>
      _controller?.stream ?? const Stream.empty();
  String? get authedUid => _authedUid;
  bool get isConnected => _channel != null;
  bool get isAuthed => _authedUid != null;

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
          if (msg['type'] == 'authed') {
            _authedUid = msg['uid'] as String?;
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

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _authedUid = null;
    await _controller?.close();
    _controller = null;
  }
}

final gameSocketServiceProvider = Provider<GameSocketService>((ref) {
  final svc = GameSocketService(FirebaseAuth.instance);
  ref.onDispose(svc.disconnect);
  return svc;
});
