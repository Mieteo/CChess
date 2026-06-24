import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/core/chess_engine/remote_pikafish_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EngineQuotaStatus.fromJson', () {
    test('parses per-feature free allowance', () {
      final status = EngineQuotaStatus.fromJson(const {
        'day': '2026-06-24',
        'vip': false,
        'features': {
          'best-move': {'used': 5, 'limit': 30, 'remaining': 25},
          'hint': {'used': 3, 'limit': 3, 'remaining': 0},
          'analyze': {'used': 0, 'limit': 3, 'remaining': 3},
        },
      });

      expect(status.day, '2026-06-24');
      expect(status.vip, isFalse);
      expect(status.hint.used, 3);
      expect(status.hint.remaining, 0);
      expect(status.hint.exhausted, isTrue);
      expect(status.bestMove.remaining, 25);
      expect(status.bestMove.exhausted, isFalse);
      expect(status.analyze.unlimited, isFalse);
    });

    test('treats -1 limit as unlimited for VIP', () {
      final status = EngineQuotaStatus.fromJson(const {
        'day': '2026-06-24',
        'vip': true,
        'features': {
          'hint': {'used': 0, 'limit': -1, 'remaining': -1},
        },
      });

      expect(status.vip, isTrue);
      expect(status.hint.unlimited, isTrue);
      expect(status.hint.exhausted, isFalse);
    });

    test('defaults missing features to an empty allowance', () {
      final status = EngineQuotaStatus.fromJson(const {'vip': false});
      expect(status.hint.used, 0);
      expect(status.hint.limit, 0);
    });
  });

  group('RemotePikafishEngine quota', () {
    test('fetchQuota reads GET /engine/quota', () async {
      final transport = _FakeTransport(
        getResponse: const {
          'day': '2026-06-24',
          'vip': false,
          'features': {
            'hint': {'used': 1, 'limit': 3, 'remaining': 2},
          },
        },
      );
      final engine = RemotePikafishEngine(
        baseUri: Uri.parse('https://engine.example'),
        transport: transport,
      );

      final status = await engine.fetchQuota();

      expect(transport.getUri?.path, '/engine/quota');
      expect(status.hint.remaining, 2);
    });

    test('maps a 429 hint rejection to EngineQuotaExceededException', () async {
      final transport = _FakeTransport(
        postError: const PikafishTransportException(
          statusCode: 429,
          code: 'quota-exceeded',
          message: 'Daily engine quota exceeded',
        ),
      );
      final engine = RemotePikafishEngine(
        baseUri: Uri.parse('https://engine.example'),
        transport: transport,
      );

      expect(
        () => engine.bestMove(
          kInitialFen,
          level: EngineLevel.grandmaster,
          useCase: EngineUseCase.hint,
        ),
        throwsA(isA<EngineQuotaExceededException>()),
      );
    });
  });
}

class _FakeTransport implements PikafishTransport {
  _FakeTransport({this.getResponse, this.postError});

  final Map<String, dynamic>? getResponse;
  final Object? postError;
  Uri? getUri;

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    getUri = uri;
    return getResponse ?? const {};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    if (postError != null) throw postError!;
    return const {'uci': 'h2e2'};
  }

  @override
  void close() {}
}
