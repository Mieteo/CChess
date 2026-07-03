import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/core/chess_engine/remote_pikafish_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted transport for the async analyze-job protocol.
class _JobTransport extends PikafishTransport {
  _JobTransport({required this.onPost, this.getResponses = const []});

  final Map<String, dynamic> Function(Uri uri, Map<String, dynamic> body)
      onPost;
  final List<Map<String, dynamic>> getResponses;

  final List<(Uri, Duration)> postCalls = [];
  int getCalls = 0;

  @override
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    postCalls.add((uri, timeout));
    return onPost(uri, body);
  }

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final index = getCalls.clamp(0, getResponses.length - 1);
    getCalls++;
    return getResponses[index];
  }
}

const _perMoveJson = [
  {
    'moveIndex': 0,
    'uci': 'h2e2',
    'bestUci': 'h2e2',
    'scoreCp': 30,
    'actualScoreCp': -25,
    'evalAfterCp': -25,
    'centipawnLoss': 5,
    'classification': 'best',
    'depth': 14,
  },
  {
    'moveIndex': 1,
    'uci': 'h7e7',
    'bestUci': 'b7e7',
    'scoreCp': -25,
    'actualScoreCp': -40,
    'evalAfterCp': 40,
    'centipawnLoss': 15,
    'classification': 'excellent',
    'depth': 14,
  },
];

const _summaryJson = {
  'redAccuracy': 100.0,
  'blackAccuracy': 95.0,
  'redBlunders': 0,
  'blackBlunders': 0,
  'redMistakes': 0,
  'blackMistakes': 0,
};

RemotePikafishEngine _engine(PikafishTransport transport) =>
    RemotePikafishEngine(
      baseUri: Uri.parse('https://engine.test'),
      transport: transport,
      jobPollInterval: const Duration(milliseconds: 1),
    );

void main() {
  group('RemotePikafishEngine analyze via job API', () {
    test('submits a job, polls to done, maps evals red-perspective',
        () async {
      final transport = _JobTransport(
        onPost: (uri, body) {
          expect(uri.path, '/engine/analyze-jobs');
          expect(body['movesUci'], ['h2e2', 'h7e7']);
          return {
            'jobId': 'job-1',
            'status': 'queued',
            'progress': 0,
            'perMove': const [],
          };
        },
        getResponses: [
          {
            'jobId': 'job-1',
            'status': 'running',
            'progress': 0.5,
            'perMove': [_perMoveJson[0]],
          },
          {
            'jobId': 'job-1',
            'status': 'done',
            'progress': 1,
            'perMove': _perMoveJson,
            'summary': _summaryJson,
          },
        ],
      );

      final progress = <double>[];
      final analysis = await _engine(transport).analyze(
        startingFen: kInitialFen,
        moveUcis: ['h2e2', 'h7e7'],
        onProgress: progress.add,
      );

      expect(analysis.source, EngineSource.remotePikafish);
      expect(analysis.moves, hasLength(2));
      expect(analysis.redAccuracy, 100.0);
      // Black's mover-relative scoreCp −25 → Red-positive bestEval +25.
      expect(analysis.moves[1].bestEval, 25);
      expect(analysis.moves[1].evalAfterCp, 40);
      expect(analysis.moves[1].actualEval, 40);
      expect(analysis.moves[0].evalAfterCp, -25);
      // Real progress reached the UI, ending at 1.0.
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
      expect(transport.getCalls, 2);
    });

    test('falls back to the legacy endpoint (with a scaled timeout) on 404',
        () async {
      final transport = _JobTransport(
        onPost: (uri, body) {
          if (uri.path == '/engine/analyze-jobs') {
            throw const PikafishTransportException(
              code: 'not-found',
              message: 'no such route',
              statusCode: 404,
            );
          }
          expect(uri.path, '/engine/analyze');
          return {'perMove': _perMoveJson, 'summary': _summaryJson};
        },
      );

      final analysis = await _engine(transport).analyze(
        startingFen: kInitialFen,
        moveUcis: ['h2e2', 'h7e7'],
      );

      expect(analysis.moves, hasLength(2));
      expect(analysis.source, EngineSource.remotePikafish);
      // The legacy call must NOT reuse the short default timeout — 2 moves →
      // 2×800ms + 10s.
      final legacyCall = transport.postCalls.last;
      expect(legacyCall.$1.path, '/engine/analyze');
      expect(legacyCall.$2, const Duration(milliseconds: 11600));
    });

    test('surfaces a failed job as an error (no silent degradation)',
        () async {
      final transport = _JobTransport(
        onPost: (uri, body) => {
          'jobId': 'job-9',
          'status': 'queued',
          'progress': 0,
          'perMove': const [],
        },
        getResponses: [
          {
            'jobId': 'job-9',
            'status': 'error',
            'progress': 0.3,
            'perMove': const [],
            'error': {'code': 'engine-exit', 'message': 'boom'},
          },
        ],
      );

      await expectLater(
        _engine(transport).analyze(
          startingFen: kInitialFen,
          moveUcis: ['h2e2'],
        ),
        throwsA(isA<PikafishTransportException>()),
      );
    });
  });
}
