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

  /// Captured clock budget from the last create-room / find-match so B3 can
  /// assert the lobby's chosen clock actually reaches the socket.
  int? lastCreateRoomClockMs;
  int? lastFindMatchClockMs;

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
  void createRoom({int? clockMs}) {
    lastCreateRoomClockMs = clockMs;
    sentTypes.add('create-room');
  }

  @override
  void findMatch({int? clockMs}) {
    lastFindMatchClockMs = clockMs;
    sentTypes.add('find-match');
  }

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  @override
  Future<String?> readRoomId() async => saved;
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

    test(
      'fresh game-start (rematch) resumes playing and resets flags',
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
      },
    );

    test(
      'rematch rejection error keeps phase ended (no crash to error)',
      () async {
        await driveToEnded();
        ctrl.offerRematch();

        socket.emit({'type': 'error', 'code': 'no-opponent'});
        await pump();

        expect(ctrl.state.phase, OnlineMatchPhase.ended);
        expect(ctrl.state.rematchOfferedByMe, isFalse);
        expect(ctrl.state.errorMessage, isNotNull);
      },
    );
  });

  group('R9 — opponent left the finished room', () {
    test(
      'peer-left while ended flips opponentLeftRoom and clears offers',
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
      },
    );

    test(
      'offerRematch after peer-left fails locally without a round-trip',
      () async {
        await driveToEnded();
        socket.emit({'type': 'peer-left', 'uid': 'black-uid'});
        await pump();

        ctrl.offerRematch();

        expect(socket.sentTypes, isNot(contains('rematch-offer')));
        expect(ctrl.state.errorMessage, isNotNull);
      },
    );

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
      expect(
        store.saved,
        isNull,
        reason: 'watchers must not save reconnect state',
      );
    });

    test(
      'room-expired returns the creator to the lobby with a message',
      () async {
        socket.emit({'type': 'room-created', 'roomId': 'ROOM02'});
        await pump();
        expect(ctrl.state.phase, OnlineMatchPhase.waitingForPeer);

        socket.emit({'type': 'room-expired', 'roomId': 'ROOM02'});
        await pump();

        expect(ctrl.state.phase, OnlineMatchPhase.authed);
        expect(ctrl.state.roomId, isNull);
        expect(ctrl.state.errorMessage, isNotNull);
      },
    );
  });

  group('core game flow', () {
    test(
      'game-ended sets result/reason and clears the reconnect store',
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
      },
    );

    test(
      'attemptMove is optimistic and rolls back when server rejects',
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
        expect(ctrl.state.moveClockRemainingMs, ctrl.state.moveClockLimitMs);
        expect(ctrl.state.moveClockUpdatedAtMs, isNotNull);
        expect(socket.sentTypes.any((t) => t.startsWith('move:')), isTrue);

        // Server rejects the move → controller undoes it.
        socket.emit({'type': 'error', 'code': 'illegal-move'});
        await pump();

        expect(ctrl.state.currentTurn, PieceColor.red);
        expect(ctrl.state.errorMessage, isNotNull);
      },
    );

    test('server clock snapshot syncs the per-move countdown', () async {
      socket.emit({
        'type': 'game-start',
        'roomId': 'ROOM01',
        'redUid': 'red-uid',
        'blackUid': 'black-uid',
        'yourColor': 'red',
        'clock': {
          'red': 600000,
          'black': 600000,
          'currentTurn': 'red',
          'moveTimeLimitMs': 90000,
          'moveRemainingMs': 45000,
        },
      });
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.playing);
      expect(ctrl.state.moveClockLimitMs, 90000);
      expect(ctrl.state.moveClockRemainingMs, 45000);
      expect(ctrl.state.moveClockUpdatedAtMs, isNotNull);
      expect(ctrl.state.currentTurn, PieceColor.red);
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

    test(
      'reconnect rejected (grace expired) stops retrying and clears store',
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

        // Recovers to a usable lobby (NOT a dead-end error) + clears the room.
        expect(ctrl.state.phase, OnlineMatchPhase.authed);
        expect(store.saved, isNull);
      },
    );

    test(
      'lobby reconnect to a DEAD room clears it and returns to lobby',
      () async {
        // A stale saved room from a previous broken session would otherwise make
        // the lobby re-attach to a ghost room on every load (the "đang đánh / no
        // board" stuck state). Rejecting it must clear the store.
        store.saved = 'GHOST1';
        ctrl.reconnectRoom('GHOST1'); // public lobby reconnect-on-load path
        await pump();
        expect(ctrl.state.phase, OnlineMatchPhase.reconnecting);
        expect(socket.sentTypes, contains('reconnect-room'));

        socket.emit({'type': 'error', 'code': 'room-not-found'});
        await pump();

        expect(ctrl.state.phase, OnlineMatchPhase.authed);
        expect(
          store.saved,
          isNull,
          reason: 'ghost room must be cleared so the lobby stops re-attaching',
        );
      },
    );

    test(
      'no fresh reconnect state → gives up without spamming reconnect-room',
      () async {
        await driveToPlaying();
        store.saved = null; // simulate the grace window already elapsed

        socket.onConnectionLost!();
        await pump();

        expect(ctrl.state.phase, OnlineMatchPhase.error);
        expect(socket.sentTypes, isNot(contains('reconnect-room')));
      },
    );

    test('connection loss outside a game does not try to reconnect', () async {
      // setUp left us at phase=authed (lobby), not in a game.
      expect(ctrl.state.phase, OnlineMatchPhase.authed);

      socket.onConnectionLost!();
      await pump();

      expect(socket.sentTypes, isNot(contains('reconnect-room')));
      expect(ctrl.state.phase, OnlineMatchPhase.error);
    });

    test(
      'reconnected replays the moves so the board is NOT reset to start',
      () async {
        // D2 headline bug: after reconnect the board showed the initial position.
        // Verify the client replays the server's move list onto a fresh game.
        await driveToPlaying(myColor: PieceColor.red);
        final game = ctrl.state.game!;

        // Make one real red move so we have a UCI in the exact client format.
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
        ctrl.attemptMove(from!, to!);
        final uci = socket.sentTypes
            .firstWhere((t) => t.startsWith('move:'))
            .substring('move:'.length);

        socket.onConnectionLost!();
        await pump();
        socket.emit({'type': 'authed', 'uid': 'me'});
        await pump();
        socket.emit({
          'type': 'reconnected',
          'roomId': 'ROOM01',
          'redUid': 'red-uid',
          'blackUid': 'black-uid',
          'yourColor': 'red',
          'moves': <String>[uci],
          'clock': {'red': 600000, 'black': 600000},
          'currentTurn': 'black',
          'chat': <Map<String, dynamic>>[],
        });
        await pump();

        expect(ctrl.state.phase, OnlineMatchPhase.playing);
        expect(
          ctrl.state.game!.history.length,
          1,
          reason: 'the played move must be replayed, not reset to the start',
        );
      },
    );

    test(
      'a burst of connectivity events coalesces into ONE reconnect attempt',
      () async {
        // Regression for D2: connectivity_plus firing several times (or a timer
        // racing) used to spawn overlapping disconnect/connect cycles that reset
        // the board + stuck the room. Single-flight must collapse them.
        await driveToPlaying();

        socket.onConnectionLost!();
        await pump(); // first attempt runs, now awaiting 'authed'

        // Network "returns" several times in a burst before the handshake lands.
        ctrl.onNetworkAvailable();
        ctrl.onNetworkAvailable();
        ctrl.onNetworkAvailable();
        await pump();

        socket.emit({'type': 'authed', 'uid': 'me'});
        await pump();

        final count = socket.sentTypes
            .where((t) => t == 'reconnect-room')
            .length;
        expect(
          count,
          1,
          reason: 'exactly one reconnect-room despite the burst',
        );
      },
    );
  });

  group('B1 — chat (C1/C3/C4/C5/C6/C7)', () {
    Map<String, dynamic> chatMsg({
      required String id,
      String from = 'black-uid',
      String text = 'gg',
      int ts = 1000,
      String? roomId,
    }) => {
      'type': 'chat-message',
      'id': id,
      'from': from,
      'text': text,
      'ts': ts,
      'roomId': ?roomId,
    };

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

    test('C1 — an incoming chat message is appended with from/text', () async {
      await driveToPlaying();
      socket.emit(chatMsg(id: 'm1', from: 'black-uid', text: 'gg wp'));
      await pump();

      expect(ctrl.state.chatMessages, hasLength(1));
      final m = ctrl.state.chatMessages.single;
      expect(m.fromUid, 'black-uid');
      expect(m.text, 'gg wp');
    });

    test('duplicate chat ids are de-duplicated', () async {
      await driveToPlaying();
      socket.emit(chatMsg(id: 'm1', text: 'first'));
      socket.emit(chatMsg(id: 'm1', text: 'first'));
      await pump();

      expect(ctrl.state.chatMessages, hasLength(1));
    });

    test('chat addressed to a different room is ignored', () async {
      await driveToPlaying(); // roomId == ROOM01
      socket.emit(chatMsg(id: 'm1', roomId: 'OTHER'));
      await pump();

      expect(ctrl.state.chatMessages, isEmpty);
    });

    test(
      'C3 — chat-rate-limited surfaces a Vietnamese message, keeps playing',
      () async {
        await driveToPlaying();
        socket.emit({'type': 'error', 'code': 'chat-rate-limited'});
        await pump();

        expect(ctrl.state.errorMessage, 'Bạn gửi chat quá nhanh.');
        expect(ctrl.state.phase, OnlineMatchPhase.playing);
      },
    );

    test(
      'C4 — invalid-chat surfaces a Vietnamese message, keeps playing',
      () async {
        await driveToPlaying();
        socket.emit({'type': 'error', 'code': 'invalid-chat'});
        await pump();

        expect(ctrl.state.errorMessage, 'Tin nhắn không hợp lệ hoặc quá dài.');
        expect(ctrl.state.phase, OnlineMatchPhase.playing);
      },
    );

    test('C4 — the client blocks > 120 chars before sending', () async {
      await driveToPlaying();
      ctrl.sendChatMessage('a' * 121);

      expect(ctrl.state.errorMessage, 'Tin nhắn tối đa 120 ký tự.');
      expect(socket.sentTypes, isNot(contains('chat-message')));
    });

    test('blank / whitespace-only chat is a no-op', () async {
      await driveToPlaying();
      ctrl.sendChatMessage('   ');

      expect(socket.sentTypes, isNot(contains('chat-message')));
    });

    test('a valid message is collapsed/trimmed and sent', () async {
      await driveToPlaying();
      ctrl.sendChatMessage('  hello   world  ');

      expect(socket.sentTypes, contains('chat-message'));
    });

    test('C5 — a spectator can receive chat', () async {
      await driveToSpectating();
      expect(ctrl.state.isSpectating, isTrue);
      expect(ctrl.state.canChat, isTrue);

      socket.emit(chatMsg(id: 's1', from: 'red-uid', text: 'nice'));
      await pump();

      expect(ctrl.state.chatMessages.single.text, 'nice');
    });

    test('C6 — the reconnect snapshot restores chat history', () async {
      await driveToPlaying();
      socket.onConnectionLost!();
      await pump();
      socket.emit({'type': 'authed', 'uid': 'me'});
      await pump();
      socket.emit({
        'type': 'reconnected',
        'roomId': 'ROOM01',
        'redUid': 'red-uid',
        'blackUid': 'black-uid',
        'yourColor': 'red',
        'moves': <String>[],
        'clock': {'red': 600000, 'black': 600000},
        'currentTurn': 'red',
        'chat': [
          {'id': 'h1', 'from': 'red-uid', 'text': 'hi', 'ts': 1},
          {'id': 'h2', 'from': 'black-uid', 'text': 'hello', 'ts': 2},
        ],
      });
      await pump();

      expect(ctrl.state.chatMessages.map((m) => m.text), ['hi', 'hello']);
    });

    test('C7 — chat is blocked once the game has ended', () async {
      await driveToEnded();
      expect(ctrl.state.canChat, isFalse);

      ctrl.sendChatMessage('too late');

      expect(socket.sentTypes, isNot(contains('chat-message')));
    });
  });

  group('B2 — reconnect banners + lifecycle (D2/D3/D4)', () {
    test(
      'D2 — peer-disconnected enters the countdown phase with grace data',
      () async {
        await driveToPlaying();
        socket.emit({'type': 'peer-disconnected', 'graceMs': 60000});
        await pump();

        expect(ctrl.state.phase, OnlineMatchPhase.peerDisconnected);
        expect(ctrl.state.peerDisconnectGraceMs, 60000);
        expect(ctrl.state.peerDisconnectedAtMs, isNotNull);
        expect(ctrl.state.isPlaying, isTrue); // the game is still alive
      },
    );

    test('peer-disconnected without graceMs falls back to 60s', () async {
      await driveToPlaying();
      socket.emit({'type': 'peer-disconnected'});
      await pump();

      expect(ctrl.state.peerDisconnectGraceMs, 60000);
    });

    test(
      'D2 — peer-reconnected clears the banner and resumes playing',
      () async {
        await driveToPlaying();
        socket.emit({'type': 'peer-disconnected', 'graceMs': 60000});
        await pump();

        socket.emit({'type': 'peer-reconnected'});
        await pump();

        expect(ctrl.state.phase, OnlineMatchPhase.playing);
        expect(ctrl.state.peerDisconnectedAtMs, isNull);
        expect(ctrl.state.peerDisconnectGraceMs, isNull);
      },
    );

    test('a spectator is NOT pushed into the countdown phase', () async {
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

      socket.emit({'type': 'peer-disconnected', 'graceMs': 60000});
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.spectating);
    });

    test('D3 — grace expiry ends the game with reason disconnect', () async {
      await driveToPlaying(myColor: PieceColor.red);
      socket.emit({'type': 'peer-disconnected', 'graceMs': 60000});
      await pump();
      expect(ctrl.state.phase, OnlineMatchPhase.peerDisconnected);

      socket.emit({
        'type': 'game-ended',
        'result': 'red-win',
        'reason': 'disconnect',
      });
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.ended);
      expect(ctrl.state.endReason, 'disconnect');
      expect(ctrl.state.peerDisconnectedAtMs, isNull); // banner cleared
    });

    test('D4 — backgrounding keeps the reconnect store for relaunch', () async {
      await driveToPlaying();
      expect(store.saved, 'ROOM01');

      await ctrl.disconnectKeepingReconnectState();

      expect(
        store.saved,
        'ROOM01',
        reason: 'the next app launch must still find the room',
      );
      expect(ctrl.state.phase, OnlineMatchPhase.idle);
    });

    test(
      'D4 — leave() abandons the match and clears the reconnect store',
      () async {
        await driveToPlaying();
        expect(store.saved, 'ROOM01');

        await ctrl.leave();

        expect(store.saved, isNull);
        expect(ctrl.state.phase, OnlineMatchPhase.idle);
      },
    );

    test('D4 — tryAutoReconnect resumes a saved room from the lobby', () async {
      // setUp left us at phase=authed with an empty store.
      expect(await ctrl.tryAutoReconnect(), isFalse);
      expect(socket.sentTypes, isNot(contains('reconnect-room')));

      store.saved = 'ROOM01';
      final issued = await ctrl.tryAutoReconnect();

      expect(issued, isTrue);
      expect(socket.sentTypes, contains('reconnect-room'));
      expect(ctrl.state.phase, OnlineMatchPhase.reconnecting);
    });
  });

  group('B3 — matchmaking + lobby (M1/M3/M4)', () {
    test('M1 — findMatch sends find-match with the chosen clock', () async {
      // setUp leaves us at phase=authed.
      ctrl.findMatch(clockMs: 300000);

      expect(socket.sentTypes, contains('find-match'));
      expect(socket.lastFindMatchClockMs, 300000);
    });

    test('matching event moves us into the queue phase', () async {
      socket.emit({'type': 'matching'});
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.matching);
    });

    test('match-found seats us with the room id and opponent', () async {
      socket.emit({
        'type': 'match-found',
        'roomId': 'ROOM07',
        'opponent': 'rival-uid',
      });
      await pump();

      expect(ctrl.state.phase, OnlineMatchPhase.waitingForPeer);
      expect(ctrl.state.roomId, 'ROOM07');
      expect(ctrl.state.opponentUid, 'rival-uid');
    });

    test(
      'M3 — cancelMatching sends cancel-matching; the ack returns to lobby',
      () async {
        socket.emit({'type': 'matching'});
        await pump();

        ctrl.cancelMatching();
        expect(socket.sentTypes, contains('cancel-matching'));

        socket.emit({'type': 'matching-canceled'});
        await pump();
        expect(ctrl.state.phase, OnlineMatchPhase.authed);
      },
    );

    test(
      'M4 — createRoom forwards the chosen clock; room-created waits',
      () async {
        ctrl.createRoom(clockMs: 600000);

        expect(socket.sentTypes, contains('create-room'));
        expect(socket.lastCreateRoomClockMs, 600000);

        socket.emit({'type': 'room-created', 'roomId': 'ROOM08'});
        await pump();
        expect(ctrl.state.phase, OnlineMatchPhase.waitingForPeer);
        expect(ctrl.state.roomId, 'ROOM08');
      },
    );

    test(
      'requestActiveRooms sends the query; active-rooms populates state',
      () async {
        ctrl.requestActiveRooms();
        expect(socket.sentTypes, contains('list-active-rooms'));

        socket.emit({
          'type': 'active-rooms',
          'rooms': [
            {
              'roomId': 'ROOM09',
              'redUid': 'r',
              'blackUid': 'b',
              'moveCount': 4,
              'spectatorCount': 2,
              'currentTurn': 'black',
              'clock': {'red': 590000, 'black': 600000},
            },
          ],
        });
        await pump();

        expect(ctrl.state.activeRooms, hasLength(1));
        final room = ctrl.state.activeRooms.single;
        expect(room.roomId, 'ROOM09');
        expect(room.moveCount, 4);
        expect(room.spectatorCount, 2);
        expect(room.currentTurn, PieceColor.black);
      },
    );

    test('lobby actions are gated to the authed phase', () async {
      // Drop out of the lobby into an active game…
      await driveToPlaying();
      expect(ctrl.state.phase, OnlineMatchPhase.playing);
      socket.sentTypes.clear();

      // …now create-room / find-match must NOT be sent, and surface an error.
      ctrl.createRoom(clockMs: 600000);
      ctrl.findMatch(clockMs: 600000);

      expect(socket.sentTypes, isNot(contains('create-room')));
      expect(socket.sentTypes, isNot(contains('find-match')));
      expect(ctrl.state.errorMessage, isNotNull);
    });
  });
}
