// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/datasources/remote/shop_api_source.dart';
import 'package:cchess/data/models/shop_item.dart';
import 'package:cchess/data/repositories/shop_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp.createTempSync('cchess_shop_repo_').path;
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

ShopApiSource _source(_FakeTransport t) => ShopApiSource(
      baseUri: Uri.parse('https://api.example.com'),
      transport: t,
      tokenProvider: () async => 'tok',
    );

const _networkError = PuzzleApiException(code: 'network', message: 'offline');

Map<String, dynamic> _itemJson(String id) => {
      'id': id,
      'kind': 'boardTheme',
      'nameVi': 'Bàn $id',
      'descVi': '',
      'priceCoins': 300,
      'priceGems': 0,
      'rarity': 'rare',
      'payloadKey': 'jade',
      'consumable': false,
      'consumableQty': 1,
      'sortOrder': 1,
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    final box = await Hive.openBox<dynamic>('cchess_shop');
    await box.clear();
  });

  test('catalog caches a successful fetch and serves it when offline', () async {
    final t = _FakeTransport()
      ..getResponse = {
        'items': [_itemJson('board_jade'), _itemJson('board_midnight')],
      };
    final repo = ShopRepository(remote: _source(t));

    final online = await repo.catalog();
    expect(online.length, 2);

    // Now the network drops — the repo should serve the cached catalog.
    t.error = _networkError;
    final offline = await repo.catalog();
    expect(offline.map((i) => i.id), containsAll(['board_jade', 'board_midnight']));
  });

  test('catalog filters cached items by kind', () async {
    final t = _FakeTransport()
      ..getResponse = {
        'items': [
          _itemJson('board_jade'),
          {..._itemJson('ink'), 'kind': 'pieceSet', 'payloadKey': 'ink'},
        ],
      };
    final repo = ShopRepository(remote: _source(t));
    await repo.catalog();
    t.error = _networkError;
    final boards = await repo.catalog(kind: ShopItemKind.boardTheme);
    expect(boards.map((i) => i.id), ['board_jade']);
  });

  test('purchase writes the debited wallet + new item to the cache', () async {
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
    final repo = ShopRepository(remote: _source(t));
    final item = ShopItem.fromJson(_itemJson('board_jade'));

    await repo.purchase(item, currency: 'coins');

    expect((await repo.cachedWallet()).coins, 200);
    final inv = await repo.cachedInventory();
    expect(inv.single.itemId, 'board_jade');
    expect(inv.single.payloadKey, 'jade');
  });

  test('equip caches the updated equipped loadout', () async {
    final t = _FakeTransport()
      ..postResponse = {
        'coins': 200,
        'gems': 0,
        'equipped': {'boardTheme': 'board_jade'},
      };
    final repo = ShopRepository(remote: _source(t));

    final wallet = await repo.equip(ShopItemKind.boardTheme, null);
    expect(wallet.equippedFor(ShopItemKind.boardTheme), 'board_jade');
    expect((await repo.cachedEquipped())['boardTheme'], 'board_jade');
  });

  test('offline repo (no remote) returns an empty catalog, not an error', () async {
    final repo = ShopRepository();
    expect(await repo.catalog(), isEmpty);
    expect((await repo.wallet()).coins, 0);
  });
}
