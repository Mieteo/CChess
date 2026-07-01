// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/datasources/remote/clubs_api_source.dart';
import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/repositories/club_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp.createTempSync('cchess_club_repo_').path;
    return _dir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() => _ensureDir();
  @override
  Future<String?> getApplicationSupportPath() => _ensureDir();
  @override
  Future<String?> getTemporaryPath() => _ensureDir();
}

/// Routes GET responses by the request path so listClubs() (which fires both
/// GET /clubs and GET /clubs/mine) can be exercised in one fake.
class _FakeTransport implements PuzzleApiTransport {
  final Map<String, Map<String, dynamic>> getResponses = {};
  Map<String, dynamic>? postResponse;
  Object? error;

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (error != null) throw error!;
    return getResponses[uri.path] ?? const {};
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

ClubsApiSource _source(_FakeTransport t) => ClubsApiSource(
  baseUri: Uri.parse('https://api.example.com'),
  transport: t,
  tokenProvider: () async => 'tok',
);

const _networkError = PuzzleApiException(code: 'network', message: 'offline');

Map<String, dynamic> _clubJson(String id) => {
  'id': id,
  'name': 'CLB $id',
  'region': 'Hà Nội',
  'description': '',
  'founderId': 'founder',
  'memberCount': 3,
  'weeklyScore': 50,
  'active': true,
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    final box = await Hive.openBox<dynamic>('cchess_clubs');
    await box.clear();
  });

  test('listClubs caches a successful fetch (with resolved membership) and serves it offline', () async {
    final t = _FakeTransport()
      ..getResponses['/clubs'] = {
        'clubs': [_clubJson('a'), _clubJson('b')],
      }
      ..getResponses['/clubs/mine'] = {
        'clubs': [
          {'clubId': 'a', 'role': 'member'},
        ],
      };
    final repo = ClubRepository(remote: _source(t));

    final online = await repo.listClubs();
    expect(online.length, 2);
    expect(online.firstWhere((c) => c.id == 'a').isMember, isTrue);
    expect(online.firstWhere((c) => c.id == 'b').isMember, isFalse);

    // Network drops — the repo should serve the cached (membership-resolved) list.
    t.error = _networkError;
    final offline = await repo.listClubs();
    expect(offline.map((c) => c.id), containsAll(['a', 'b']));
    expect(offline.firstWhere((c) => c.id == 'a').isMember, isTrue);
  });

  test('offline repo (no remote) falls back to the seed list, not an error', () async {
    final repo = ClubRepository();
    final clubs = await repo.listClubs();
    expect(clubs, isNotEmpty);
  });

  test('create/join/leave delegate to the remote source', () async {
    final t = _FakeTransport()..postResponse = _clubJson('new-club');
    final repo = ClubRepository(remote: _source(t));
    final created = await repo.create(name: 'CLB', region: 'HN', description: '');
    expect(created.id, 'new-club');

    t.postResponse = {..._clubJson('new-club'), 'memberCount': 4};
    final joined = await repo.join('new-club');
    expect(joined.memberCount, 4);

    t.postResponse = {'left': true};
    await repo.leave('new-club'); // should not throw
  });
}
