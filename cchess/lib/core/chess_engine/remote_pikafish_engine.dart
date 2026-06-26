import '../constants/piece_constants.dart';
import 'ai/engine_config.dart';
import 'ai/game_analyzer.dart';
import 'engine_quota.dart';
import 'move.dart';
import 'move_engine.dart';
import 'remote_pikafish_transport.dart';
import 'remote_pikafish_transport_factory.dart';
import 'xiangqi_game.dart';

typedef EngineTokenProvider = Future<String?> Function();

class RemotePikafishEngine implements MoveEngine {
  RemotePikafishEngine({
    required this.baseUri,
    EngineTokenProvider? tokenProvider,
    PikafishTransport? transport,
    this.timeout = const Duration(seconds: 8),
  }) : _tokenProvider = tokenProvider ?? _noToken,
       _transport = transport ?? createDefaultPikafishTransport();

  final Uri baseUri;
  final EngineTokenProvider _tokenProvider;
  final PikafishTransport _transport;
  final Duration timeout;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
    EngineConfig? config,
  }) async {
    // `level` is always sent for backward-compat with the current backend.
    // The ELO-ladder strength fields are additive — a backend that doesn't yet
    // understand them (pre Phase 5) simply ignores them and uses `level`.
    final body = <String, dynamic>{'fen': fen, 'level': level.apiName};
    if (config != null) {
      if (config.uciElo != null) body['elo'] = config.uciElo;
      if (config.skillLevel != null) body['skill'] = config.skillLevel;
      if (config.movetimeMs != null) body['movetimeMs'] = config.movetimeMs;
    }
    final json = await _postJson(
      useCase == EngineUseCase.hint ? '/engine/hint' : '/engine/best-move',
      body,
    );
    final uci = json['uci'] as String?;
    if (uci == null) return null;
    return _moveFromUci(
      fen: fen,
      uci: uci,
      scoreCp: _asInt(json['scoreCp']),
      depth: _asInt(json['depth']),
    );
  }

  @override
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
  }) async {
    final json = await _postJson('/engine/analyze', {
      'startingFen': startingFen,
      'movesUci': moveUcis,
    });
    return _analysisFromJson(
      startingFen: startingFen,
      moveUcis: moveUcis,
      json: json,
    );
  }

  /// Reads the caller's remaining free-tier allowance for today. Throws
  /// [PikafishTransportException] on transport failure (no offline fallback —
  /// callers treat an error as "quota unknown").
  Future<EngineQuotaStatus> fetchQuota() async {
    final json = await _getJson('/engine/quota');
    return EngineQuotaStatus.fromJson(json);
  }

  void close() => _transport.close();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenProvider();
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = await _authHeaders();
    try {
      return await _transport.postJson(
        baseUri.resolve(path),
        headers: headers,
        body: body,
        timeout: timeout,
      );
    } on PikafishTransportException catch (e) {
      throw _mapTransportError(e, path);
    }
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final headers = await _authHeaders();
    try {
      return await _transport.getJson(
        baseUri.resolve(path),
        headers: headers,
        timeout: timeout,
      );
    } on PikafishTransportException catch (e) {
      throw _mapTransportError(e, path);
    }
  }

  /// Promote a 429 quota rejection to a typed domain exception so the router /
  /// UI can offer a VIP upsell; everything else propagates unchanged.
  Object _mapTransportError(PikafishTransportException e, String path) {
    if (e.statusCode == 429 || e.code == 'quota-exceeded') {
      return EngineQuotaExceededException(_featureForPath(path));
    }
    return e;
  }

  static String _featureForPath(String path) {
    if (path.contains('hint')) return 'hint';
    if (path.contains('analyze')) return 'analyze';
    return 'best-move';
  }

  EngineMove? _moveFromUci({
    required String fen,
    required String uci,
    int? scoreCp,
    int? depth,
  }) {
    final coords = Move.parseUciCoords(uci);
    if (coords == null) return null;
    final game = XiangqiGame.fromFen(fen);
    final (from, to) = coords;
    final piece = game.board.at(from);
    if (piece == null) return null;
    return EngineMove(
      move: Move(from: from, to: to, moved: piece, captured: game.board.at(to)),
      uci: uci,
      scoreCp: scoreCp,
      depth: depth,
      source: EngineSource.remotePikafish,
    );
  }

  GameAnalysis _analysisFromJson({
    required String startingFen,
    required List<String> moveUcis,
    required Map<String, dynamic> json,
  }) {
    final game = XiangqiGame.fromFen(startingFen);
    final rawMoves = json['perMove'] is List
        ? json['perMove'] as List
        : const [];
    final analyses = <MoveAnalysis>[];

    for (var i = 0; i < rawMoves.length && i < moveUcis.length; i++) {
      final item = rawMoves[i];
      if (item is! Map) continue;
      final uci = item['uci'] as String? ?? moveUcis[i];
      final coords = Move.parseUciCoords(uci);
      if (coords == null) continue;
      final (from, to) = coords;
      final piece = game.board.at(from);
      if (piece == null) continue;

      final recommended = _recommendedMove(
        game: game,
        uci: item['bestUci'] as String?,
      );
      final move = Move(
        from: from,
        to: to,
        moved: piece,
        captured: game.board.at(to),
      );
      analyses.add(
        MoveAnalysis(
          moveIndex: _asInt(item['moveIndex']) ?? i,
          move: move,
          mover: game.turn,
          recommendedMove: recommended,
          bestEval: _asInt(item['scoreCp']) ?? 0,
          actualEval: _asInt(item['actualScoreCp']) ?? 0,
          centipawnLoss: _asInt(item['centipawnLoss']) ?? 0,
          quality: _qualityFromString(item['classification'] as String?),
        ),
      );

      if (game.isValidMove(from, to)) {
        game.makeMove(from, to);
      } else {
        break;
      }
    }

    final localSummary = _aggregate(analyses);
    final summary = json['summary'] is Map ? json['summary'] as Map : const {};
    return GameAnalysis(
      moves: analyses,
      redAccuracy:
          _asDouble(summary['redAccuracy']) ?? localSummary.redAccuracy,
      blackAccuracy:
          _asDouble(summary['blackAccuracy']) ?? localSummary.blackAccuracy,
      redBlunders: _asInt(summary['redBlunders']) ?? localSummary.redBlunders,
      blackBlunders:
          _asInt(summary['blackBlunders']) ?? localSummary.blackBlunders,
      redMistakes: _asInt(summary['redMistakes']) ?? localSummary.redMistakes,
      blackMistakes:
          _asInt(summary['blackMistakes']) ?? localSummary.blackMistakes,
    );
  }

  Move? _recommendedMove({required XiangqiGame game, required String? uci}) {
    if (uci == null) return null;
    final coords = Move.parseUciCoords(uci);
    if (coords == null) return null;
    final (from, to) = coords;
    final piece = game.board.at(from);
    if (piece == null) return null;
    return Move(from: from, to: to, moved: piece, captured: game.board.at(to));
  }

  static Future<String?> _noToken() async => null;
}

MoveQuality _qualityFromString(String? value) {
  switch (value) {
    case 'best':
      return MoveQuality.best;
    case 'excellent':
      return MoveQuality.excellent;
    case 'good':
      return MoveQuality.good;
    case 'inaccuracy':
      return MoveQuality.inaccuracy;
    case 'mistake':
      return MoveQuality.mistake;
    case 'blunder':
      return MoveQuality.blunder;
    default:
      return MoveQuality.good;
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return null;
}

GameAnalysis _aggregate(List<MoveAnalysis> analyses) {
  var redCount = 0;
  var blackCount = 0;
  var redScore = 0;
  var blackScore = 0;
  var redBlunders = 0;
  var blackBlunders = 0;
  var redMistakes = 0;
  var blackMistakes = 0;
  for (final move in analyses) {
    if (move.mover == PieceColor.red) {
      redCount++;
      redScore += move.quality.scoreOut100;
      if (move.quality == MoveQuality.blunder) redBlunders++;
      if (move.quality == MoveQuality.mistake) redMistakes++;
    } else {
      blackCount++;
      blackScore += move.quality.scoreOut100;
      if (move.quality == MoveQuality.blunder) blackBlunders++;
      if (move.quality == MoveQuality.mistake) blackMistakes++;
    }
  }
  return GameAnalysis(
    moves: analyses,
    redAccuracy: redCount == 0 ? 0 : redScore / redCount,
    blackAccuracy: blackCount == 0 ? 0 : blackScore / blackCount,
    redBlunders: redBlunders,
    blackBlunders: blackBlunders,
    redMistakes: redMistakes,
    blackMistakes: blackMistakes,
  );
}
