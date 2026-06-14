import 'dart:async';

import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/data/services/game_socket_service.dart';
import 'package:cchess/data/services/reconnect_store.dart';
import 'package:cchess/presentation/online/online_match_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for [GameSocketService]. We drive server events through
/// [emit] and record every outgoing command type in [sentTypes]. Only the
/// members the controller actually touches are implemented; anything else
/// falls through to [noSuchMethod] and would throw loudly if hit.
class FakeGameSocketService implements GameSocketService {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<String> sentTypes = <String>[];

  @override
  void Function()? onConnectionLost;

  void emit(Map<String, dynamic> msg) => _controller.add(msg);
  Future<void> close() => _controller.close();

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  Future<void> connect(String url) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> authenticate() async {}

  @override
  bool get isInRoom => false;

  @override
  void createRoom({int? clockMs}) => sentTypes.add('create-room');
  @override
  void findMatch({int? clockMs}) => sentTypes.add('find-match');
  @override
  void cancelMatching() => sentTypes.add('cancel-matching');
  @override
  void listActiveRooms() => sentTypes.add('list-active-rooms');
  @override
  void joinRoom(String roomId) => sentTypes.add('join-room');
  @override
  void spectateRoom(String roomId) => sentTypes.add('spectate-room');
  @override
  void stopSpectating() => sentTypes.add('stop-spectating');
  @override
  void reconnectRoom(String roomId) => sentTypes.add('reconnect-room');
  @override
  void leaveRoom() => sentTypes.add('leave-room');
  @override
  void sendChatMessage(String text) => sentTypes.add('chat-message');
  @override
  void offerRematch() => sentTypes.add('rematch-offer');
  @override
  void declineRematch() => sentTypes.add('rematch-decline');
  @override
  void sendMove(String uci) => sentTypes.add('move:$uci');
  @override
  void resign() => sentTypes.add('resign');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Avoids SharedPreferences by keeping the saved room id in memory.
class FakeReconnectStore extends ReconnectStore {
  String? saved;

  @override
  Future<void> save(String roomId) async => saved = roomId;
  @override
  Future<void> clear() async => saved = null;
  @override
  Future<String?> readFresh() async => saved;
}

void main() {
  late FakeGameSocketService socket;
  late FakeReconnectStore store;
  late OnlineMatchController ctrl;

  // Let pending stream events + microtasks flush before asserting.
  Future<void> pump() => Future<void>.delayed(Duration.zero);

  Future<void> driveToPlaying({PieceColor myColor = PieceColor.red}) async {
    socket.emit({
      'type': 'game-start',
      'roomId': 'ROOM01',
      'redUid': 'red-uid',
      'blackUid': 'black-uid',
      'yourColor': myColor == PieceColor.red ? 'red' : 'black',
      'clock': {'red': 600000, 'black': 600000},
    });
    await pump();
  }

  Future<void> driveToEnded() async {
    await driveToPlaying();
    socket.emit({
      'type': 'game-ended',
      'result': 'red-win',
      'reason': 'checkmate',
      'elo': {
        'red': {'old': 1000, 'new': 1016, 'delta': 16},
        'black': {'old': 1000, 'new': 984, 'delta': -16},
      },
    });
    await pump();
  }

  setUp(() async {
    socket = FakeGameSocketService();
    store = FakeReconnectStore();
    ctrl = OnlineMatchController(socket, store);
    await ctrl.connect('ws://fake');
    socket.emit({'type': 'authed', 'uid': 'me'});
    await pump();
  });

  tearDown(() async {
    ctrl.dispose();
    await socket.close();
  });

  group('rematch flow', () {
    test('offerRematch marks me offered and sends rematch-offer', () async {
      await driveToEnded();

      ctrl.offerRematch();

      expect(ctrl.state.rematchOfferedByMe, isTrue);
      expect(socket.sentTypes, contains('rematch-offer'));
    });

    test('offerRematch is a no-op before the game ends', () async {
      await driveToPlaying();

      ctrl.offerRematch();

      expect(ctrl.state.rematchOfferedByMe, isFalse);
      expect(socket.sentTypes, isNot(contains('rematch-offer')));
    });

    test('rematch-offered from server marks opponent as offered', () async {
      await driveToEnded();

      socket.emit({'type': 'rematch-offered', 'from': 'black-uid'});
      await pump();

      expect(ctrl.state.rematchOfferedByOpponent, isTrue);
    });

    test('rematch-declined clears both flags and surfaces a message', () async {
      await driveToEnded();
      ctrl.offerRematch();

      socket.emit({'type': 'rematch-declined', 'from': 'black-uid'});
      await pump();

      expect(ctrl.state.rematchOfferedByMe, isFalse);
      expect(ctrl.state.rematchOfferedByOpponent, isFalse);
      expect(ctrl.state.errorMessage, isNotNull);
    });

    test('fresh game-start (rematch) resumes playing and resets flags',
        () async {
      await driveToEnded();
      ctrl.offerRematch();
      socket.emit({'type': 'rematch-offered', 'from': 'black-uid'});
      await pump();

      // Both offered → server restarts with colors swapped.
      socket.emit({
        'type': 'game-start',
        'roomId': 'ROOM01',
        'redUid': 'black-uid',
        'blackUid': 'red-uid',
        'yourColor': 'black',
        'clock': {'red': 600000, 'black': 600000},
        'rematch': true,
      });
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.playing);
      expect(ctrl.state.myColor, PieceColor.black);
      expect(ctrl.state.rematchOfferedByMe, isFalse);
      expect(ctrl.state.rematchOfferedByOpponent, isFalse);
    });

    test('rematch rejection error keeps phase ended (no crash to error)',
        () async {
      await driveToEnded();
      ctrl.offerRematch();

      socket.emit({'type': 'error', 'code': 'no-opponent'});
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.ended);
      expect(ctrl.state.rematchOfferedByMe, isFalse);
      expect(ctrl.state.errorMessage, isNotNull);
    });
  });

  group('R9 — opponent left the finished room', () {
    test('peer-left while ended flips opponentLeftRoom and clears offers',
        () async {
      await driveToEnded();
      ctrl.offerRematch(); // I'm already waiting for a rematch…
      expect(ctrl.state.rematchOfferedByMe, isTrue);

      socket.emit({'type': 'peer-left', 'uid': 'black-uid'});
      await pump();

      expect(ctrl.state.opponentLeftRoom, isTrue);
      expect(ctrl.state.rematchOfferedByMe, isFalse);
      expect(ctrl.state.rematchOfferedByOpponent, isFalse);
      expect(ctrl.state.phase, OnlineMatchPhase.ended); // dialog stays up
    });

    test('offerRematch after peer-left fails locally without a round-trip',
        () async {
      await driveToEnded();
      socket.emit({'type': 'peer-left', 'uid': 'black-uid'});
      await pump();

      ctrl.offerRematch();

      expect(socket.sentTypes, isNot(contains('rematch-offer')));
      expect(ctrl.state.errorMessage, isNotNull);
    });

    test('peer-left outside the ended phase is just logged', () async {
      await driveToPlaying();

      socket.emit({'type': 'peer-left', 'uid': 'black-uid'});
      await pump();

      expect(ctrl.state.opponentLeftRoom, isFalse);
      expect(ctrl.state.phase, OnlineMatchPhase.playing);
    });

    test('a fresh game-start resets opponentLeftRoom', () async {
      await driveToEnded();
      socket.emit({'type': 'peer-left', 'uid': 'black-uid'});
      await pump();
      expect(ctrl.state.opponentLeftRoom, isTrue);

      await driveToPlaying();

      expect(ctrl.state.opponentLeftRoom, isFalse);
    });
  });

  group('spectator + waiting-room lifecycle', () {
    Future<void> driveToSpectating() async {
      socket.emit({
        'type': 'spectate-started',
        'roomId': 'ROOM01',
        'redUid': 'red-uid',
        'blackUid': 'black-uid',
        'moves': <String>[],
        'chat': <Map<String, dynamic>>[],
        'currentTurn': 'red',
        'clock': {'red': 600000, 'black': 600000},
        'spectatorCount': 1,
      });
      await pump();
    }

    test('rematch game-start keeps a spectator read-only', () async {
      await driveToSpectating();
      expect(ctrl.state.phase, OnlineMatchPhase.spectating);

      socket.emit({
        'type': 'game-ended',
        'result': 'red-win',
        'reason': 'checkmate',
      });
      await pump();
      expect(ctrl.state.phase, OnlineMatchPhase.ended);

      // Players rematch → server sends game-start with yourColor == null to
      // spectators. The watcher must resume SPECTATING, never become "red".
      socket.emit({
        'type': 'game-start',
        'roomId': 'ROOM01',
        'redUid': 'black-uid',
        'blackUid': 'red-uid',
        'yourColor': null,
        'clock': {'red': 600000, 'black': 600000},
        'rematch': true,
      });
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.spectating);
      expect(ctrl.state.myColor, isNull);
      expect(ctrl.state.game!.history, isEmpty);
      expect(store.saved, isNull, reason: 'watchers must not save reconnect state');
    });

    test('room-expired returns the creator to the lobby with a message',
        () async {
      socket.emit({'type': 'room-created', 'roomId': 'ROOM02'});
      await pump();
      expect(ctrl.state.phase, OnlineMatchPhase.waitingForPeer);

      socket.emit({'type': 'room-expired', 'roomId': 'ROOM02'});
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.authed);
      expect(ctrl.state.roomId, isNull);
      expect(ctrl.state.errorMessage, isNotNull);
    });
  });

  group('core game flow', () {
    test('game-ended sets result/reason and clears the reconnect store',
        () async {
      await driveToPlaying();
      expect(store.saved, 'ROOM01'); // game-start persisted it

      socket.emit({
        'type': 'game-ended',
        'result': 'black-win',
        'reason': 'timeout',
      });
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.ended);
      expect(ctrl.state.result, 'black-win');
      expect(ctrl.state.endReason, 'timeout');
      expect(store.saved, isNull);
    });

    test('attemptMove is optimistic and rolls back when server rejects',
        () async {
      await driveToPlaying(myColor: PieceColor.red);
      final game = ctrl.state.game!;

      // Pick any legal red move from the initial position.
      Position? from;
      Position? to;
      for (final (pos, piece) in game.board.occupied()) {
        if (piece.color != PieceColor.red) continue;
        final moves = game.getValidMoves(pos);
        if (moves.isNotEmpty) {
          from = pos;
          to = moves.first;
          break;
        }
      }
      expect(from, isNotNull);

      ctrl.attemptMove(from!, to!);
      // Applied optimistically → turn flips to black, move sent.
      expect(ctrl.state.currentTurn, PieceColor.black);
      expect(socket.sentTypes.any((t) => t.startsWith('move:')), isTrue);

      // Server rejects the move → controller undoes it.
      socket.emit({'type': 'error', 'code': 'illegal-move'});
      await pump();

      expect(ctrl.state.currentTurn, PieceColor.red);
      expect(ctrl.state.errorMessage, isNotNull);
    });
  });

  group('D1 — mid-game auto-reconnect', () {
    test('connection loss mid-game reconnects and resumes playing', () async {
      await driveToPlaying();
      expect(store.saved, 'ROOM01');

      // Socket service reports the live connection dropped.
      socket.onConnectionLost!();
      await pump();
      expect(ctrl.state.phase, OnlineMatchPhase.reconnecting);

      // Re-auth lands → controller resumes the room instead of the lobby.
      socket.emit({'type': 'authed', 'uid': 'me'});
      await pump();
      expect(socket.sentTypes, contains('reconnect-room'));
      expect(ctrl.state.phase, OnlineMatchPhase.reconnecting);

      // Server restores the game snapshot.
      socket.emit({
        'type': 'reconnected',
        'roomId': 'ROOM01',
        'redUid': 'red-uid',
        'blackUid': 'black-uid',
        'yourColor': 'red',
        'moves': <String>[],
        'clock': {'red': 600000, 'black': 600000},
        'currentTurn': 'red',
        'chat': <Map<String, dynamic>>[],
      });
      await pump();
      expect(ctrl.state.phase, OnlineMatchPhase.playing);
    });

    test('reconnect rejected (grace expired) stops retrying and clears store',
        () async {
      await driveToPlaying();

      socket.onConnectionLost!();
      await pump();
      socket.emit({'type': 'authed', 'uid': 'me'});
      await pump();
      expect(socket.sentTypes, contains('reconnect-room'));

      // Server says the room is gone — our seat was forfeited.
      socket.emit({'type': 'error', 'code': 'room-not-found'});
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.error);
      expect(store.saved, isNull);
    });

    test('no fresh reconnect state → gives up without spamming reconnect-room',
        () async {
      await driveToPlaying();
      store.saved = null; // simulate the grace window already elapsed

      socket.onConnectionLost!();
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.error);
      expect(socket.sentTypes, isNot(contains('reconnect-room')));
    });

    test('connection loss outside a game does not try to reconnect', () async {
      // setUp left us at phase=authed (lobby), not in a game.
      expect(ctrl.state.phase, OnlineMatchPhase.authed);

      socket.onConnectionLost!();
      await pump();

      expect(socket.sentTypes, isNot(contains('reconnect-room')));
      expect(ctrl.state.phase, OnlineMatchPhase.error);
    });
  });
}
