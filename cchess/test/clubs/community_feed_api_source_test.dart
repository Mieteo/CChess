import 'package:cchess/data/datasources/remote/community_feed_api_source.dart';
import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements PuzzleApiTransport {
  Map<String, dynamic>? getResponse;
  Object? error;
  Uri? lastUri;

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastUri = uri;
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

void main() {
  test('listFeed GETs /community/feed and parses items', () async {
    final t = _FakeTransport()
      ..getResponse = {
        'items': [
          {
            'id': 'daily-endgame',
            'type': 'puzzle',
            'title': 'Tàn Cục Thách Đấu',
            'subtitle': 'Chiếu hết 3 nước',
            'meta': '488 kỳ thủ đã thử',
            'route': 'daily_puzzle',
          },
          {
            'id': 'news-1',
            'type': 'news',
            'title': 'Tin tức',
            'subtitle': 'Nội dung',
            'meta': '',
            'linkUrl': 'https://example.com/a',
          },
        ],
      };
    final source = CommunityFeedApiSource(baseUri: Uri.parse('https://api.example.com'), transport: t);
    final items = await source.listFeed();
    expect(items.length, 2);
    expect(items.first.route, 'daily_puzzle');
    expect(items.last.linkUrl, 'https://example.com/a');
    expect(t.lastUri.toString(), 'https://api.example.com/community/feed');
  });

  test('wraps a transport error into FeedApiException', () async {
    final t = _FakeTransport()..error = const PuzzleApiException(code: 'network', message: 'offline');
    final source = CommunityFeedApiSource(baseUri: Uri.parse('https://api.example.com'), transport: t);
    await expectLater(source.listFeed(), throwsA(isA<FeedApiException>()));
  });
}
