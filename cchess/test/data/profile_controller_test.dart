// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/repositories/profile_repository.dart';
import 'package:cchess/data/repositories/user_remote_repository.dart';
import 'package:cchess/presentation/profile/profile_controller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp.createTempSync('cchess_profilectrl_').path;
    return _dir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() => _ensureDir();
  @override
  Future<String?> getApplicationSupportPath() => _ensureDir();
  @override
  Future<String?> getTemporaryPath() => _ensureDir();
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
}

class _FakeAuth extends Fake implements FirebaseAuth {
  _FakeAuth(this._user);
  final User? _user;
  @override
  User? get currentUser => _user;
}

class _FakeRemote extends Fake implements UserRemoteRepository {
  final List<Map<String, dynamic>> fieldUpdates = [];

  @override
  Future<void> updateProfileFields(
    String uid, {
    String? displayName,
    String? region,
    String? avatarUrl,
    bool? onboardingCompleted,
    int? eloBot,
    int? botGames,
    int? botWins,
    int? botLosses,
    int? botDraws,
  }) async {
    fieldUpdates.add({
      'uid': uid,
      'displayName': displayName,
      'region': region,
      'onboardingCompleted': onboardingCompleted,
    });
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    final p = await Hive.openBox<dynamic>('cchess_profile');
    await p.clear();
  });

  group('ProfileController mutations right after construction', () {
    test(
        'completeOnboarding persists even when called before the initial load '
        'finishes (S16 QA: onboarding lost on force-stop)', () async {
      // Mirrors OnboardingScreen._finish: the very first read of the provider
      // constructs the controller (state = loading) and immediately calls
      // completeOnboarding. The old update() saw loading and dropped the
      // mutation silently.
      final controller = ProfileController(
        ProfileRepository(),
        _FakeRemote(),
        _FakeAuth(null),
      );
      await controller.completeOnboarding(
        displayName: 'Trần Kỳ Thủ',
        region: 'Huế',
      );

      final persisted = await ProfileRepository().loadOrCreate();
      expect(persisted.onboardingCompleted, isTrue,
          reason: 'the flag must reach Hive — a force-stop must not lose it');
      expect(persisted.displayName, 'Trần Kỳ Thủ');
      expect(persisted.region, 'Huế');

      // In-memory state ends on the mutated profile (not clobbered by the
      // racing initial load).
      expect(controller.state.value?.displayName, 'Trần Kỳ Thủ');
      expect(controller.state.value?.onboardingCompleted, isTrue);
    });

    test('the whitelist push still fires when signed in', () async {
      final remote = _FakeRemote();
      final controller = ProfileController(
        ProfileRepository(),
        remote,
        _FakeAuth(_FakeUser('uid-9')),
      );
      await controller.completeOnboarding(
        displayName: 'Trần Kỳ Thủ',
        region: 'Huế',
      );

      expect(remote.fieldUpdates, hasLength(1));
      final push = remote.fieldUpdates.single;
      expect(push['uid'], 'uid-9');
      expect(push['onboardingCompleted'], isTrue);
      expect(push['displayName'], 'Trần Kỳ Thủ');
    });

    test('applyGameResult right after construction is not dropped either',
        () async {
      final seedRepo = ProfileRepository();
      final seeded = await seedRepo.loadOrCreate();
      await seedRepo.save(seeded.copyWith(eloBot: 1200, botGames: 3));

      final controller = ProfileController(
        ProfileRepository(),
        _FakeRemote(),
        _FakeAuth(null),
      );
      await controller.applyGameResult(eloDelta: 16, won: true, drew: false);

      final persisted = await ProfileRepository().loadOrCreate();
      expect(persisted.eloBot, 1216);
      expect(persisted.botGames, 4);
      expect(persisted.botWins, 1);
    });

    test('update seeds a fresh profile when nothing was stored yet', () async {
      final controller = ProfileController(
        ProfileRepository(),
        _FakeRemote(),
        _FakeAuth(null),
      );
      await controller.rename('Người Mới');

      final persisted = await ProfileRepository().loadOrCreate();
      expect(persisted.displayName, 'Người Mới');
    });
  });
}
