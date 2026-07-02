import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/core/chess_engine/pikafish/uci_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_uci_transport.dart';

void main() {
  group('UciClient handshake', () {
    test('sends uci → setoptions → isready in order', () async {
      final transport = FakeUciTransport();
      final client = UciClient(transport);
      await client.start(options: {'Threads': '2', 'EvalFile': '/x.nnue'});

      expect(
        transport.sent,
        containsAllInOrder([
          'uci',
          'setoption name Threads value 2',
          'setoption name EvalFile value /x.nnue',
          'isready',
        ]),
      );
      await client.dispose();
    });

    test('times out when the engine never answers', () async {
      final transport = FakeUciTransport()..respondToHandshake = false;
      final client = UciClient(transport);
      await expectLater(
        client.start(timeout: const Duration(milliseconds: 50)),
        throwsA(isA<UciException>()),
      );
      await client.dispose();
    });
  });

  group('UciClient search', () {
    test('parses score/depth/pv and bestmove', () async {
      final transport = FakeUciTransport()
        ..searchScripts.add([
          'info depth 8 seldepth 12 multipv 1 score cp 34 nodes 1000 pv b2e2 b9c7',
          'info depth 10 seldepth 15 multipv 1 score cp 42 nodes 5000 pv b2e2 h9g7',
          'bestmove b2e2 ponder h9g7',
        ]);
      final client = UciClient(transport);
      await client.start();

      final result = await client.search(fen: kInitialFen, movetimeMs: 100);
      expect(result.bestUci, 'b2e2');
      expect(result.best!.score.cp, 42);
      expect(result.best!.depth, 10);
      expect(result.best!.pv.first, 'b2e2');
      await client.dispose();
    });

    test('keeps deepest line per multipv slot, skips bounds and strings',
        () async {
      final transport = FakeUciTransport()
        ..searchScripts.add([
          'info string NNUE evaluation using pikafish.nnue',
          'info depth 9 multipv 1 score cp 50 lowerbound nodes 10 pv b2e2',
          'info depth 10 multipv 1 score cp 40 nodes 10 pv b2e2 h9g7',
          'info depth 10 multipv 2 score cp 12 nodes 10 pv h2e2 b9c7',
          'info depth 10 multipv 3 score mate -4 nodes 10 pv a0a1 x',
          'bestmove b2e2',
        ]);
      final client = UciClient(transport);
      await client.start();

      final result = await client.search(
        fen: kInitialFen,
        movetimeMs: 100,
        multiPv: 3,
      );
      expect(transport.sent, contains('setoption name MultiPV value 3'));
      expect(result.pvLines, hasLength(3));
      expect(result.pvLines[0].score.cp, 40); // bound line ignored
      expect(result.pvLines[1].firstMove, 'h2e2');
      expect(result.pvLines[2].score.mate, -4);
      expect(result.pvLines[2].score.toCp(), -29996);
      await client.dispose();
    });

    test('bestmove (none) yields null bestUci', () async {
      final transport = FakeUciTransport()
        ..searchScripts.add(['bestmove (none)']);
      final client = UciClient(transport);
      await client.start();
      final result = await client.search(fen: kInitialFen, movetimeMs: 50);
      expect(result.bestUci, isNull);
      await client.dispose();
    });

    test('engine death mid-search surfaces as UciException', () async {
      final transport = FakeUciTransport()..respondToGo = false;
      final client = UciClient(transport);
      await client.start();

      final pending = client.search(fen: kInitialFen, movetimeMs: 100);
      transport.die();
      await expectLater(pending, throwsA(isA<UciException>()));
      expect(client.isAlive, isFalse);
      await client.dispose();
    });
  });

  group('parseInfoLine', () {
    test('returns null for currmove progress lines (no pv/score)', () {
      expect(
        parseInfoLine('info depth 12 currmove b2e2 currmovenumber 3'),
        isNull,
      );
    });

    test('mate score converts to ±(30000 − n)', () {
      final line = parseInfoLine('info depth 20 score mate 5 pv a0a1');
      expect(line!.score.toCp(), 29995);
      final losing = parseInfoLine('info depth 20 score mate -2 pv a0a1');
      expect(losing!.score.toCp(), -29998);
    });
  });
}
