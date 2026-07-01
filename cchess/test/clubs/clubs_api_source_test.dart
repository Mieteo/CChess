import 'package:cchess/data/datasources/remote/clubs_api_source.dart';
import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the last request and replays a canned response (or throws).
class _FakeTransport implements PuzzleApiTransport {
  Map<String, dynamic>? getResponse;
  Map<String, dynamic>? postResponse;
  Object? error;

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

ClubsApiSource _source(_FakeTransport t, {String? token = 'tok'}) {
  return ClubsApiSource(
    baseUri: Uri.parse('https://api.example.com'),
    transport: t,
    tokenProvider: () async => token,
  );
}

Map<String, dynamic> _clubJson(String id, {bool isMember = false}) => {
  'id': id,
  'name': 'CLB $id',
  'region': 'Hà Nội',
  'description': 'Vui vẻ',
  'founderId': 'founder',
  'memberCount': 5,
  'weeklyScore': 100,
  'active': true,
  'isMember': isMember,
};

void main() {
  group('listClubs', () {
    test('GET /clubs parses clubs, no auth header', () async {
      final t = _FakeTransport()
        ..getResponse = {
          'clubs': [_clubJson('a'), _clubJson('b')],
        };
      final clubs = await _source(t).listClubs();
      expect(clubs.length, 2);
      expect(clubs.first.id, 'a');
      expect(t.lastUri.toString(), 'https://api.example.com/clubs');
      expect(t.lastHeaders?.containsKey('authorization'), isFalse);
    });
  });

  group('listMine', () {
    test('sends Bearer token and parses club ids/roles', () async {
      final t = _FakeTransport()
        ..getResponse = {
          'clubs': [
            {'clubId': 'a', 'role': 'owner'},
          ],
        };
      final mine = await _source(t).listMine();
      expect(mine.single.clubId, 'a');
      expect(t.lastHeaders?['authorization'], 'Bearer tok');
    });

    test('throws 401 when signed out (no token)', () async {
      final t = _FakeTransport()..getResponse = {};
      await expectLater(
        _source(t, token: null).listMine(),
        throwsA(isA<ClubApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('create', () {
    test('POSTs name/region/description and parses the created club', () async {
      final t = _FakeTransport()..postResponse = _clubJson('new-club');
      final club = await _source(t).create(name: 'CLB', region: 'HN', description: 'desc');
      expect(club.id, 'new-club');
      expect(t.lastUri.toString(), 'https://api.example.com/clubs');
      expect(t.lastBody?['name'], 'CLB');
    });
  });

  group('join / leave', () {
    test('join POSTs to /clubs/:id/join and parses the updated club', () async {
      final t = _FakeTransport()..postResponse = _clubJson('a', isMember: true);
      final club = await _source(t).join('a');
      expect(club.isMember, isTrue);
      expect(t.lastUri.toString(), 'https://api.example.com/clubs/a/join');
    });

    test('join maps a 409 into club-limit-reached', () async {
      final t = _FakeTransport()
        ..error = const PuzzleApiException(
          statusCode: 409,
          code: 'club-limit-reached',
          message: 'too many clubs',
        );
      await expectLater(
        _source(t).join('a'),
        throwsA(isA<ClubApiException>().having((e) => e.code, 'code', 'club-limit-reached')),
      );
    });

    test('leave POSTs to /clubs/:id/leave', () async {
      final t = _FakeTransport()..postResponse = {'left': true};
      await _source(t).leave('a');
      expect(t.lastUri.toString(), 'https://api.example.com/clubs/a/leave');
    });
  });

  test('getClub returns null on 404', () async {
    final t = _FakeTransport()
      ..error = const PuzzleApiException(statusCode: 404, code: 'not-found', message: 'gone');
    expect(await _source(t).getClub('nope'), isNull);
  });
}
