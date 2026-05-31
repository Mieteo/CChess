import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/services/game_socket_service.dart';
import '../../data/services/reconnect_store.dart';

enum OnlineMatchPhase {
  idle,
  connecting,
  authed,

  /// Step A3: in matchmaking queue, waiting to be paired.
  matching,
  waitingForPeer,
  playing,
  spectating,

  /// Step 8: opponent disconnected, waiting for them to reconnect.
  /// Game is still alive on server; will auto-resume if they come back.
  peerDisconnected,

  /// Step 8: I just attempted reconnect-room and am waiting for snapshot.
  reconnecting,
  ended,
  error,
}

class OnlineChatMessage {
  const OnlineChatMessage({
    required this.id,
    required this.fromUid,
    required this.text,
    required this.sentAtMs,
  });

  final String id;
  final String fromUid;
  final String text;
  final int sentAtMs;

  static OnlineChatMessage? fromServer(Map<String, dynamic> msg) {
    final id = msg['id'] as String?;
    final from = msg['from'] as String?;
    final text = msg['text'] as String?;
    final ts = (msg['ts'] as num?)?.toInt();
    if (id == null || from == null || text == null || ts == null) {
      return null;
    }
    return OnlineChatMessage(id: id, fromUid: from, text: text, sentAtMs: ts);
  }
}

class OnlineMatchState {
  const OnlineMatchState({
    this.phase = OnlineMatchPhase.idle,
    this.serverUrl,
    this.roomId,
    this.myUid,
    this.myColor,
    this.opponentUid,
    this.redUid,
    this.blackUid,
    this.spectatorCount = 0,
    this.game,
    this.redClockMs = 30000,
    this.blackClockMs = 30000,
    this.currentTurn,
    this.result,
    this.endReason,
    this.errorMessage,
    this.lastEventLog = const <String>[],
    this.peerDisconnectedAtMs,
    this.peerDisconnectGraceMs,
    this.eloUpdate,
    this.chatMessages = const <OnlineChatMessage>[],
  });

  final OnlineMatchPhase phase;
  final String? serverUrl;
  final String? roomId;
  final String? myUid;
  final PieceColor? myColor;
  final String? opponentUid;
  final String? redUid;
  final String? blackUid;
  final int spectatorCount;
  final XiangqiGame? game;
  final int redClockMs;
  final int blackClockMs;
  final PieceColor? currentTurn;
  final String? result; // 'red-win' | 'black-win' | 'draw'
  final String? endReason; // 'timeout' | 'resign' | 'disconnect'
  final String? errorMessage;
  final List<String> lastEventLog;

  /// Step 8: timestamp when peer disconnect was received (local ms).
  /// Combined with [peerDisconnectGraceMs] gives the countdown deadline.
  final int? peerDisconnectedAtMs;
  final int? peerDisconnectGraceMs;

  /// Step A2: Elo change after game-ended. Shape:
  ///   { 'red': {old, new, delta}, 'black': {old, new, delta} }
  /// Null when server didn't (yet) compute ELO (vd persist failed).
  final Map<String, dynamic>? eloUpdate;
  final List<OnlineChatMessage> chatMessages;

  bool get isMyTurn => myColor != null && currentTurn == myColor;
  bool get isPlaying =>
      phase == OnlineMatchPhase.playing ||
      phase == OnlineMatchPhase.peerDisconnected;
  bool get isSpectating => phase == OnlineMatchPhase.spectating;
  bool get canChat => isPlaying || isSpectating;
  bool get isEnded => phase == OnlineMatchPhase.ended;

  OnlineMatchState copyWith({
    OnlineMatchPhase? phase,
    String? serverUrl,
    String? roomId,
    String? myUid,
    PieceColor? myColor,
    String? opponentUid,
    String? redUid,
    String? blackUid,
    int? spectatorCount,
    XiangqiGame? game,
    int? redClockMs,
    int? blackClockMs,
    PieceColor? currentTurn,
    String? result,
    String? endReason,
    String? errorMessage,
    List<String>? lastEventLog,
    int? peerDisconnectedAtMs,
    int? peerDisconnectGraceMs,
    Map<String, dynamic>? eloUpdate,
    List<OnlineChatMessage>? chatMessages,
    bool clearError = false,
    bool clearPeerDisconnect = false,
  }) {
    return OnlineMatchState(
      phase: phase ?? this.phase,
      serverUrl: serverUrl ?? this.serverUrl,
      roomId: roomId ?? this.roomId,
      myUid: myUid ?? this.myUid,
      myColor: myColor ?? this.myColor,
      opponentUid: opponentUid ?? this.opponentUid,
      redUid: redUid ?? this.redUid,
      blackUid: blackUid ?? this.blackUid,
      spectatorCount: spectatorCount ?? this.spectatorCount,
      game: game ?? this.game,
      redClockMs: redClockMs ?? this.redClockMs,
      blackClockMs: blackClockMs ?? this.blackClockMs,
      currentTurn: currentTurn ?? this.currentTurn,
      result: result ?? this.result,
      endReason: endReason ?? this.endReason,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastEventLog: lastEventLog ?? this.lastEventLog,
      peerDisconnectedAtMs: clearPeerDisconnect
          ? null
          : (peerDisconnectedAtMs ?? this.peerDisconnectedAtMs),
      peerDisconnectGraceMs: clearPeerDisconnect
          ? null
          : (peerDisconnectGraceMs ?? this.peerDisconnectGraceMs),
      eloUpdate: eloUpdate ?? this.eloUpdate,
      chatMessages: chatMessages ?? this.chatMessages,
    );
  }
}

/// Bridges [GameSocketService] (raw WS messages) with [XiangqiGame] (board state).
///
/// UI talks to this controller; controller mutates state in response to either
/// user actions (createRoom, sendMove, resign) or server events.
class OnlineMatchController extends StateNotifier<OnlineMatchState> {
  OnlineMatchController(this._socket, this._reconnectStore)
    : super(const OnlineMatchState());

  final GameSocketService _socket;
  final ReconnectStore _reconnectStore;
  StreamSubscription<Map<String, dynamic>>? _sub;

  Future<void> connect(String url) async {
    try {
      state = state.copyWith(
        phase: OnlineMatchPhase.connecting,
        serverUrl: url,
        clearError: true,
      );
      await _socket.disconnect();
      await _socket.connect(url);
      _sub?.cancel();
      _sub = _socket.messages.listen(_onMessage, onError: _onStreamError);
      await _socket.authenticate();
      // Auth response handled in _onMessage when 'authed' arrives.
    } catch (e) {
      state = state.copyWith(
        phase: OnlineMatchPhase.error,
        errorMessage: 'Connect/auth failed: $e',
      );
    }
  }

  void createRoom({int? clockMs}) {
    if (state.phase != OnlineMatchPhase.authed) {
      _setError('Chưa sẵn sàng (phase=${state.phase.name})');
      return;
    }
    _socket.createRoom(clockMs: clockMs);
  }

  void joinRoom(String roomId) {
    if (state.phase != OnlineMatchPhase.authed) {
      _setError('Chưa sẵn sàng (phase=${state.phase.name})');
      return;
    }
    _socket.joinRoom(roomId);
  }

  void spectateRoom(String roomId) {
    if (state.phase != OnlineMatchPhase.authed) {
      _setError('Chưa sẵn sàng (phase=${state.phase.name})');
      return;
    }
    _socket.spectateRoom(roomId);
  }

  /// Step 8: attempt to resume a saved room. Lobby calls this on load if
  /// `ReconnectStore.readFresh()` returned a value.
  void reconnectRoom(String roomId) {
    if (state.phase != OnlineMatchPhase.authed) {
      _setError('Chưa sẵn sàng (phase=${state.phase.name})');
      return;
    }
    state = state.copyWith(phase: OnlineMatchPhase.reconnecting);
    _socket.reconnectRoom(roomId);
  }

  /// Convenience: read the freshly-saved room id and try to reconnect.
  /// Returns true if a reconnect attempt was issued, false if no fresh
  /// state was found.
  Future<bool> tryAutoReconnect() async {
    final saved = await _reconnectStore.readFresh();
    if (saved == null) return false;
    reconnectRoom(saved);
    return true;
  }

  /// Step A3: enter matchmaking queue. Server pairs by ELO tolerance.
  void findMatch({int? clockMs}) {
    if (state.phase != OnlineMatchPhase.authed) {
      _setError('Chưa sẵn sàng (phase=${state.phase.name})');
      return;
    }
    _socket.findMatch(clockMs: clockMs);
  }

  void cancelMatching() {
    _socket.cancelMatching();
  }

  /// Called by UI when user taps from→to. Validates locally via XiangqiGame,
  /// applies optimistically, sends to server. Server may reject (wrong turn,
  /// timeout) — we'll roll back if so.
  void attemptMove(Position from, Position to) {
    final game = state.game;
    if (game == null) return;
    if (!state.isMyTurn) {
      _setError('Chưa tới lượt bạn');
      return;
    }
    if (!game.isValidMove(from, to)) {
      _setError('Nước không hợp lệ');
      return;
    }
    final move = game.makeMove(from, to);
    state = state.copyWith(
      game: game,
      currentTurn: game.turn,
      clearError: true,
    );
    _socket.sendMove(move.toUci());
  }

  void resign() {
    if (!state.isPlaying) return;
    _socket.resign();
  }

  void sendChatMessage(String text) {
    if (!state.canChat) return;
    final trimmed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 120) {
      state = state.copyWith(errorMessage: 'Tin nhắn tối đa 120 ký tự.');
      return;
    }
    _socket.sendChatMessage(trimmed);
  }

  /// User-initiated leave. Clears persistent reconnect state — they've
  /// explicitly chosen to abandon the match. Use this for "Về Đối Đầu" etc.
  Future<void> leave() async {
    _sub?.cancel();
    _sub = null;
    if (_socket.isInRoom) {
      if (state.isSpectating) {
        _socket.stopSpectating();
      } else if (!state.isPlaying) {
        _socket.leaveRoom();
      }
    }
    await _socket.disconnect();
    await _reconnectStore.clear();
    state = const OnlineMatchState();
  }

  /// Soft-leave for lifecycle backgrounding: disconnect socket but KEEP
  /// the persistent room id so the next app launch can attempt reconnect.
  Future<void> disconnectKeepingReconnectState() async {
    _sub?.cancel();
    _sub = null;
    await _socket.disconnect();
    state = const OnlineMatchState();
  }

  // ───────────────── server event handlers ─────────────────

  void _onMessage(Map<String, dynamic> msg) {
    final logEntry = msg.toString();
    final newLog = [logEntry, ...state.lastEventLog].take(20).toList();

    switch (msg['type']) {
      case 'authed':
        state = state.copyWith(
          phase: OnlineMatchPhase.authed,
          myUid: msg['uid'] as String?,
          lastEventLog: newLog,
          clearError: true,
        );
        break;
      case 'room-created':
        state = state.copyWith(
          phase: OnlineMatchPhase.waitingForPeer,
          roomId: msg['roomId'] as String?,
          lastEventLog: newLog,
        );
        break;
      case 'room-joined':
        state = state.copyWith(
          phase: OnlineMatchPhase.waitingForPeer,
          roomId: msg['roomId'] as String?,
          lastEventLog: newLog,
        );
        break;
      case 'matching':
        state = state.copyWith(
          phase: OnlineMatchPhase.matching,
          lastEventLog: newLog,
        );
        break;
      case 'match-found':
        // Server đã add socket vào room. game-start sẽ tới ngay sau.
        state = state.copyWith(
          phase: OnlineMatchPhase.waitingForPeer,
          roomId: msg['roomId'] as String?,
          opponentUid: msg['opponent'] as String?,
          lastEventLog: newLog,
        );
        break;
      case 'matching-canceled':
        state = state.copyWith(
          phase: OnlineMatchPhase.authed,
          lastEventLog: newLog,
        );
        break;
      case 'peer-joined':
        // Will be followed by game-start; just log.
        state = state.copyWith(lastEventLog: newLog);
        break;
      case 'game-start':
        _onGameStart(msg, newLog);
        break;
      case 'spectate-started':
        _onSpectateStarted(msg, newLog);
        break;
      case 'spectate-stopped':
        state = OnlineMatchState(
          phase: OnlineMatchPhase.authed,
          serverUrl: state.serverUrl,
          myUid: state.myUid,
          lastEventLog: newLog,
        );
        break;
      case 'spectator-joined':
      case 'spectator-left':
        state = state.copyWith(
          spectatorCount:
              (msg['spectatorCount'] as num?)?.toInt() ?? state.spectatorCount,
          lastEventLog: newLog,
        );
        break;
      case 'move-ack':
        _onMoveAck(msg, newLog);
        break;
      case 'opponent-move':
        _onOpponentMove(msg, newLog);
        break;
      case 'chat-message':
        _onChatMessage(msg, newLog);
        break;
      case 'game-ended':
        _onGameEnded(msg, newLog);
        break;
      case 'peer-disconnected':
        if (state.isSpectating) {
          state = state.copyWith(lastEventLog: newLog);
        } else {
          state = state.copyWith(
            phase: OnlineMatchPhase.peerDisconnected,
            peerDisconnectedAtMs: DateTime.now().millisecondsSinceEpoch,
            peerDisconnectGraceMs: (msg['graceMs'] as num?)?.toInt() ?? 60000,
            lastEventLog: newLog,
          );
        }
        break;
      case 'peer-reconnected':
        state = state.copyWith(
          phase: state.isSpectating
              ? OnlineMatchPhase.spectating
              : OnlineMatchPhase.playing,
          lastEventLog: newLog,
          clearError: true,
          clearPeerDisconnect: true,
        );
        break;
      case 'reconnected':
        _onReconnected(msg, newLog);
        break;
      case 'error':
        _onError(msg, newLog);
        break;
      default:
        state = state.copyWith(lastEventLog: newLog);
    }
  }

  void _onGameStart(Map<String, dynamic> msg, List<String> log) {
    final redUid = msg['redUid'] as String?;
    final blackUid = msg['blackUid'] as String?;
    // Server sends `yourColor` per-socket — authoritative even when both
    // sockets share the same Firebase uid (solo testing).
    final yourColor = msg['yourColor'] as String?;
    final myColor = yourColor == 'black' ? PieceColor.black : PieceColor.red;
    final opponentUid = myColor == PieceColor.red ? blackUid : redUid;
    final clock = msg['clock'] as Map<String, dynamic>?;
    final roomId = msg['roomId'] as String?;
    state = state.copyWith(
      phase: OnlineMatchPhase.playing,
      roomId: roomId,
      game: XiangqiGame.initial(),
      myColor: myColor,
      opponentUid: opponentUid,
      redUid: redUid,
      blackUid: blackUid,
      spectatorCount: 0,
      currentTurn: PieceColor.red,
      redClockMs: (clock?['red'] as num?)?.toInt() ?? state.redClockMs,
      blackClockMs: (clock?['black'] as num?)?.toInt() ?? state.blackClockMs,
      lastEventLog: log,
      chatMessages: const <OnlineChatMessage>[],
      clearError: true,
    );
    // Persist for Step 8 reconnect
    if (roomId != null) _reconnectStore.save(roomId);
  }

  void _onReconnected(Map<String, dynamic> msg, List<String> log) {
    final redUid = msg['redUid'] as String?;
    final blackUid = msg['blackUid'] as String?;
    final yourColor = msg['yourColor'] as String?;
    final myColor = yourColor == 'black' ? PieceColor.black : PieceColor.red;
    final opponentUid = myColor == PieceColor.red ? blackUid : redUid;
    final moves =
        (msg['moves'] as List?)?.whereType<String>().toList() ?? const [];
    // Replay moves into a fresh game.
    final game = XiangqiGame.initial();
    for (final uci in moves) {
      final coords = Move.parseUciCoords(uci);
      if (coords == null) continue;
      try {
        game.makeMove(coords.$1, coords.$2);
      } catch (_) {
        break; // server gave us inconsistent move list — bail to avoid divergence
      }
    }
    final clock = msg['clock'] as Map<String, dynamic>?;
    final currentTurnStr = msg['currentTurn'] as String?;
    final currentTurn = currentTurnStr == 'black'
        ? PieceColor.black
        : (currentTurnStr == 'red' ? PieceColor.red : game.turn);
    final chat =
        (msg['chat'] as List?)
            ?.whereType<Map>()
            .map(
              (m) => OnlineChatMessage.fromServer(Map<String, dynamic>.from(m)),
            )
            .whereType<OnlineChatMessage>()
            .toList() ??
        const <OnlineChatMessage>[];
    state = state.copyWith(
      phase: OnlineMatchPhase.playing,
      roomId: msg['roomId'] as String?,
      game: game,
      myColor: myColor,
      opponentUid: opponentUid,
      redUid: redUid,
      blackUid: blackUid,
      spectatorCount:
          (msg['spectatorCount'] as num?)?.toInt() ?? state.spectatorCount,
      currentTurn: currentTurn,
      redClockMs: (clock?['red'] as num?)?.toInt() ?? state.redClockMs,
      blackClockMs: (clock?['black'] as num?)?.toInt() ?? state.blackClockMs,
      chatMessages: chat,
      lastEventLog: log,
      clearError: true,
    );
  }

  void _onSpectateStarted(Map<String, dynamic> msg, List<String> log) {
    final moves =
        (msg['moves'] as List?)?.whereType<String>().toList() ?? const [];
    final game = XiangqiGame.initial();
    for (final uci in moves) {
      final coords = Move.parseUciCoords(uci);
      if (coords == null) continue;
      try {
        game.makeMove(coords.$1, coords.$2);
      } catch (_) {
        break;
      }
    }
    final clock = msg['clock'] as Map<String, dynamic>?;
    final currentTurnStr = msg['currentTurn'] as String?;
    final currentTurn = currentTurnStr == 'black'
        ? PieceColor.black
        : (currentTurnStr == 'red' ? PieceColor.red : game.turn);
    final chat =
        (msg['chat'] as List?)
            ?.whereType<Map>()
            .map(
              (m) => OnlineChatMessage.fromServer(Map<String, dynamic>.from(m)),
            )
            .whereType<OnlineChatMessage>()
            .toList() ??
        const <OnlineChatMessage>[];

    state = OnlineMatchState(
      phase: OnlineMatchPhase.spectating,
      serverUrl: state.serverUrl,
      roomId: msg['roomId'] as String?,
      myUid: state.myUid,
      redUid: msg['redUid'] as String?,
      blackUid: msg['blackUid'] as String?,
      spectatorCount: (msg['spectatorCount'] as num?)?.toInt() ?? 1,
      game: game,
      redClockMs: (clock?['red'] as num?)?.toInt() ?? state.redClockMs,
      blackClockMs: (clock?['black'] as num?)?.toInt() ?? state.blackClockMs,
      currentTurn: currentTurn,
      lastEventLog: log,
      chatMessages: chat,
    );
  }

  void _onMoveAck(Map<String, dynamic> msg, List<String> log) {
    final clock = msg['clock'] as Map<String, dynamic>?;
    state = state.copyWith(
      redClockMs: (clock?['red'] as num?)?.toInt() ?? state.redClockMs,
      blackClockMs: (clock?['black'] as num?)?.toInt() ?? state.blackClockMs,
      currentTurn: state.game?.turn,
      lastEventLog: log,
    );
  }

  void _onOpponentMove(Map<String, dynamic> msg, List<String> log) {
    final uci = msg['uci'] as String?;
    final game = state.game;
    if (uci == null || game == null) {
      state = state.copyWith(lastEventLog: log);
      return;
    }
    final coords = Move.parseUciCoords(uci);
    if (coords == null) {
      state = state.copyWith(lastEventLog: log);
      return;
    }
    try {
      game.makeMove(coords.$1, coords.$2);
    } catch (_) {
      _setError('Server gửi nước trái luật cờ: $uci');
      return;
    }
    final clock = msg['clock'] as Map<String, dynamic>?;
    state = state.copyWith(
      game: game,
      currentTurn: game.turn,
      redClockMs: (clock?['red'] as num?)?.toInt() ?? state.redClockMs,
      blackClockMs: (clock?['black'] as num?)?.toInt() ?? state.blackClockMs,
      lastEventLog: log,
    );
  }

  void _onChatMessage(Map<String, dynamic> msg, List<String> log) {
    final roomId = msg['roomId'] as String?;
    if (roomId != null && state.roomId != null && roomId != state.roomId) {
      state = state.copyWith(lastEventLog: log);
      return;
    }
    final message = OnlineChatMessage.fromServer(msg);
    if (message == null) {
      state = state.copyWith(lastEventLog: log);
      return;
    }
    final exists = state.chatMessages.any((m) => m.id == message.id);
    final next = exists
        ? state.chatMessages
        : <OnlineChatMessage>[...state.chatMessages, message];
    final trimmed = next.length > 50 ? next.sublist(next.length - 50) : next;
    state = state.copyWith(
      chatMessages: trimmed,
      lastEventLog: log,
      clearError: true,
    );
  }

  /// Handle server `error` messages. When the error indicates server REJECTED
  /// our optimistic move (`illegal-move`, `not-your-turn`, `time-out`), roll
  /// back the local game state so client and server stay in sync.
  void _onError(Map<String, dynamic> msg, List<String> log) {
    final code = msg['code'] as String?;
    if (code == 'invalid-chat' || code == 'chat-rate-limited') {
      state = state.copyWith(
        errorMessage: code == 'invalid-chat'
            ? 'Tin nhắn không hợp lệ hoặc quá dài.'
            : 'Bạn gửi chat quá nhanh.',
        lastEventLog: log,
      );
      return;
    }
    final shouldUndo = code == 'illegal-move' || code == 'not-your-turn';
    final game = state.game;
    if (shouldUndo && game != null) {
      final undone = game.undoMove();
      if (undone != null) {
        state = state.copyWith(
          currentTurn: game.turn,
          errorMessage: code == 'illegal-move'
              ? 'Server từ chối nước (trái luật) — đã rollback.'
              : 'Server báo chưa tới lượt — đã rollback.',
          lastEventLog: log,
        );
        return;
      }
    }
    _setError('${msg['code']} ${msg['message'] ?? ''}'.trim());
    state = state.copyWith(lastEventLog: log);
  }

  void _onGameEnded(Map<String, dynamic> msg, List<String> log) {
    state = state.copyWith(
      phase: OnlineMatchPhase.ended,
      result: msg['result'] as String?,
      endReason: msg['reason'] as String?,
      eloUpdate: msg['elo'] as Map<String, dynamic>?,
      lastEventLog: log,
      clearPeerDisconnect: true,
    );
    // Game ended — no point trying to reconnect later
    _reconnectStore.clear();
  }

  void _onStreamError(Object err) {
    _setError('Stream: $err');
  }

  void _setError(String msg) {
    state = state.copyWith(phase: OnlineMatchPhase.error, errorMessage: msg);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final onlineMatchControllerProvider =
    StateNotifierProvider<OnlineMatchController, OnlineMatchState>((ref) {
      return OnlineMatchController(
        ref.read(gameSocketServiceProvider),
        ref.read(reconnectStoreProvider),
      );
    });
