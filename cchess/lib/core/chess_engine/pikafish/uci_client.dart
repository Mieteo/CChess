import 'dart:async';

/// Line-oriented I/O channel to a running UCI engine.
///
/// The real implementation wraps a child [Process] (see
/// `pikafish_support_io.dart`); tests inject a scripted fake. Keeping the
/// protocol client transport-agnostic lets every parsing/sequencing path run
/// in plain unit tests without a binary.
abstract class UciTransport {
  /// Engine stdout, one line per event (no trailing newline).
  Stream<String> get lines;

  /// Write one command line to engine stdin.
  void send(String line);

  /// Completes when the engine process exits (any reason).
  Future<int> get exitCode;

  /// Kill the engine process and release pipes.
  Future<void> dispose();
}

class UciException implements Exception {
  final String message;
  UciException(this.message);
  @override
  String toString() => 'UciException: $message';
}

/// Engine score from the *side-to-move* perspective.
class UciScore {
  /// Centipawns, null when the engine reported a mate score instead.
  final int? cp;

  /// Moves-to-mate: positive = side to move mates, negative = gets mated.
  final int? mate;

  const UciScore({this.cp, this.mate});

  /// Collapse to a single centipawn number. Mate scores map to
  /// ±(30000 − distance) so "mate in 1" ≈ ±29999 — the convention Thiên Thiên
  /// Tượng Kỳ users know and what our eval charts will plot.
  int toCp() {
    final m = mate;
    if (m != null) {
      final magnitude = 30000 - m.abs().clamp(0, 1000);
      return m >= 0 ? magnitude : -magnitude;
    }
    return cp ?? 0;
  }

  @override
  String toString() => mate != null ? 'mate $mate' : 'cp $cp';
}

/// One `info ... multipv N ... pv ...` snapshot.
class UciPvLine {
  final int multipv;
  final int depth;
  final UciScore score;
  final List<String> pv;

  const UciPvLine({
    required this.multipv,
    required this.depth,
    required this.score,
    required this.pv,
  });

  String? get firstMove => pv.isEmpty ? null : pv.first;
}

/// Outcome of one `go` command.
class UciSearchResult {
  /// Move from the `bestmove` line, or null for `bestmove (none)`.
  final String? bestUci;

  /// Deepest non-bound info snapshot per MultiPV slot, ordered by multipv.
  final List<UciPvLine> pvLines;

  const UciSearchResult({required this.bestUci, required this.pvLines});

  /// The primary line (multipv 1) when the engine reported one.
  UciPvLine? get best {
    for (final line in pvLines) {
      if (line.multipv == 1) return line;
    }
    return pvLines.isEmpty ? null : pvLines.first;
  }
}

/// Minimal UCI protocol client: handshake, options, and serialized searches.
///
/// All commands are funneled through an internal queue so concurrent callers
/// can never interleave `position`/`go` pairs. Engine death at any point fails
/// the in-flight request with [UciException].
class UciClient {
  UciClient(this._transport);

  final UciTransport _transport;

  StreamSubscription<String>? _sub;
  Completer<void>? _uciok;
  Completer<void>? _readyok;
  _SearchCollector? _search;
  Future<void> _queue = Future<void>.value();
  bool _dead = false;
  bool _started = false;
  int _multiPv = 1;

  bool get isAlive => _started && !_dead;

  /// Handshake + apply [options] (`setoption name K value V`), then block
  /// until the engine reports ready.
  Future<void> start({
    Map<String, String> options = const {},
    Duration timeout = const Duration(seconds: 15),
  }) {
    return _enqueue(() async {
      if (_started) return;
      _started = true;
      _sub = _transport.lines.listen(_onLine);
      unawaited(
        _transport.exitCode.then((_) => _onEngineDied()).catchError((_) {}),
      );

      _uciok = Completer<void>();
      _transport.send('uci');
      await _await(_uciok!.future, timeout, 'uciok');

      for (final entry in options.entries) {
        _transport.send('setoption name ${entry.key} value ${entry.value}');
      }
      await _isReady(timeout);
    });
  }

  /// Run one search and wait for `bestmove`.
  ///
  /// Exactly one of [movetimeMs] / [depth] should be set (movetime wins when
  /// both are). Scores in the result are side-to-move relative.
  Future<UciSearchResult> search({
    required String fen,
    int? movetimeMs,
    int? depth,
    int multiPv = 1,
    Duration? timeout,
  }) {
    return _enqueue(() async {
      _ensureAlive();
      if (multiPv != _multiPv) {
        _transport.send('setoption name MultiPV value $multiPv');
        _multiPv = multiPv;
        await _isReady(const Duration(seconds: 5));
      }

      final collector = _SearchCollector();
      _search = collector;
      _transport.send('position fen $fen');
      if (movetimeMs != null) {
        _transport.send('go movetime $movetimeMs');
      } else {
        _transport.send('go depth ${depth ?? 12}');
      }

      // Give the engine its budget plus generous slack; a stuck engine gets
      // one `stop` nudge before we declare it broken.
      final budget = timeout ??
          Duration(milliseconds: (movetimeMs ?? 20000) + 8000);
      try {
        return await _await(collector.done.future, budget, 'bestmove');
      } on UciException {
        if (!_dead) {
          _transport.send('stop');
          try {
            return await _await(
              collector.done.future,
              const Duration(seconds: 3),
              'bestmove after stop',
            );
          } on UciException {
            _dead = true;
            rethrow;
          }
        }
        rethrow;
      } finally {
        _search = null;
      }
    });
  }

  Future<void> dispose() async {
    _dead = true;
    try {
      _transport.send('quit');
    } catch (_) {}
    await _sub?.cancel();
    await _transport.dispose();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _isReady(Duration timeout) async {
    _readyok = Completer<void>();
    _transport.send('isready');
    await _await(_readyok!.future, timeout, 'readyok');
  }

  Future<T> _await<T>(Future<T> future, Duration timeout, String what) {
    return future.timeout(
      timeout,
      onTimeout: () => throw UciException('Timed out waiting for $what'),
    );
  }

  void _ensureAlive() {
    if (!_started) throw UciException('Client not started');
    if (_dead) throw UciException('Engine process has exited');
  }

  void _onEngineDied() {
    _dead = true;
    final err = UciException('Engine process exited unexpectedly');
    if (!(_uciok?.isCompleted ?? true)) _uciok!.completeError(err);
    if (!(_readyok?.isCompleted ?? true)) _readyok!.completeError(err);
    final search = _search;
    if (search != null && !search.done.isCompleted) {
      search.done.completeError(err);
    }
  }

  void _onLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    if (line == 'uciok') {
      if (!(_uciok?.isCompleted ?? true)) _uciok!.complete();
      return;
    }
    if (line == 'readyok') {
      if (!(_readyok?.isCompleted ?? true)) _readyok!.complete();
      return;
    }
    if (line.startsWith('info ')) {
      _search?.addInfo(line);
      return;
    }
    if (line.startsWith('bestmove')) {
      final search = _search;
      if (search == null || search.done.isCompleted) return;
      final parts = line.split(RegExp(r'\s+'));
      final move = parts.length > 1 ? parts[1] : '(none)';
      search.done.complete(
        UciSearchResult(
          bestUci: move == '(none)' ? null : move,
          pvLines: search.snapshot(),
        ),
      );
    }
  }
}

/// Accumulates `info` lines for one search, keeping the deepest exact
/// (non lowerbound/upperbound) snapshot per MultiPV slot.
class _SearchCollector {
  final Completer<UciSearchResult> done = Completer<UciSearchResult>();
  final Map<int, UciPvLine> _byMultipv = {};

  void addInfo(String line) {
    final parsed = parseInfoLine(line);
    if (parsed == null) return;
    final existing = _byMultipv[parsed.multipv];
    if (existing == null || parsed.depth >= existing.depth) {
      _byMultipv[parsed.multipv] = parsed;
    }
  }

  List<UciPvLine> snapshot() {
    final lines = _byMultipv.values.toList()
      ..sort((a, b) => a.multipv.compareTo(b.multipv));
    return lines;
  }
}

/// Parse one `info` line into a [UciPvLine]. Returns null for lines that
/// carry no usable score+pv (e.g. `info string ...`, bound scores,
/// currmove progress reports).
UciPvLine? parseInfoLine(String line) {
  final tokens = line.split(RegExp(r'\s+'));
  int? depth;
  int multipv = 1;
  int? cp;
  int? mate;
  List<String>? pv;
  bool bound = false;

  for (var i = 0; i < tokens.length; i++) {
    switch (tokens[i]) {
      case 'depth':
        if (i + 1 < tokens.length) depth = int.tryParse(tokens[i + 1]);
        break;
      case 'multipv':
        if (i + 1 < tokens.length) {
          multipv = int.tryParse(tokens[i + 1]) ?? 1;
        }
        break;
      case 'score':
        if (i + 2 < tokens.length) {
          final kind = tokens[i + 1];
          final value = int.tryParse(tokens[i + 2]);
          if (kind == 'cp') cp = value;
          if (kind == 'mate') mate = value;
        }
        break;
      case 'lowerbound':
      case 'upperbound':
        bound = true;
        break;
      case 'pv':
        pv = tokens.sublist(i + 1);
        i = tokens.length; // pv consumes the rest of the line
        break;
      case 'string':
        return null;
    }
  }

  if (bound || pv == null || pv.isEmpty || (cp == null && mate == null)) {
    return null;
  }
  return UciPvLine(
    multipv: multipv,
    depth: depth ?? 0,
    score: UciScore(cp: cp, mate: mate),
    pv: pv,
  );
}
