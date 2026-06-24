import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/datasources/remote/shop_api_source.dart';
import 'package:cchess/data/models/shop_item.dart';
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

ShopApiSource _source(_FakeTransport t, {String? token = 'tok'}) {
  return ShopApiSource(
    baseUri: Uri.parse('https://api.example.com'),
    transport: t,
    tokenProvider: () async => token,
  );
}

Map<String, dynamic> _itemJson(String id, {String kind = 'boardTheme'}) => {
      'id': id,
      'kind': kind,
      'nameVi': 'Item $id',
      'descVi': 'desc',
      'priceCoins': 300,
      'priceGems': 0,
      'rarity': 'rare',
      'payloadKey': 'jade',
      'consumable': false,
      'consumableQty': 1,
      'sortOrder': 1,
    };

void main() {
  group('listItems', () {
    test('GET /shop parses items, no auth header', () async {
      final t = _FakeTransport()
        ..getResponse = {
          'items': [_itemJson('jade'), _itemJson('ink', kind: 'pieceSet')],
        };
      final items = await _source(t).listItems();
      expect(items.length, 2);
      expect(items.first.id, 'jade');
      expect(items.first.kind, ShopItemKind.boardTheme);
      expect(t.lastUri.toString(), 'https://api.example.com/shop');
      expect(t.lastHeaders?.containsKey('authorization'), isFalse);
    });

    test('passes ?kind= filter', () async {
      final t = _FakeTransport()..getResponse = {'items': []};
      await _source(t).listItems(kind: ShopItemKind.pieceSet);
      expect(t.lastUri!.queryParameters['kind'], 'pieceSet');
    });
  });

  group('getWallet', () {
    test('sends Bearer token and parses wallet + equipped', () async {
      final t = _FakeTransport()
        ..getResponse = {
          'coins': 250,
          'gems': 12,
          'equipped': {'boardTheme': 'board_jade'},
        };
      final w = await _source(t).getWallet();
      expect(w.coins, 250);
      expect(w.gems, 12);
      expect(w.equippedFor(ShopItemKind.boardTheme), 'board_jade');
      expect(t.lastHeaders?['authorization'], 'Bearer tok');
    });

    test('throws 401 when signed out (no token)', () async {
      final t = _FakeTransport()..getResponse = {};
      await expectLater(
        _source(t, token: null).getWallet(),
        throwsA(isA<ShopApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('purchase', () {
    test('POSTs currency and parses wallet + granted item', () async {
      final t = _FakeTransport()
        ..postResponse = {
          'wallet': {'coins': 200, 'gems': 0, 'equipped': {}},
          'item': {
            'itemId': 'board_jade',
            'kind': 'boardTheme',
            'payloadKey': 'jade',
            'qty': 1,
          },
        };
      final out = await _source(t).purchase('board_jade', currency: 'coins');
      expect(out.wallet.coins, 200);
      expect(out.item.itemId, 'board_jade');
      expect(out.item.payloadKey, 'jade');
      expect(t.lastUri.toString(),
          'https://api.example.com/shop/board_jade/purchase');
      expect(t.lastBody?['currency'], 'coins');
    });

    test('maps a 402 into an insufficient-funds exception', () async {
      final t = _FakeTransport()
        ..error = const PuzzleApiException(
          statusCode: 402,
          code: 'insufficient-funds',
          message: 'Not enough coins',
        );
      await expectLater(
        _source(t).purchase('board_jade', currency: 'coins'),
        throwsA(isA<ShopApiException>()
            .having((e) => e.isInsufficientFunds, 'isInsufficientFunds', true)),
      );
    });
  });

  group('equip', () {
    test('POSTs kind + itemId and parses wallet', () async {
      final t = _FakeTransport()
        ..postResponse = {
          'coins': 200,
          'gems': 0,
          'equipped': {'boardTheme': 'board_jade'},
        };
      final w = await _source(t).equip(ShopItemKind.boardTheme, 'board_jade');
      expect(w.equippedFor(ShopItemKind.boardTheme), 'board_jade');
      expect(t.lastUri.toString(), 'https://api.example.com/inventory/equip');
      expect(t.lastBody?['kind'], 'boardTheme');
      expect(t.lastBody?['itemId'], 'board_jade');
    });

    test('unequip sends itemId: null', () async {
      final t = _FakeTransport()
        ..postResponse = {'coins': 0, 'gems': 0, 'equipped': {}};
      await _source(t).equip(ShopItemKind.boardTheme, null);
      expect(t.lastBody!.containsKey('itemId'), isTrue);
      expect(t.lastBody!['itemId'], isNull);
    });
  });

  test('getItem returns null on 404', () async {
    final t = _FakeTransport()
      ..error = const PuzzleApiException(
        statusCode: 404,
        code: 'not-found',
        message: 'gone',
      );
    expect(await _source(t).getItem('nope'), isNull);
  });
}
