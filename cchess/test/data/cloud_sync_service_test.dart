// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/models/user_profile.dart';
import 'package:cchess/data/repositories/profile_repository.dart';
import 'package:cchess/data/repositories/user_remote_repository.dart';
import 'package:cchess/data/services/cloud_sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp.createTempSync('cchess_cloudsync_test_').path;
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

/// In-memory stand-in for the Firestore-backed repository. Records every
/// `updateProfileFields` call so tests can assert on the heal push.
class _FakeRemote extends Fake implements UserRemoteRepository {
  Map<String, dynamic>? cloudDoc;
  UserProfile? createdFrom;
  final List<Map<String, dynamic>> fieldUpdates = [];

  @override
  Future<Map<String, dynamic>?> read(String uid) async => cloudDoc;

  @override
  Future<void> createFromLocal(String uid, UserProfile local) async {
    createdFrom = local;
  }

  @override
  Future<void> touchLastActive(String uid) async {}

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

  CloudSyncService buildService(_FakeRemote remote, {String uid = 'uid-1'}) {
    return CloudSyncService(
      auth: _FakeAuth(_FakeUser(uid)),
      local: ProfileRepository(),
      remote: remote,
    );
  }

  /// Cloud doc as `createFromLocal` seeds it on first launch — before the
  /// user has completed onboarding.
  Map<String, dynamic> preOnboardingCloudDoc() => {
        'displayName': 'Kỳ Thủ',
        'region': 'Hà Nội',
        'onboardingCompleted': false,
      };

  group('CloudSyncService onboarding persistence (force-stop)', () {
    test(
        'syncOnStart keeps local onboardingCompleted=true when the cloud doc '
        'missed the push (force-stop scenario)', () async {
      // Local state after onboarding finished: flag + name saved in Hive,
      // but the fire-and-forget cloud push was killed by a force-stop.
      final localRepo = ProfileRepository();
      final fresh = await localRepo.loadOrCreate();
      await localRepo.save(fresh.copyWith(
        displayName: 'Trần Kỳ Thủ',
        region: 'Huế',
        onboardingCompleted: true,
      ));

      final remote = _FakeRemote()..cloudDoc = preOnboardingCloudDoc();
      final result = await buildService(remote).syncOnStart();

      expect(result.outcome, CloudSyncOutcome.pulledFromCloud);
      expect(result.profile.onboardingCompleted, isTrue,
          reason: 'onboarding is a one-way latch — cloud false must not win');
      expect(result.profile.displayName, 'Trần Kỳ Thủ',
          reason: 'local whitelist is newer than the stale cloud doc');
      expect(result.profile.region, 'Huế');

      // Hive must not be regressed either — next cold start reads this.
      final persisted = await ProfileRepository().loadOrCreate();
      expect(persisted.onboardingCompleted, isTrue);
      expect(persisted.displayName, 'Trần Kỳ Thủ');
    });

    test('syncOnStart re-pushes the flag to heal the stale cloud doc',
        () async {
      final localRepo = ProfileRepository();
      final fresh = await localRepo.loadOrCreate();
      await localRepo.save(fresh.copyWith(
        displayName: 'Trần Kỳ Thủ',
        region: 'Huế',
        onboardingCompleted: true,
      ));

      final remote = _FakeRemote()..cloudDoc = preOnboardingCloudDoc();
      await buildService(remote).syncOnStart();

      expect(remote.fieldUpdates, hasLength(1));
      final push = remote.fieldUpdates.single;
      expect(push['onboardingCompleted'], isTrue);
      expect(push['displayName'], 'Trần Kỳ Thủ');
      expect(push['region'], 'Huế');
    });

    test('refreshFromCloud applies the same latch + heal', () async {
      final localRepo = ProfileRepository();
      final fresh = await localRepo.loadOrCreate();
      await localRepo.save(fresh.copyWith(
        displayName: 'Trần Kỳ Thủ',
        region: 'Huế',
        onboardingCompleted: true,
      ));

      final remote = _FakeRemote()..cloudDoc = preOnboardingCloudDoc();
      final result = await buildService(remote).refreshFromCloud();

      expect(result.profile.onboardingCompleted, isTrue);
      expect(result.profile.displayName, 'Trần Kỳ Thủ');
      expect(remote.fieldUpdates, hasLength(1));
      expect(remote.fieldUpdates.single['onboardingCompleted'], isTrue);
    });

    test('cloud onboardingCompleted=true still wins over a fresh local',
        () async {
      final remote = _FakeRemote()
        ..cloudDoc = {
          'displayName': 'Tên Cloud',
          'region': 'Đà Nẵng',
          'onboardingCompleted': true,
        };
      final result = await buildService(remote).syncOnStart();

      expect(result.profile.onboardingCompleted, isTrue);
      expect(result.profile.displayName, 'Tên Cloud',
          reason: 'cloud stays source of truth when it is not stale');
      expect(result.profile.region, 'Đà Nẵng');
      expect(remote.fieldUpdates, isEmpty,
          reason: 'no heal push needed when cloud already agrees');
    });

    test('neither side onboarded → still routed to onboarding, no heal push',
        () async {
      final remote = _FakeRemote()..cloudDoc = preOnboardingCloudDoc();
      final result = await buildService(remote).syncOnStart();

      expect(result.profile.onboardingCompleted, isFalse);
      expect(remote.fieldUpdates, isEmpty);
    });
  });
}
