// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/datasources/remote/economy_api_source.dart';
import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/models/economy_models.dart';
import 'package:cchess/data/models/shop_item.dart';
import 'package:cchess/data/repositories/economy_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp.createTempSync('cchess_economy_repo_').path;
    return _dir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() => _ensureDir();
  @override
  Future<String?> getApplicationSupportPath() => _ensureDir();
  @override
  Future<String?> getTemporaryPath() => _ensureDir();
}

/// Routes each URI path to a canned response, so one fake covers every
/// economy endpoint. Set [error] to throw instead (network failure).
class _FakeTransport implements PuzzleApiTransport {
  final Map<String, Map<String, dynamic>> responses = {};
  Object? error;
  final List<String> calls = [];

  /// Last JSON body sent per POST path, so tests can assert the wire format.
  final Map<String, Map<String, dynamic>> bodies = {};

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add('GET ${uri.path}');
    if (error != null) throw error!;
    return responses[uri.path] ?? const {};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    Map<String, String> headers = const {},
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add('POST ${uri.path}');
    bodies[uri.path] = body;
    if (error != null) throw error!;
    return responses[uri.path] ?? const {};
  }

  @override
  void close() {}
}

const _networkError = PuzzleApiException(code: 'network', message: 'offline');

EconomyRepository _repo(_FakeTransport t) => EconomyRepository(
      remote: EconomyApiSource(
        baseUri: Uri.parse('https://api.example.com'),
        transport: t,
        tokenProvider: () async => 'tok',
      ),
    );

Map<String, dynamic> _mailJson(String id, {bool claimed = false}) => {
      'id': id,
      'title': 'Quà $id',
      'body': 'Nội dung',
      'reward': {'coins': 50, 'gems': 0, 'items': []},
      'read': false,
      'claimed': claimed,
      'createdAtMs': 1000,
      'expiresAtMs': null,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('cchess_economy');
  });

  group('mail', () {
    test('fetches from backend and caches; falls back to cache offline',
        () async {
      final t = _FakeTransport();
      t.responses['/mail'] = {
        'messages': [_mailJson('m1'), _mailJson('m2')],
      };
      final repo = _repo(t);
      final fresh = await repo.mail();
      expect(fresh.length, 2);
      expect(fresh.first.hasUnclaimedReward, isTrue);

      t.error = _networkError;
      final cached = await repo.mail();
      expect(cached.map((m) => m.id), ['m1', 'm2']);
    });

    test('claimMail returns wallet + reward and patches the cache', () async {
      final t = _FakeTransport();
      t.responses['/mail'] = {
        'messages': [_mailJson('m1')],
      };
      t.responses['/mail/m1/claim'] = {
        'wallet': {'coins': 150, 'gems': 3, 'equipped': {}},
        'reward': {'coins': 50, 'gems': 0, 'items': []},
      };
      final repo = _repo(t);
      await repo.mail();

      final outcome = await repo.claimMail('m1');
      expect(outcome.wallet.coins, 150);
      expect(outcome.reward.coins, 50);

      // Cached copy now reads claimed → not claimable again offline.
      t.error = _networkError;
      final cached = await repo.mail();
      expect(cached.single.claimed, isTrue);
      expect(cached.single.hasUnclaimedReward, isFalse);
    });

    test('unreadMailCount counts unread + unclaimed', () async {
      final t = _FakeTransport();
      t.responses['/mail'] = {
        'messages': [
          _mailJson('m1'), // unread + unclaimed
          _mailJson('m2', claimed: true)..['read'] = true, // done
        ],
      };
      final repo = _repo(t);
      await repo.mail();
      expect(await repo.unreadMailCount(), 1);
    });

    test('mutations require the server', () async {
      final repo = EconomyRepository(remote: null);
      expect(() => repo.claimMail('m1'), throwsA(isA<EconomyApiException>()));
      expect(() => repo.checkin(), throwsA(isA<EconomyApiException>()));
      expect(() => repo.craft('r1'), throwsA(isA<EconomyApiException>()));
    });

    test('markMailRead patches the cached copy', () async {
      final t = _FakeTransport();
      t.responses['/mail'] = {
        'messages': [_mailJson('m1')],
      };
      final repo = _repo(t);
      await repo.mail();

      await repo.markMailRead('m1');
      expect(t.calls, contains('POST /mail/m1/read'));

      // Offline reload sees the read flag from the cache.
      t.error = _networkError;
      expect((await repo.mail()).single.read, isTrue);
    });

    test('deleteMail removes the message from the cache', () async {
      final t = _FakeTransport();
      t.responses['/mail'] = {
        'messages': [_mailJson('m1'), _mailJson('m2')],
      };
      final repo = _repo(t);
      await repo.mail();

      await repo.deleteMail('m1');
      expect(t.calls, contains('POST /mail/m1/delete'));

      t.error = _networkError;
      expect((await repo.mail()).map((m) => m.id), ['m2']);
    });
  });

  group('events', () {
    test('lists events and remembers claims across offline reloads', () async {
      final t = _FakeTransport();
      t.responses['/events'] = {
        'events': [
          {
            'id': 'tet',
            'title': 'Tết',
            'descVi': '',
            'startAtMs': 1,
            'endAtMs': 2,
            'gifts': [
              {
                'id': 'lixi',
                'title': 'Lì xì',
                'reward': {'coins': 88, 'gems': 0, 'items': []},
              },
            ],
          },
        ],
      };
      t.responses['/events/claims'] = {
        'claims': [
          {'eventId': 'tet', 'giftId': 'lixi'},
        ],
      };
      final repo = _repo(t);
      final events = await repo.events();
      expect(events.single.gifts.single.reward.coins, 88);
      final claims = await repo.eventClaims();
      expect(claims, {'tet__lixi'});

      t.error = _networkError;
      expect((await repo.events()).single.id, 'tet');
      expect(await repo.eventClaims(), {'tet__lixi'});
    });

    test('claimEventGift records the claim key locally and sends giftId', () async {
      final t = _FakeTransport();
      t.responses['/events/tet/claim'] = {
        'wallet': {'coins': 88, 'gems': 0, 'equipped': {}},
        'reward': {'coins': 88, 'gems': 0, 'items': []},
      };
      final repo = _repo(t);
      final outcome = await repo.claimEventGift('tet', 'lixi');
      expect(outcome.wallet.coins, 88);
      expect(t.bodies['/events/tet/claim'], {'giftId': 'lixi'});

      t.error = _networkError;
      expect(await repo.eventClaims(), {'tet__lixi'});
    });
  });

  group('api source auth + errors', () {
    test('personal reads without a token → 401 missing-token; public reads OK',
        () async {
      final t = _FakeTransport();
      t.responses['/events'] = {'events': []};
      t.responses['/crafting'] = {'recipes': []};
      final source = EconomyApiSource(
        baseUri: Uri.parse('https://api.example.com'),
        transport: t,
        tokenProvider: () async => null,
      );

      // Catalog reads need no auth.
      expect(await source.listEvents(), isEmpty);
      expect(await source.listRecipes(), isEmpty);

      // The personal surface fails fast with a 401 before hitting the wire.
      for (final call in <Future<Object?> Function()>[
        source.listMail,
        source.getWelfare,
        source.listEventClaims,
        source.checkin,
        () => source.claimMail('m1'),
        () => source.craft('r1'),
      ]) {
        await expectLater(
          call,
          throwsA(isA<EconomyApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', 'missing-token')),
        );
      }
      expect(t.calls.where((c) => c.startsWith('POST')), isEmpty);
    });

    test('a 409 from the backend maps to isAlreadyClaimed', () async {
      final t = _FakeTransport();
      t.error = const PuzzleApiException(
        statusCode: 409,
        code: 'already-claimed',
        message: 'Gift already claimed',
      );
      final source = EconomyApiSource(
        baseUri: Uri.parse('https://api.example.com'),
        transport: t,
        tokenProvider: () async => 'tok',
      );
      await expectLater(
        () => source.claimEventGift('tet', 'lixi'),
        throwsA(isA<EconomyApiException>()
            .having((e) => e.isAlreadyClaimed, 'isAlreadyClaimed', isTrue)
            .having((e) => e.isNetworkError, 'isNetworkError', isFalse)),
      );
    });
  });

  group('welfare offline', () {
    test('no server + no cache → default empty status (nothing claimable)',
        () async {
      final repo = EconomyRepository(remote: null);
      final status = await repo.welfare();
      expect(status.streak, 0);
      expect(status.todayClaimed, isFalse);
      expect(status.comebackAvailable, isFalse);
      expect(status.cycle, isEmpty);
    });

    test('no server + no cache → empty event claims', () async {
      final repo = EconomyRepository(remote: null);
      expect(await repo.eventClaims(), isEmpty);
    });
  });

  group('welfare', () {
    Map<String, dynamic> statusJson({bool todayClaimed = false, int streak = 1}) => {
          'streak': streak,
          'totalCheckins': streak,
          'lastCheckinDate': '2026-07-23',
          'todayClaimed': todayClaimed,
          'todayIndex': streak - 1,
          'newbieClaimed': false,
          'comebackAvailable': false,
          'cycle': [
            {'coins': 20, 'gems': 0, 'items': []},
            {'coins': 30, 'gems': 0, 'items': []},
          ],
        };

    test('status fetch caches; checkin stores refreshed status', () async {
      final t = _FakeTransport();
      t.responses['/welfare'] = statusJson();
      t.responses['/welfare/checkin'] = {
        'wallet': {'coins': 120, 'gems': 10, 'equipped': {}},
        'reward': {'coins': 20, 'gems': 0, 'items': []},
        'status': statusJson(todayClaimed: true),
      };
      final repo = _repo(t);
      expect((await repo.welfare()).todayClaimed, isFalse);

      final outcome = await repo.checkin();
      expect(outcome.reward.coins, 20);
      expect(outcome.status.todayClaimed, isTrue);

      // Offline reload shows the post-check-in status from the cache.
      t.error = _networkError;
      expect((await repo.welfare()).todayClaimed, isTrue);
    });
  });

  group('crafting', () {
    test('recipes cache offline; craft returns wallet + item', () async {
      final t = _FakeTransport();
      t.responses['/crafting'] = {
        'recipes': [
          {
            'id': 'jade',
            'nameVi': 'Bàn Ngọc',
            'descVi': '',
            'ingredients': [
              {'itemId': 'shard', 'qty': 3},
            ],
            'costCoins': 200,
            'output': {
              'itemId': 'jade-board',
              'kind': 'boardTheme',
              'payloadKey': 'jade',
              'qty': 1,
            },
          },
        ],
      };
      t.responses['/crafting/jade/craft'] = {
        'wallet': {'coins': 0, 'gems': 0, 'equipped': {}},
        'item': {
          'itemId': 'jade-board',
          'kind': 'boardTheme',
          'payloadKey': 'jade',
          'qty': 1,
        },
      };
      final repo = _repo(t);
      final recipes = await repo.recipes();
      expect(recipes.single.ingredients.single.qty, 3);

      final outcome = await repo.craft('jade');
      expect(outcome.item.itemId, 'jade-board');

      t.error = _networkError;
      expect((await repo.recipes()).single.id, 'jade');
    });
  });

  group('models', () {
    test('MailMessage/EconEvent/WelfareStatus/CraftRecipe JSON round-trip', () {
      final mail = MailMessage.fromJson(_mailJson('m9'));
      expect(MailMessage.fromJson(mail.toJson()), mail);

      const event = EconEvent(
        id: 'e',
        title: 'E',
        startAtMs: 1,
        endAtMs: 2,
        gifts: [
          EventGift(
            id: 'g',
            title: 'G',
            reward: RewardBundle(coins: 1),
          ),
        ],
      );
      expect(EconEvent.fromJson(event.toJson()), event);

      const status = WelfareStatus(
        streak: 3,
        totalCheckins: 9,
        lastCheckinDate: '2026-07-23',
        todayClaimed: true,
        todayIndex: 2,
        cycle: [RewardBundle(coins: 20)],
      );
      expect(WelfareStatus.fromJson(status.toJson()), status);
    });

    test('empty reward normalizes to null on MailMessage', () {
      final m = MailMessage.fromJson({
        'id': 'x',
        'title': 'Thông báo',
        'reward': {'coins': 0, 'gems': 0, 'items': []},
      });
      expect(m.reward, isNull);
      expect(m.hasUnclaimedReward, isFalse);
    });

    test('malformed JSON fields fall back to safe defaults', () {
      final mail = MailMessage.fromJson({
        'id': 1, // wrong type
        'title': null,
        'reward': 'junk',
        'read': 'yes',
        'createdAtMs': 'sớm',
      });
      expect(mail.id, '');
      expect(mail.title, '');
      expect(mail.reward, isNull);
      expect(mail.read, isFalse);
      expect(mail.createdAtMs, isNull);

      final event = EconEvent.fromJson({'id': 'e', 'gifts': 'junk'});
      expect(event.gifts, isEmpty);
      expect(event.startAtMs, 0);

      // Recipe missing its output still parses (screen renders it disabled).
      final recipe = CraftRecipe.fromJson({'id': 'r', 'nameVi': 'x'});
      expect(recipe.output.itemId, '');
      expect(recipe.ingredients, isEmpty);
      expect(recipe.costCoins, 0);

      final welfare = WelfareStatus.fromJson({'streak': '3', 'cycle': 'junk'});
      expect(welfare.streak, 0);
      expect(welfare.cycle, isEmpty);
    });

    test('RewardItem qty defaults to 1; unknown kind falls back to consumable',
        () {
      final item = RewardItem.fromJson({
        'itemId': 'x',
        'kind': 'không-tồn-tại',
        'payloadKey': 'p',
      });
      expect(item.qty, 1);
      expect(item.kind, ShopItemKind.consumable);
    });

    test('RewardBundle.isEmpty treats non-positive amounts as empty', () {
      expect(const RewardBundle().isEmpty, isTrue);
      expect(const RewardBundle(coins: -5).isEmpty, isTrue);
      expect(const RewardBundle(gems: 1).isEmpty, isFalse);
      expect(
        const RewardBundle(items: [
          RewardItem(itemId: 'x', kind: ShopItemKind.consumable, payloadKey: 'p'),
        ]).isEmpty,
        isFalse,
      );
    });
  });
}
