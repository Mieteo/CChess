// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/datasources/remote/economy_api_source.dart';
import 'package:cchess/data/datasources/remote/puzzle_api_transport.dart';
import 'package:cchess/data/models/economy_models.dart';
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

    test('claimEventGift records the claim key locally', () async {
      final t = _FakeTransport();
      t.responses['/events/tet/claim'] = {
        'wallet': {'coins': 88, 'gems': 0, 'equipped': {}},
        'reward': {'coins': 88, 'gems': 0, 'items': []},
      };
      final repo = _repo(t);
      final outcome = await repo.claimEventGift('tet', 'lixi');
      expect(outcome.wallet.coins, 88);

      t.error = _networkError;
      expect(await repo.eventClaims(), {'tet__lixi'});
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
  });
}
