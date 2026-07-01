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

const int onlineDefaultMoveClockMs = 90 * 1000;

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

class OnlineActiveRoom {
  const OnlineActiveRoom({
    required this.roomId,
    required this.moveCount,
    required this.spectatorCount,
    this.mode = 'ranked',
    this.variant = 'standard',
    this.redUid,
    this.blackUid,
    this.startedAtMs,
    this.currentTurn,
    this.redClockMs,
    this.blackClockMs,
  });

  final String roomId;
  final String? redUid;
  final String? blackUid;
  final int moveCount;
  final int spectatorCount;
  final String mode;
  final String variant;
  final int? startedAtMs;
  final PieceColor? currentTurn;
  final int? redClockMs;
  final int? blackClockMs;

  static OnlineActiveRoom? fromServer(Map<String, dynamic> msg) {
    final roomId = msg['roomId'] as String?;
    if (roomId == null || roomId.isEmpty) return null;
    final turn = msg['currentTurn'] as String?;
    final clock = msg['clock'] as Map<String, dynamic>?;
    return OnlineActiveRoom(
      roomId: roomId,
      mode: msg['mode'] as String? ?? 'ranked',
      variant: msg['variant'] as String? ?? 'standard',
      redUid: msg['redUid'] as String?,
      blackUid: msg['blackUid'] as String?,
      moveCount: (msg['moveCount'] as num?)?.toInt() ?? 0,
      spectatorCount: (msg['spectatorCount'] as num?)?.toInt() ?? 0,
      startedAtMs: (msg['startedAt'] as num?)?.toInt(),
      currentTurn: turn == 'black'
          ? PieceColor.black
          : (turn == 'red' ? PieceColor.red : null),
      redClockMs: (clock?['red'] as num?)?.toInt(),
      blackClockMs: (clock?['black'] as num?)?.toInt(),
    );
  }
}

class _ClockUpdate {
  const _ClockUpdate({
    this.redClockMs,
    this.blackClockMs,
    this.currentTurn,
    required this.moveClockLimitMs,
    required this.moveClockRemainingMs,
    required this.moveClockUpdatedAtMs,
  });

  final int? redClockMs;
  final int? blackClockMs;
  final PieceColor? currentTurn;
  final int moveClockLimitMs;
  final int moveClockRemainingMs;
  final int moveClockUpdatedAtMs;
}

PieceColor? _pieceColorFromServer(Object? value) {
  if (value == 'black') return PieceColor.black;
  if (value == 'red') return PieceColor.red;
  return null;
}

_ClockUpdate _clockUpdateFromServer(
  Map<String, dynamic>? clock,
  OnlineMatchState state,
) {
  final limit =
      (clock?['moveTimeLimitMs'] as num?)?.toInt() ?? state.moveClockLimitMs;
  return _ClockUpdate(
    redClockMs: (clock?['red'] as num?)?.toInt(),
    blackClockMs: (clock?['black'] as num?)?.toInt(),
    currentTurn: _pieceColorFromServer(clock?['currentTurn']),
    moveClockLimitMs: limit,
    moveClockRemainingMs: (clock?['moveRemainingMs'] as num?)?.toInt() ?? limit,
    moveClockUpdatedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
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
    this.moveClockLimitMs = onlineDefaultMoveClockMs,
    this.moveClockRemainingMs = onlineDefaultMoveClockMs,
    this.moveClockUpdatedAtMs,
    this.currentTurn,
    this.result,
    this.endReason,
    this.errorMessage,
    this.lastEventLog = const <String>[],
    this.peerDisconnectedAtMs,
    this.peerDisconnectGraceMs,
    this.eloUpdate,
    this.chatMessages = const <OnlineChatMessage>[],
    this.activeRooms = const <OnlineActiveRoom>[],
    this.activeRoomsUpdatedAtMs,
    this.rematchOfferedByMe = false,
    this.rematchOfferedByOpponent = false,
    this.opponentLeftRoom = false,
    this.roomMode = 'ranked',
    this.variant = 'standard',
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

  /// Active board session. [XiangqiGame] for standard rooms, [CupClientGame] for
  /// Cờ Úp rooms (covers + reveals only — the client never learns hidden
  /// identities). Null until `game-start` / reconnect / spectate arrives.
  final ChessGameSession? game;
  final int redClockMs;
  final int blackClockMs;
  final int moveClockLimitMs;
  final int moveClockRemainingMs;
  final int? moveClockUpdatedAtMs;
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
  final List<OnlineActiveRoom> activeRooms;
  final int? activeRoomsUpdatedAtMs;

  /// Sprint 12 rematch: whether I have offered a rematch, and whether the
  /// opponent has offered one. When both true, server starts a new game.
  final bool rematchOfferedByMe;
  final bool rematchOfferedByOpponent;

  /// R9: the opponent left the (finished) room — server sent `peer-left`.
  /// Rematch is no longer possible; the result dialog reacts immediately
  /// instead of waiting for a rejected rematch-offer round-trip.
  final bool opponentLeftRoom;
  final String roomMode;
  final String variant;

  bool get isMyTurn => myColor != null && currentTurn == myColor;
  bool get isPlaying =>
      phase == OnlineMatchPhase.playing ||
      phase == OnlineMatchPhase.peerDisconnected;
  bool get isSpectating => phase == OnlineMatchPhase.spectating;
  bool get canChat => isPlaying || isSpectating;
  bool get isEnded => phase == OnlineMatchPhase.ended;
  bool get isCasual => roomMode == 'casual';

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
    ChessGameSession? game,
    int? redClockMs,
    int? blackClockMs,
    int? moveClockLimitMs,
    int? moveClockRemainingMs,
    int? moveClockUpdatedAtMs,
    PieceColor? currentTurn,
    String? result,
    String? endReason,
    String? errorMessage,
    List<String>? lastEventLog,
    int? peerDisconnectedAtMs,
    int? peerDisconnectGraceMs,
    Map<String, dynamic>? eloUpdate,
    List<OnlineChatMessage>? chatMessages,
    List<OnlineActiveRoom>? activeRooms,
    int? activeRoomsUpdatedAtMs,
    bool? rematchOfferedByMe,
    bool? rematchOfferedByOpponent,
    bool? opponentLeftRoom,
    String? roomMode,
    String? variant,
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
      moveClockLimitMs: moveClockLimitMs ?? this.moveClockLimitMs,
      moveClockRemainingMs: moveClockRemainingMs ?? this.moveClockRemainingMs,
      moveClockUpdatedAtMs: moveClockUpdatedAtMs ?? this.moveClockUpdatedAtMs,
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
      activeRooms: activeRooms ?? this.activeRooms,
      activeRoomsUpdatedAtMs:
          activeRoomsUpdatedAtMs ?? this.activeRoomsUpdatedAtMs,
      rematchOfferedByMe: rematchOfferedByMe ?? this.rematchOfferedByMe,
      rematchOfferedByOpponent:
          rematchOfferedByOpponent ?? this.rematchOfferedByOpponent,
      opponentLeftRoom: opponentLeftRoom ?? this.opponentLeftRoom,
      roomMode: roomMode ?? this.roomMode,
      variant: variant ?? this.variant,
    );
  }
}

/// Bridges [GameSocketService] (raw WS messages) with [XiangqiGame] (board state).
///
/// UI talks to this controller; controller mutates state in response to either
/// user actions (createRoom, sendMove, resign) or server events.
class OnlineMatchController extends StateNotifier<OnlineMatchState> {
  OnlineMatchController(this._socket, this._reconnectStore)
    : super(const OnlineMatchState()) {
    // D1 fix: the socket service notifies us when the live connection drops or
    // goes silent; if we were mid-game we auto-reconnect within the grace window.
    _socket.onConnectionLost = _handleConnectionLost;
  }

  final GameSocketService _socket;
  final ReconnectStore _reconnectStore;
  StreamSubscription<Map<String, dynamic>>? _sub;

  // D1/D2 fix: mid-game auto-reconnect bookkeeping (single-flight).
  bool _reconnecting = false;
  bool _disposed = false;
  bool _attemptInFlight = false; // inside _attemptReconnect's async setup
  bool _awaitingResponse = false; // handshake sent, awaiting reconnected/error
  Timer? _reconnectTimer; // delay before the next attempt
  Timer? _attemptTimeout; // bounds a stalled handshake
  // When set, the next 'authed' sends reconnect-room (resume) instead of
  // dropping the user back to the lobby.
  String? _pendingReconnectRoomId;

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

  void createRoom({
    int? clockMs,
    bool casual = false,
    String? variant,
    Map<String, String>? tournamentTag,
  }) {
    if (state.phase != OnlineMatchPhase.authed) {
      _setError('Chưa sẵn sàng (phase=${state.phase.name})');
      return;
    }
    _socket.createRoom(
      clockMs: clockMs,
      casual: casual,
      variant: variant,
      tournamentTag: tournamentTag,
    );
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

  /// Step A3: enter matchmaking queue. Server pairs by ELO tolerance. [variant]
  /// `cup` joins the Cờ Úp pool (own ELO bucket, never paired with standard).
  void findMatch({int? clockMs, String? variant}) {
    if (state.phase != OnlineMatchPhase.authed) {
      _setError('Chưa sẵn sàng (phase=${state.phase.name})');
      return;
    }
    _socket.findMatch(clockMs: clockMs, variant: variant);
  }

  void cancelMatching() {
    _socket.cancelMatching();
  }

  void requestActiveRooms() {
    if (state.phase != OnlineMatchPhase.authed) {
      _setError('Chưa sẵn sàng (phase=${state.phase.name})');
      return;
    }
    _socket.listActiveRooms();
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
      moveClockRemainingMs: state.moveClockLimitMs,
      moveClockUpdatedAtMs: DateTime.now().millisecondsSinceEpoch,
      clearError: true,
    );
    _socket.sendMove(move.toUci());
  }

  void resign() {
    if (!state.isPlaying) return;
    _socket.resign();
  }

  /// Sprint 12 rematch: offer to play again. Only valid once the game ended
  /// and the opponent is still connected. When both sides offer, the server
  /// starts a fresh game (colors swapped) via a new game-start event.
  void offerRematch() {
    if (state.phase != OnlineMatchPhase.ended) return;
    if (state.rematchOfferedByMe) return;
    if (state.opponentLeftRoom) {
      state = state.copyWith(
        errorMessage: 'Không thể đấu lại — đối thủ đã rời phòng.',
      );
      return;
    }
    state = state.copyWith(rematchOfferedByMe: true, clearError: true);
    _socket.offerRematch();
  }

  void declineRematch() {
    state = state.copyWith(
      rematchOfferedByMe: false,
      rematchOfferedByOpponent: false,
    );
    _socket.declineRematch();
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
    _stopReconnectLoop();
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
    _stopReconnectLoop();
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
        // D1 fix: if we're resuming a dropped game, go straight to
        // reconnect-room instead of surfacing the lobby.
        final pendingRoom = _pendingReconnectRoomId;
        if (pendingRoom != null) {
          _pendingReconnectRoomId = null;
          state = state.copyWith(
            phase: OnlineMatchPhase.reconnecting,
            myUid: msg['uid'] as String?,
            lastEventLog: newLog,
            clearError: true,
          );
          _socket.reconnectRoom(pendingRoom);
          break;
        }
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
          roomMode: msg['mode'] as String? ?? state.roomMode,
          variant: msg['variant'] as String? ?? state.variant,
          lastEventLog: newLog,
        );
        break;
      case 'room-joined':
        state = state.copyWith(
          phase: OnlineMatchPhase.waitingForPeer,
          roomId: msg['roomId'] as String?,
          roomMode: msg['mode'] as String? ?? state.roomMode,
          variant: msg['variant'] as String? ?? state.variant,
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
      case 'room-expired':
        // Waiting-room TTL: nobody joined in time, server cancelled the room.
        state = OnlineMatchState(
          phase: OnlineMatchPhase.authed,
          serverUrl: state.serverUrl,
          myUid: state.myUid,
          errorMessage:
              'Phòng đã hủy — không có đối thủ vào sau 1 phút. Hãy tạo lại.',
          lastEventLog: newLog,
        );
        _reconnectStore.clear();
        break;
      case 'active-rooms':
        _onActiveRooms(msg, newLog);
        break;
      case 'peer-joined':
        // Will be followed by game-start; just log.
        state = state.copyWith(lastEventLog: newLog);
        break;
      case 'peer-left':
        // R9: the opponent walked out of the room. After a finished game this
        // kills any rematch hope — flip the flag so the result dialog reacts
        // NOW (not on the next failed rematch-offer round-trip).
        if (state.phase == OnlineMatchPhase.ended) {
          state = state.copyWith(
            opponentLeftRoom: true,
            rematchOfferedByMe: false,
            rematchOfferedByOpponent: false,
            lastEventLog: newLog,
          );
        } else {
          state = state.copyWith(lastEventLog: newLog);
        }
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
      case 'rematch-offered':
        state = state.copyWith(
          rematchOfferedByOpponent: true,
          lastEventLog: newLog,
        );
        break;
      case 'rematch-pending':
        state = state.copyWith(rematchOfferedByMe: true, lastEventLog: newLog);
        break;
      case 'rematch-declined':
        state = state.copyWith(
          rematchOfferedByMe: false,
          rematchOfferedByOpponent: false,
          errorMessage: 'Đối thủ đã từ chối đấu lại.',
          lastEventLog: newLog,
        );
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
    // sockets share the same Firebase uid (solo testing). Spectators receive
    // rematch game-starts with yourColor == null: they must STAY read-only
    // watchers, not be promoted to "red player".
    final yourColor = msg['yourColor'] as String?;
    final watching = yourColor == null;
    final myColor = yourColor == 'black' ? PieceColor.black : PieceColor.red;
    final opponentUid = myColor == PieceColor.red ? blackUid : redUid;
    final clock = msg['clock'] as Map<String, dynamic>?;
    final clockUpdate = _clockUpdateFromServer(clock, state);
    final roomId = msg['roomId'] as String?;
    final variant = msg['variant'] as String? ?? state.variant;
    // Cờ Úp rooms get the cover-only client engine; standard rooms the plain
    // Xiangqi engine. Both implement [ChessGameSession] for the board layer.
    final ChessGameSession game = variant == 'cup'
        ? CupClientGame.initial()
        : XiangqiGame.initial();
    state = state.copyWith(
      phase: watching ? OnlineMatchPhase.spectating : OnlineMatchPhase.playing,
      roomId: roomId,
      game: game,
      roomMode: msg['mode'] as String? ?? state.roomMode,
      variant: variant,
      // copyWith ignores nulls, so a watcher keeps myColor/opponentUid null.
      myColor: watching ? null : myColor,
      opponentUid: watching ? null : opponentUid,
      redUid: redUid,
      blackUid: blackUid,
      spectatorCount: watching ? state.spectatorCount : 0,
      currentTurn: clockUpdate.currentTurn ?? PieceColor.red,
      redClockMs: clockUpdate.redClockMs ?? state.redClockMs,
      blackClockMs: clockUpdate.blackClockMs ?? state.blackClockMs,
      moveClockLimitMs: clockUpdate.moveClockLimitMs,
      moveClockRemainingMs: clockUpdate.moveClockRemainingMs,
      moveClockUpdatedAtMs: clockUpdate.moveClockUpdatedAtMs,
      lastEventLog: log,
      chatMessages: const <OnlineChatMessage>[],
      rematchOfferedByMe: false,
      rematchOfferedByOpponent: false,
      opponentLeftRoom: false,
      clearError: true,
    );
    // Persist for Step 8 reconnect (players only — watchers don't own a seat).
    if (roomId != null && !watching) _reconnectStore.save(roomId);
  }

  void _onActiveRooms(Map<String, dynamic> msg, List<String> log) {
    final rooms =
        (msg['rooms'] as List?)
            ?.whereType<Map>()
            .map(
              (m) => OnlineActiveRoom.fromServer(Map<String, dynamic>.from(m)),
            )
            .whereType<OnlineActiveRoom>()
            .toList() ??
        const <OnlineActiveRoom>[];
    state = state.copyWith(
      activeRooms: rooms,
      activeRoomsUpdatedAtMs:
          (msg['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      lastEventLog: log,
      clearError: true,
    );
  }

  /// Rebuild the active board from a reconnect/spectate snapshot. Standard rooms
  /// replay the UCI move list into a fresh game; Cờ Úp rooms can't (a UCI replay
  /// can't reconstruct revealed identities) so they rebuild from the server's
  /// cheat-safe `cup` snapshot (covers + revealed pieces + hidden squares).
  ChessGameSession _buildGameFromSnapshot(
    Map<String, dynamic> msg,
    String variant,
    PieceColor turn,
  ) {
    if (variant == 'cup') {
      final cup = msg['cup'] as Map<String, dynamic>?;
      final fen = cup?['fen'] as String?;
      if (fen != null) {
        final hidden =
            (cup?['hidden'] as List?)
                ?.whereType<num>()
                .map((n) => n.toInt())
                .toList() ??
            const <int>[];
        return CupClientGame.fromSnapshot(
          fen: fen,
          hiddenIndices: hidden,
          turn: turn,
        );
      }
      return CupClientGame.initial();
    }
    final moves =
        (msg['moves'] as List?)?.whereType<String>().toList() ?? const [];
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
    return game;
  }

  void _onReconnected(Map<String, dynamic> msg, List<String> log) {
    final redUid = msg['redUid'] as String?;
    final blackUid = msg['blackUid'] as String?;
    final yourColor = msg['yourColor'] as String?;
    final myColor = yourColor == 'black' ? PieceColor.black : PieceColor.red;
    final opponentUid = myColor == PieceColor.red ? blackUid : redUid;
    final variant = msg['variant'] as String? ?? state.variant;
    final clock = msg['clock'] as Map<String, dynamic>?;
    final clockUpdate = _clockUpdateFromServer(clock, state);
    final serverTurn = _pieceColorFromServer(msg['currentTurn']);
    final game = _buildGameFromSnapshot(
      msg,
      variant,
      serverTurn ?? clockUpdate.currentTurn ?? PieceColor.red,
    );
    final currentTurn = serverTurn ?? clockUpdate.currentTurn ?? game.turn;
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
      roomMode: msg['mode'] as String? ?? state.roomMode,
      variant: variant,
      myColor: myColor,
      opponentUid: opponentUid,
      redUid: redUid,
      blackUid: blackUid,
      spectatorCount:
          (msg['spectatorCount'] as num?)?.toInt() ?? state.spectatorCount,
      currentTurn: currentTurn,
      redClockMs: clockUpdate.redClockMs ?? state.redClockMs,
      blackClockMs: clockUpdate.blackClockMs ?? state.blackClockMs,
      moveClockLimitMs: clockUpdate.moveClockLimitMs,
      moveClockRemainingMs: clockUpdate.moveClockRemainingMs,
      moveClockUpdatedAtMs: clockUpdate.moveClockUpdatedAtMs,
      chatMessages: chat,
      lastEventLog: log,
      clearError: true,
    );
    // D1 fix: resume succeeded — tear down the reconnect loop.
    _stopReconnectLoop();
  }

  void _onSpectateStarted(Map<String, dynamic> msg, List<String> log) {
    final variant = msg['variant'] as String? ?? state.variant;
    final clock = msg['clock'] as Map<String, dynamic>?;
    final clockUpdate = _clockUpdateFromServer(clock, state);
    final serverTurn = _pieceColorFromServer(msg['currentTurn']);
    final game = _buildGameFromSnapshot(
      msg,
      variant,
      serverTurn ?? clockUpdate.currentTurn ?? PieceColor.red,
    );
    final currentTurn = serverTurn ?? clockUpdate.currentTurn ?? game.turn;
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
      roomMode: msg['mode'] as String? ?? state.roomMode,
      variant: variant,
      redUid: msg['redUid'] as String?,
      blackUid: msg['blackUid'] as String?,
      spectatorCount: (msg['spectatorCount'] as num?)?.toInt() ?? 1,
      game: game,
      redClockMs: clockUpdate.redClockMs ?? state.redClockMs,
      blackClockMs: clockUpdate.blackClockMs ?? state.blackClockMs,
      moveClockLimitMs: clockUpdate.moveClockLimitMs,
      moveClockRemainingMs: clockUpdate.moveClockRemainingMs,
      moveClockUpdatedAtMs: clockUpdate.moveClockUpdatedAtMs,
      currentTurn: currentTurn,
      lastEventLog: log,
      chatMessages: chat,
    );
  }

  void _onMoveAck(Map<String, dynamic> msg, List<String> log) {
    // Cờ Úp: my optimistically-moved piece slid as a blank cover; the ack now
    // carries its true identity, so flip the destination square face-up.
    final game = state.game;
    if (game is CupClientGame) {
      final reveal = msg['reveal'] as Map<String, dynamic>?;
      final uci = msg['uci'] as String?;
      if (reveal != null && uci != null) {
        final coords = Move.parseUciCoords(uci);
        final revealed = CupClientGame.pieceFromFenChar(
          reveal['revealed'] as String?,
        );
        if (coords != null && revealed != null) {
          game.applyReveal(coords.$2, revealed);
        }
      }
    }
    final clock = msg['clock'] as Map<String, dynamic>?;
    final clockUpdate = _clockUpdateFromServer(clock, state);
    state = state.copyWith(
      game: game,
      redClockMs: clockUpdate.redClockMs ?? state.redClockMs,
      blackClockMs: clockUpdate.blackClockMs ?? state.blackClockMs,
      currentTurn: clockUpdate.currentTurn ?? state.game?.turn,
      moveClockLimitMs: clockUpdate.moveClockLimitMs,
      moveClockRemainingMs: clockUpdate.moveClockRemainingMs,
      moveClockUpdatedAtMs: clockUpdate.moveClockUpdatedAtMs,
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
      if (game is CupClientGame) {
        // Cờ Úp: the server tells us the revealed identity (+ captured piece) so
        // we can flip the right cover. Without a reveal we can't place the true
        // piece, so fall back to the cover-as-placeholder apply.
        final reveal = msg['reveal'] as Map<String, dynamic>?;
        final revealed = CupClientGame.pieceFromFenChar(
          reveal?['revealed'] as String?,
        );
        if (revealed != null) {
          game.applyServerMove(
            coords.$1,
            coords.$2,
            revealed: revealed,
            captured: CupClientGame.pieceFromFenChar(
              reveal?['captured'] as String?,
            ),
          );
        } else {
          game.makeMove(coords.$1, coords.$2);
        }
      } else {
        game.makeMove(coords.$1, coords.$2);
      }
    } catch (_) {
      _setError('Server gửi nước trái luật cờ: $uci');
      return;
    }
    final clock = msg['clock'] as Map<String, dynamic>?;
    final clockUpdate = _clockUpdateFromServer(clock, state);
    state = state.copyWith(
      game: game,
      currentTurn: clockUpdate.currentTurn ?? game.turn,
      redClockMs: clockUpdate.redClockMs ?? state.redClockMs,
      blackClockMs: clockUpdate.blackClockMs ?? state.blackClockMs,
      moveClockLimitMs: clockUpdate.moveClockLimitMs,
      moveClockRemainingMs: clockUpdate.moveClockRemainingMs,
      moveClockUpdatedAtMs: clockUpdate.moveClockUpdatedAtMs,
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
    // D1/D2 fix: a reconnect attempt was rejected — the saved room is dead
    // (grace expired, game over, or our seat is gone). This fires for BOTH the
    // mid-game auto-reconnect AND the lobby's reconnect-on-load. In either case
    // CLEAR the stale saved room (otherwise the lobby keeps re-attaching to a
    // ghost room every time it loads) and drop back to a clean, usable lobby
    // state so the user can immediately start a new game.
    final isReconnectReject =
        code == 'room-not-found' ||
        code == 'not-disconnected-player' ||
        code == 'game-not-active' ||
        code == 'missing-room-id';
    if (isReconnectReject &&
        (_reconnecting || state.phase == OnlineMatchPhase.reconnecting)) {
      _stopReconnectLoop();
      _reconnectStore.clear();
      state = OnlineMatchState(
        phase: OnlineMatchPhase.authed,
        serverUrl: state.serverUrl,
        myUid: state.myUid,
        errorMessage: 'Ván cũ đã kết thúc hoặc hết hạn — hãy tạo ván mới.',
        lastEventLog: log,
      );
      return;
    }
    if (code == 'invalid-chat' || code == 'chat-rate-limited') {
      state = state.copyWith(
        errorMessage: code == 'invalid-chat'
            ? 'Tin nhắn không hợp lệ hoặc quá dài.'
            : 'Bạn gửi chat quá nhanh.',
        lastEventLog: log,
      );
      return;
    }
    // Sprint 12 rematch: the opponent left before a rematch could start. Keep
    // the ended screen alive (don't flip to phase=error) and reset offer flags
    // so the result dialog can show a hint instead of breaking.
    if (state.phase == OnlineMatchPhase.ended &&
        (code == 'no-opponent' ||
            code == 'rematch-failed' ||
            code == 'not-finished' ||
            code == 'not-player')) {
      state = state.copyWith(
        rematchOfferedByMe: false,
        rematchOfferedByOpponent: false,
        errorMessage: 'Không thể đấu lại — đối thủ đã rời phòng.',
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
    final clock = msg['clock'] as Map<String, dynamic>?;
    final clockUpdate = _clockUpdateFromServer(clock, state);
    state = state.copyWith(
      phase: OnlineMatchPhase.ended,
      result: msg['result'] as String?,
      endReason: msg['reason'] as String?,
      eloUpdate: msg['elo'] as Map<String, dynamic>?,
      roomMode: msg['mode'] as String? ?? state.roomMode,
      variant: msg['variant'] as String? ?? state.variant,
      redClockMs: clockUpdate.redClockMs ?? state.redClockMs,
      blackClockMs: clockUpdate.blackClockMs ?? state.blackClockMs,
      currentTurn: clockUpdate.currentTurn ?? state.currentTurn,
      moveClockLimitMs: clockUpdate.moveClockLimitMs,
      moveClockRemainingMs: clockUpdate.moveClockRemainingMs,
      moveClockUpdatedAtMs: clockUpdate.moveClockUpdatedAtMs,
      lastEventLog: log,
      clearPeerDisconnect: true,
    );
    // Game ended — no point trying to reconnect later
    _reconnectStore.clear();
  }

  // ── D1 fix: mid-game auto-reconnect ────────────────────────────────────
  /// Called by the socket service when the live connection drops or goes
  /// silent. If we were in an active game, kick off the single-flight reconnect
  /// state machine that resumes the room; otherwise surface the disconnect.
  void _handleConnectionLost() {
    if (_disposed) return;
    final inGame =
        state.isPlaying ||
        state.phase == OnlineMatchPhase.peerDisconnected ||
        state.phase == OnlineMatchPhase.reconnecting;
    if (!inGame) {
      if (state.phase != OnlineMatchPhase.error) {
        state = state.copyWith(
          phase: OnlineMatchPhase.error,
          errorMessage: 'Mất kết nối máy chủ.',
        );
      }
      return;
    }
    if (!_reconnecting) {
      _reconnecting = true;
      state = state.copyWith(
        phase: OnlineMatchPhase.reconnecting,
        clearError: true,
      );
    }
    // The socket we were on just died — any handshake we were awaiting is void.
    _awaitingResponse = false;
    _attemptTimeout?.cancel();
    _scheduleAttempt(immediate: true);
  }

  /// Hook for a connectivity listener: nudge a reconnect the instant the
  /// network returns. connectivity_plus can fire several events in a burst; the
  /// single-flight guards coalesce them into ONE attempt (the socket churn from
  /// overlapping reconnects is exactly what corrupted state in D2).
  void onNetworkAvailable() {
    if (_reconnecting && !_disposed && !_awaitingResponse) {
      _scheduleAttempt(immediate: true);
    }
  }

  void _scheduleAttempt({bool immediate = false}) {
    if (!_reconnecting || _disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      immediate ? Duration.zero : const Duration(seconds: 2),
      _attemptReconnect,
    );
  }

  void _stopReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _attemptTimeout?.cancel();
    _attemptTimeout = null;
    _reconnecting = false;
    _awaitingResponse = false;
    _pendingReconnectRoomId = null;
  }

  /// A single reconnect attempt. STRICTLY one in flight at a time: refused while
  /// the socket setup is running (`_attemptInFlight`) or while we're still
  /// waiting for the server's `reconnected`/`error` (`_awaitingResponse`).
  /// Retries are driven by drops + the handshake timeout — never a blind
  /// periodic timer — so overlapping `disconnect/connect` cycles can't race the
  /// server (which previously left the board reset to the start + the room
  /// stuck "playing").
  Future<void> _attemptReconnect() async {
    if (!_reconnecting || _disposed || _attemptInFlight || _awaitingResponse) {
      return;
    }
    _attemptInFlight = true;
    try {
      // Mid-game: use the raw saved room id (NOT readFresh's 70s window — that
      // gate is only for relaunch). The server's 60s grace is the real bound;
      // if it expired the server rejects with room-not-found/
      // not-disconnected-player, handled in _onError.
      final saved = await _reconnectStore.readRoomId();
      if (saved == null) {
        _stopReconnectLoop();
        state = state.copyWith(
          phase: OnlineMatchPhase.error,
          errorMessage: 'Mất kết nối — không có ván để vào lại.',
        );
        return;
      }
      final url = state.serverUrl;
      if (url == null) {
        _scheduleAttempt();
        return;
      }
      _pendingReconnectRoomId = saved;
      await _socket.disconnect();
      await _socket.connect(url);
      _sub?.cancel();
      _sub = _socket.messages.listen(_onMessage, onError: _onStreamError);
      await _socket.authenticate();
      // Handshake initiated → wait for authed → reconnect-room → reconnected.
      // Arm a timeout so a stalled/offline handshake retries instead of hanging.
      _awaitingResponse = true;
      _attemptTimeout?.cancel();
      _attemptTimeout = Timer(const Duration(seconds: 8), () {
        _awaitingResponse = false;
        _scheduleAttempt();
      });
    } catch (_) {
      // Setup threw (likely still offline) — retry after a short delay.
      _scheduleAttempt();
    } finally {
      _attemptInFlight = false;
    }
  }

  void _onStreamError(Object err) {
    // D1 fix: during auto-reconnect, transient stream errors are expected while
    // the network is down — don't clobber the 'reconnecting' phase.
    if (_reconnecting) return;
    _setError('Stream: $err');
  }

  void _setError(String msg) {
    state = state.copyWith(phase: OnlineMatchPhase.error, errorMessage: msg);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _attemptTimeout?.cancel();
    _socket.onConnectionLost = null;
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

/// D1 fix: true while the pushed online game screen is mounted. The lobby reads
/// this before pushing the game route so a mid-game reconnect (which transitions
/// the phase back to `playing` while the screen is already on the navigator
/// stack) doesn't push a SECOND copy. The relaunch-from-lobby reconnect still
/// pushes normally because the screen isn't mounted yet at that point.
final onlineGameOpenProvider = StateProvider<bool>((ref) => false);
