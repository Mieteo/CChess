import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../models/chess_puzzle.dart';
import 'puzzle_api_transport.dart';
import 'puzzle_api_transport_factory.dart';

typedef PuzzleTokenProvider = Future<String?> Function();

/// Server-side ordering for the puzzle list. Mirrors the backend `PuzzleSort`.
enum PuzzleSort {
  newest('newest'),
  hardest('hardest'),
  easiest('easiest');

  const PuzzleSort(this.apiName);
  final String apiName;
}

/// One page of the paginated puzzle list (`GET /puzzles`).
class PuzzlePage {
  const PuzzlePage({
    required this.puzzles,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<ChessPuzzle> puzzles;
  final bool hasMore;
  final String? nextCursor;

  static const empty = PuzzlePage(puzzles: [], hasMore: false, nextCursor: null);
}

/// Talks to the cchess-backend puzzle REST API (B4 — Kho Tàn Cục).
///
/// Public reads (`list`, `getById`, `daily`) need no auth; [reportProgress]
/// sends the Firebase ID token as a Bearer header. All methods throw
/// [PuzzleApiException] on failure — the repository layer decides when to fall
/// back to the local/cached catalog.
class RemotePuzzleSource {
  RemotePuzzleSource({
    required this.baseUri,
    PuzzleTokenProvider? tokenProvider,
    PuzzleApiTransport? transport,
    this.timeout = const Duration(seconds: 8),
  })  : _tokenProvider = tokenProvider ?? _noToken,
        _transport = transport ?? createDefaultPuzzleApiTransport();

  final Uri baseUri;
  final PuzzleTokenProvider _tokenProvider;
  final PuzzleApiTransport _transport;
  final Duration timeout;

  /// Browse the catalog with optional filters. Cursor-paginated.
  Future<PuzzlePage> list({
    int limit = 20,
    String? cursor,
    int? difficulty,
    String? category,
    String? theme,
    String? tag,
    PuzzleSort sort = PuzzleSort.newest,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      'sort': sort.apiName,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (difficulty != null) 'difficulty': '$difficulty',
      if (category != null && category.isNotEmpty) 'category': category,
      if (theme != null && theme.isNotEmpty) 'theme': theme,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
    };
    final json = await _transport.getJson(
      _uri(const ['puzzles'], query),
      timeout: timeout,
    );
    final rawList = json['puzzles'];
    final puzzles = rawList is List
        ? rawList
            .whereType<Map>()
            .map(ChessPuzzle.fromJson)
            .toList(growable: false)
        : const <ChessPuzzle>[];
    return PuzzlePage(
      puzzles: puzzles,
      hasMore: json['hasMore'] == true,
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// Fetch a single puzzle, or `null` if the server returns 404.
  Future<ChessPuzzle?> getById(String id) async {
    try {
      final json = await _transport.getJson(
        _uri(['puzzles', id]),
        timeout: timeout,
      );
      return ChessPuzzle.fromJson(json);
    } on PuzzleApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// The featured daily puzzle for [date] (`YYYY-MM-DD`, server default = today
  /// in VN time). Returns `null` when none is scheduled.
  Future<ChessPuzzle?> daily({String? date}) async {
    final json = await _transport.getJson(
      _uri(const ['puzzles', 'daily'],
          date != null && date.isNotEmpty ? {'date': date} : null),
      timeout: timeout,
    );
    final puzzle = json['puzzle'];
    return puzzle is Map ? ChessPuzzle.fromJson(puzzle) : null;
  }

  /// Report an attempt to the server (auth required). Returns the authoritative
  /// progress doc (includes the server-clamped `bestScore`).
  Future<PuzzleProgress> reportProgress(
    String id, {
    required bool solved,
    int hintsUsed = 0,
    int score = 0,
  }) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const PuzzleApiException(
        statusCode: 401,
        code: 'missing-token',
        message: 'Sign-in required to sync puzzle progress',
      );
    }
    final json = await _transport.postJson(
      _uri(['puzzles', id, 'progress']),
      headers: {'authorization': 'Bearer $token'},
      body: {'solved': solved, 'hintsUsed': hintsUsed, 'score': score},
      timeout: timeout,
    );
    return PuzzleProgress.fromRemoteJson(json);
  }

  void close() => _transport.close();

  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final basePath = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();
    return baseUri.replace(
      pathSegments: [...basePath, ...segments],
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  static Future<String?> _noToken() async => null;
}

/// Backend-backed source wired to the configured HTTP origin + Firebase token.
final remotePuzzleSourceProvider = Provider<RemotePuzzleSource>((ref) {
  final source = RemotePuzzleSource(
    baseUri: Uri.parse(AppConstants.defaultBackendHttpUrl),
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.getIdToken();
    },
  );
  ref.onDispose(source.close);
  return source;
});
