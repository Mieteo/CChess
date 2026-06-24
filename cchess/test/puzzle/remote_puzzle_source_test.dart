import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/datasources/remote/remote_puzzle_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the last request and replays a canned response (or throws).
class _FakeTransport implements PuzzleApiTransport {
  _FakeTransport();

  Map<String, dynamic>? getResponse;
  Map<String, dynamic>? postResponse;
  Object? error; // thrown by the next call when set

  Uri? lastUri;
  String? lastMethod;
  Map<String, String>? lastHeaders;
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastUri = uri;
    lastMethod = 'GET';
    lastHeaders = headers;
    if (error != null) throw error!;
    return getResponse ?? const {};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    Map<String, String> headers = const {},
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastUri = uri;
    lastMethod = 'POST';
    lastHeaders = headers;
    lastBody = body;
    if (error != null) throw error!;
    return postResponse ?? const {};
  }

  @override
  void close() {}
}

void main() {
  final base = Uri.parse('https://api.example.com');

  group('RemotePuzzleSource.list', () {
    test('builds /puzzles URL with filters and parses the page', () async {
      final transport = _FakeTransport()
        ..getResponse = {
          'puzzles': [
            {
              'id': 'p100',
              'fen': '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
              'solution': ['a0a1'],
              'titleVi': 'Test',
              'descriptionVi': 'desc',
              'tags': ['Xe'],
              'difficulty': 3,
              'category': 'capture',
              'theme': 'Xe Pháo',
              'solveRateGlobal': 0.42,
            },
          ],
          'hasMore': true,
          'nextCursor': 'p100',
        };
      final source = RemotePuzzleSource(baseUri: base, transport: transport);

      final page = await source.list(
        limit: 10,
        difficulty: 3,
        category: 'capture',
        sort: PuzzleSort.hardest,
      );

      expect(transport.lastMethod, 'GET');
      expect(transport.lastUri!.path, '/puzzles');
      expect(transport.lastUri!.queryParameters['limit'], '10');
      expect(transport.lastUri!.queryParameters['difficulty'], '3');
      expect(transport.lastUri!.queryParameters['category'], 'capture');
      expect(transport.lastUri!.queryParameters['sort'], 'hardest');

      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'p100');
      expect(page.puzzles, hasLength(1));
      final p = page.puzzles.first;
      expect(p.id, 'p100');
      expect(p.category, 'capture');
      expect(p.theme, 'Xe Pháo');
      expect(p.solveRate, closeTo(0.42, 1e-9));
      expect(p.difficulty, 3);
    });

    test('omits absent optional query params', () async {
      final transport = _FakeTransport()..getResponse = {'puzzles': []};
      final source = RemotePuzzleSource(baseUri: base, transport: transport);

      await source.list();

      final q = transport.lastUri!.queryParameters;
      expect(q.containsKey('difficulty'), isFalse);
      expect(q.containsKey('cursor'), isFalse);
      expect(q.containsKey('category'), isFalse);
      expect(q['sort'], 'newest');
    });
  });

  group('RemotePuzzleSource.getById', () {
    test('returns null on 404', () async {
      final transport = _FakeTransport()
        ..error = const PuzzleApiException(
          statusCode: 404,
          code: 'not-found',
          message: 'Puzzle not found',
        );
      final source = RemotePuzzleSource(baseUri: base, transport: transport);

      expect(await source.getById('nope'), isNull);
      expect(transport.lastUri!.path, '/puzzles/nope');
    });

    test('rethrows non-404 errors', () async {
      final transport = _FakeTransport()
        ..error = const PuzzleApiException(
          statusCode: 500,
          code: 'internal-error',
          message: 'boom',
        );
      final source = RemotePuzzleSource(baseUri: base, transport: transport);

      expect(() => source.getById('p1'), throwsA(isA<PuzzleApiException>()));
    });
  });

  group('RemotePuzzleSource.daily', () {
    test('unwraps the { date, puzzle } envelope', () async {
      final transport = _FakeTransport()
        ..getResponse = {
          'date': '2026-06-24',
          'puzzle': {
            'id': 'd1',
            'fen': '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
            'solution': ['a0a1'],
            'titleVi': 'Daily',
            'descriptionVi': '',
          },
        };
      final source = RemotePuzzleSource(baseUri: base, transport: transport);

      final puzzle = await source.daily(date: '2026-06-24');
      expect(transport.lastUri!.path, '/puzzles/daily');
      expect(transport.lastUri!.queryParameters['date'], '2026-06-24');
      expect(puzzle!.id, 'd1');
    });

    test('returns null when no puzzle scheduled', () async {
      final transport = _FakeTransport()
        ..getResponse = {'date': '2026-06-24', 'puzzle': null};
      final source = RemotePuzzleSource(baseUri: base, transport: transport);
      expect(await source.daily(), isNull);
    });
  });

  group('RemotePuzzleSource.reportProgress', () {
    test('sends bearer token + body and parses the doc', () async {
      final transport = _FakeTransport()
        ..postResponse = {
          'puzzleId': 'p1',
          'solved': true,
          'attempts': 4,
          'hintsUsed': 1,
          'bestScore': 90,
          'solvedAtMs': 1_700_000_000_000,
          'updatedAtMs': 1_700_000_000_000,
        };
      final source = RemotePuzzleSource(
        baseUri: base,
        transport: transport,
        tokenProvider: () async => 'tok123',
      );

      final progress = await source.reportProgress(
        'p1',
        solved: true,
        hintsUsed: 1,
        score: 90,
      );

      expect(transport.lastMethod, 'POST');
      expect(transport.lastUri!.path, '/puzzles/p1/progress');
      expect(transport.lastHeaders!['authorization'], 'Bearer tok123');
      expect(transport.lastBody, {'solved': true, 'hintsUsed': 1, 'score': 90});

      expect(progress.solved, isTrue);
      expect(progress.bestScore, 90);
      expect(progress.attempts, 4);
      expect(progress.solvedAt, isNotNull);
    });

    test('throws (without calling transport) when signed out', () async {
      final transport = _FakeTransport();
      final source = RemotePuzzleSource(baseUri: base, transport: transport);

      await expectLater(
        source.reportProgress('p1', solved: true),
        throwsA(isA<PuzzleApiException>()),
      );
      expect(transport.lastMethod, isNull);
    });
  });
}
