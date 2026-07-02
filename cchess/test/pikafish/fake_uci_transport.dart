import 'dart:async';

import 'package:cchess/core/chess_engine/pikafish/uci_client.dart';

/// Scripted in-memory [UciTransport]: pattern-matches commands the client
/// sends and emits canned engine output, so protocol + engine logic tests
/// never need a real binary.
class FakeUciTransport implements UciTransport {
  final _controller = StreamController<String>.broadcast();
  final _exit = Completer<int>();
  final List<String> sent = [];

  /// Scripted responses for successive `go` commands (each entry is the list
  /// of lines the "engine" prints for that search).
  final List<List<String>> searchScripts = [];
  int _searchIndex = 0;

  /// When false the standard uci/isready handshake lines are not emitted
  /// (used to test handshake timeouts).
  bool respondToHandshake = true;

  /// When false, `go` commands are swallowed (search hangs until [emit] or
  /// death).
  bool respondToGo = true;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  void send(String line) {
    sent.add(line);
    if (respondToHandshake && line == 'uci') {
      emit('id name FakeFish');
      emit('uciok');
      return;
    }
    if (respondToHandshake && line == 'isready') {
      emit('readyok');
      return;
    }
    if (line.startsWith('go') && respondToGo) {
      final script = _searchIndex < searchScripts.length
          ? searchScripts[_searchIndex++]
          : const ['bestmove (none)'];
      for (final out in script) {
        emit(out);
      }
    }
  }

  void emit(String line) {
    if (!_controller.isClosed) _controller.add(line);
  }

  /// Simulate the engine process dying.
  void die([int code = 1]) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> dispose() async {
    die(0);
    await _controller.close();
  }
}
