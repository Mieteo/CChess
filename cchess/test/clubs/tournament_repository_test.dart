// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/datasources/remote/tournaments_api_source.dart';
import 'package:cchess/data/repositories/tournament_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp.createTempSync('cchess_tournament_repo_').path;
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
    throw UnimplementedError();
  }

  @override
  void close() {}
}

TournamentsApiSource _source(_FakeTransport t) => TournamentsApiSource(
  baseUri: Uri.parse('https://api.example.com'),
  transport: t,
  tokenProvider: () async => 'tok',
);

const _networkError = PuzzleApiException(code: 'network', message: 'offline');

Map<String, dynamic> _tournamentJson(String id) => {
  'id': id,
  'name': 'CChess Open $id',
  'format': 'single_elimination',
  'status': 'registering',
  'startsAtMs': 1000,
  'capacity': 8,
  'participantCount': 2,
  'prize': '',
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    final box = await Hive.openBox<dynamic>('cchess_tournaments');
    await box.clear();
  });

  test('listTournaments caches a successful fetch and serves it offline', () async {
    final t = _FakeTransport()
      ..getResponse = {
        'tournaments': [_tournamentJson('a'), _tournamentJson('b')],
      };
    final repo = TournamentRepository(remote: _source(t));

    final online = await repo.listTournaments();
    expect(online.map((x) => x.id), ['a', 'b']);

    t.error = _networkError;
    final offline = await repo.listTournaments();
    expect(offline.map((x) => x.id), containsAll(['a', 'b']));
  });

  test('offline repo (no remote) falls back to the seed list, not an error', () async {
    final repo = TournamentRepository();
    final list = await repo.listTournaments();
    expect(list, isNotEmpty);
  });
}
