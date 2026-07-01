import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/datasources/remote/tournaments_api_source.dart';
import 'package:cchess/data/models/community_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements PuzzleApiTransport {
  Map<String, dynamic>? getResponse;
  Map<String, dynamic>? postResponse;
  Object? error;

  Uri? lastUri;
  String? lastMethod;
  Map<String, String>? lastHeaders;

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
    if (error != null) throw error!;
    return postResponse ?? const {};
  }

  @override
  void close() {}
}

TournamentsApiSource _source(_FakeTransport t, {String? token = 'tok'}) {
  return TournamentsApiSource(
    baseUri: Uri.parse('https://api.example.com'),
    transport: t,
    tokenProvider: () async => token,
  );
}

Map<String, dynamic> _tournamentJson(String id) => {
  'id': id,
  'name': 'CChess Open',
  'format': 'single_elimination',
  'status': 'registering',
  'createdBy': 'system',
  'startsAtMs': 1000,
  'registrationDeadlineMs': 500,
  'minElo': null,
  'maxElo': null,
  'capacity': 8,
  'participantCount': 2,
  'prize': '1000 xu',
  'rewards': <String, dynamic>{},
  'winnerUid': null,
};

void main() {
  test('listTournaments GETs /tournaments, no auth header', () async {
    final t = _FakeTransport()
      ..getResponse = {
        'tournaments': [_tournamentJson('a'), _tournamentJson('b')],
      };
    final list = await _source(t).listTournaments();
    expect(list.length, 2);
    expect(list.first.id, 'a');
    expect(t.lastUri.toString(), 'https://api.example.com/tournaments');
    expect(t.lastHeaders?.containsKey('authorization'), isFalse);
  });

  test('listMatches parses bracket rows', () async {
    final t = _FakeTransport()
      ..getResponse = {
        'matches': [
          {
            'id': 'r1_m0',
            'round': 1,
            'slotIndex': 0,
            'player1Id': 'p1',
            'player2Id': 'p2',
            'result': null,
            'roomId': null,
            'status': 'ready',
          },
        ],
      };
    final matches = await _source(t).listMatches('t1');
    expect(matches.single.id, 'r1_m0');
    expect(matches.single.status, TournamentMatchStatus.ready);
    expect(t.lastUri.toString(), 'https://api.example.com/tournaments/t1/matches');
  });

  test('register sends Bearer token and POSTs to /tournaments/:id/register', () async {
    final t = _FakeTransport()..postResponse = _tournamentJson('t1');
    final result = await _source(t).register('t1');
    expect(result.id, 't1');
    expect(t.lastUri.toString(), 'https://api.example.com/tournaments/t1/register');
    expect(t.lastHeaders?['authorization'], 'Bearer tok');
  });

  test('register throws 401 when signed out (no token)', () async {
    final t = _FakeTransport()..postResponse = {};
    await expectLater(
      _source(t, token: null).register('t1'),
      throwsA(isA<TournamentApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('register maps a 409 tournament-full error', () async {
    final t = _FakeTransport()
      ..error = const PuzzleApiException(statusCode: 409, code: 'tournament-full', message: 'full');
    await expectLater(
      _source(t).register('t1'),
      throwsA(isA<TournamentApiException>().having((e) => e.code, 'code', 'tournament-full')),
    );
  });

  test('getTournament returns null on 404', () async {
    final t = _FakeTransport()
      ..error = const PuzzleApiException(statusCode: 404, code: 'not-found', message: 'gone');
    expect(await _source(t).getTournament('nope'), isNull);
  });
}
