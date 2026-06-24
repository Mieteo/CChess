// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/datasources/remote/remote_puzzle_source.dart';
import 'package:cchess/data/repositories/puzzle_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp.createTempSync('cchess_puzzle_repo_').path;
    return _dir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() => _ensureDir();
  @override
  Future<String?> getApplicationSupportPath() => _ensureDir();
  @override
  Future<String?> getTemporaryPath() => _ensureDir();
}

class _FakeTransport implements PuzzleApiTransport {
  Map<String, dynamic>? getResponse;
  Map<String, dynamic>? postResponse;
  Object? error;

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
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
    if (error != null) throw error!;
    return postResponse ?? const {};
  }

  @override
  void close() {}
}

RemotePuzzleSource _source(_FakeTransport t, {String? token = 'tok'}) {
  return RemotePuzzleSource(
    baseUri: Uri.parse('https://api.example.com'),
    transport: t,
    tokenProvider: () async => token,
  );
}

const _networkError =
    PuzzleApiException(code: 'network', message: 'offline');

Map<String, dynamic> _puzzleJson(String id, {int difficulty = 2}) => {
      'id': id,
      'fen': '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
      'solution': ['a0a1'],
      'titleVi': 'Remote $id',
      'descriptionVi': 'from server',
      'tags': ['Tàn cục'],
      'difficulty': difficulty,
      'category': 'capture',
      'theme': '',
      'solveRateGlobal': 0.5,
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    final progress = await Hive.openBox<dynamic>('cchess_puzzle_progress');
    final cache = await Hive.openBox<dynamic>('cchess_puzzle_cache');
    await progress.clear();
    await cache.clear();
  });

  group('offline fallback (no remote)', () {
    test('fetchPuzzles returns the seed catalog filtered by difficulty', () async {
      final repo = PuzzleRepository();
      final page = await repo.fetchPuzzles(difficulty: 1);
      expect(page.puzzles, isNotEmpty);
      expect(page.puzzles.every((p) => p.difficulty == 1), isTrue);
      expect(page.hasMore, isFalse);
    });

    test('fetchPuzzleById falls back to the seed', () async {
      final repo = PuzzleRepository();
      final p = await repo.fetchPuzzleById('p001');
      expect(p, isNotNull);
      expect(p!.id, 'p001');
    });
  });

  group('remote success caches for offline', () {
    test('fetched puzzles are served from cache when the network drops',
        () async {
      final transport = _FakeTransport()
        ..getResponse = {
          'puzzles': [_puzzleJson('r1')],
          'hasMore': false,
          'nextCursor': null,
        };
      final repo = PuzzleRepository(remote: _source(transport));

      final online = await repo.fetchPuzzles();
      expect(online.puzzles.map((p) => p.id), contains('r1'));

      // Network drops on the next call → fall back to cache + seed.
      transport.error = _networkError;
      final offline = await repo.fetchPuzzles();
      expect(offline.puzzles.map((p) => p.id), contains('r1'));
      // Seed is still present in the merged local catalog.
      expect(offline.puzzles.map((p) => p.id), contains('p001'));
    });

    test('fetchPuzzleById uses cache after a successful fetch', () async {
      final transport = _FakeTransport()
        ..getResponse = _puzzleJson('r9', difficulty: 4);
      final repo = PuzzleRepository(remote: _source(transport));

      final fetched = await repo.fetchPuzzleById('r9');
      expect(fetched!.difficulty, 4);

      transport.error = _networkError;
      final cached = await repo.fetchPuzzleById('r9');
      expect(cached, isNotNull);
      expect(cached!.id, 'r9');
    });
  });

  group('progress sync', () {
    test('syncProgress merges the server bestScore into local', () async {
      final transport = _FakeTransport()
        ..postResponse = {
          'puzzleId': 'p001',
          'solved': true,
          'attempts': 2,
          'hintsUsed': 0,
          'bestScore': 80,
          'solvedAtMs': 1_700_000_000_000,
          'updatedAtMs': 1_700_000_000_000,
        };
      final repo = PuzzleRepository(remote: _source(transport));

      final merged = await repo.syncProgress('p001', solved: true, score: 80);
      expect(merged.solved, isTrue);
      expect(merged.bestScore, 80);

      // Persisted locally too.
      final reread = await repo.getProgress('p001');
      expect(reread.bestScore, 80);
      expect(reread.solved, isTrue);
    });

    test('syncProgress returns local progress when the server is unreachable',
        () async {
      final transport = _FakeTransport()..error = _networkError;
      final repo = PuzzleRepository(remote: _source(transport));

      final result = await repo.syncProgress('p002', solved: true, score: 50);
      // No crash, returns the (default) local entry; nothing was merged.
      expect(result.puzzleId, 'p002');
      expect(result.bestScore, 0);
    });

    test('recordAttempt works offline (no remote configured)', () async {
      final repo = PuzzleRepository();
      final p = await repo.recordAttempt('p001', solved: true, score: 70);
      expect(p.attempts, 1);
      expect(p.solved, isTrue);
      expect(p.bestScore, 70);
    });

    test('recordAttempt accumulates hints and skips mirror when asked',
        () async {
      final repo = PuzzleRepository();
      await repo.recordAttempt('p001', hintsUsed: 2, mirror: false);
      final p = await repo.recordAttempt('p001', solved: true, score: 90,
          hintsUsed: 1, mirror: false);
      expect(p.attempts, 2);
      expect(p.hintsUsed, 3);
      expect(p.bestScore, 90);
    });
  });

  group('stats', () {
    test('getProgressForIds defaults unknown ids', () async {
      final repo = PuzzleRepository();
      final map = await repo.getProgressForIds(['p001', 'zzz']);
      expect(map.keys, containsAll(['p001', 'zzz']));
      expect(map['zzz']!.attempts, 0);
      expect(map['zzz']!.solved, isFalse);
    });

    test('computeStats aggregates progress with difficulty buckets', () async {
      final repo = PuzzleRepository();
      // p001 is a difficulty-1 seed puzzle.
      await repo.recordAttempt('p001', solved: true, score: 80, mirror: false);
      // p020 is a difficulty-3 seed puzzle, attempted but unsolved.
      await repo.recordAttempt('p020', mirror: false);

      final stats = await repo.computeStats();
      expect(stats.attempted, 2);
      expect(stats.solved, 1);
      expect(stats.catalogSize, greaterThanOrEqualTo(2));
      expect(stats.averageScore, 80);
      expect(stats.solveRate, closeTo(0.5, 1e-9));

      final d1 = stats.byDifficulty.firstWhere((b) => b.difficulty == 1);
      expect(d1.solved, 1);
      expect(d1.attempted, 1);
    });
  });
}
