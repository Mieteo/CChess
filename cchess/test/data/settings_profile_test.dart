// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/data/models/app_settings.dart';
import 'package:cchess/data/models/user_profile.dart';
import 'package:cchess/data/repositories/profile_repository.dart';
import 'package:cchess/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??=
        Directory.systemTemp.createTempSync('cchess_settings_test_').path;
    return _dir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() => _ensureDir();
  @override
  Future<String?> getApplicationSupportPath() => _ensureDir();
  @override
  Future<String?> getTemporaryPath() => _ensureDir();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    // Clear both boxes between tests.
    final s = await Hive.openBox<dynamic>('cchess_settings');
    await s.clear();
    final p = await Hive.openBox<dynamic>('cchess_profile');
    await p.clear();
  });

  group('SettingsRepository', () {
    test('load returns defaults when nothing is persisted', () async {
      final repo = SettingsRepository();
      final settings = await repo.load();
      expect(settings, const AppSettings()); // default constructor values
    });

    test('save then load round-trips all fields', () async {
      final repo = SettingsRepository();
      const sample = AppSettings(
        soundEnabled: false,
        musicEnabled: false,
        vibrationEnabled: false,
        showLegalMoveDots: false,
        defaultBoardFlipped: true,
        dailyHintsLimit: 7,
        healthyGamingMinutes: 120,
      );
      await repo.save(sample);

      final repo2 = SettingsRepository();
      final back = await repo2.load();
      expect(back, sample);
    });

    test('partial updates via copyWith preserve other fields', () {
      const a = AppSettings();
      final b = a.copyWith(dailyHintsLimit: 5);
      expect(b.dailyHintsLimit, 5);
      expect(b.soundEnabled, a.soundEnabled);
      expect(b.healthyGamingMinutes, a.healthyGamingMinutes);
    });
  });

  group('ProfileRepository', () {
    test('loadOrCreate returns a fresh profile when none stored', () async {
      final repo = ProfileRepository();
      final p = await repo.loadOrCreate();
      expect(p.displayName, isNotEmpty);
      expect(p.onboardingCompleted, isFalse);
      expect(p.eloChess, greaterThan(0));
    });

    test('save then loadOrCreate returns the saved profile', () async {
      final repo = ProfileRepository();
      final first = await repo.loadOrCreate();
      final updated = first.copyWith(
        displayName: 'Trần Cờ Tướng',
        region: 'Đà Nẵng',
        onboardingCompleted: true,
      );
      await repo.save(updated);

      final repo2 = ProfileRepository();
      final back = await repo2.loadOrCreate();
      expect(back.displayName, 'Trần Cờ Tướng');
      expect(back.region, 'Đà Nẵng');
      expect(back.onboardingCompleted, isTrue);
      expect(back.id, first.id, reason: 'id must stay stable');
    });

    test('clear wipes the stored profile', () async {
      final repo = ProfileRepository();
      final p = await repo.loadOrCreate();
      await repo.save(p.copyWith(displayName: 'X'));
      await repo.clear();
      final next = await ProfileRepository().loadOrCreate();
      expect(next.displayName, isNot('X'));
    });

    test('shortId is stable and 10 chars (# + 9 digits)', () {
      final p = UserProfile.fresh(id: 'abc');
      expect(p.shortId, startsWith('#'));
      expect(p.shortId.length, 10);
    });
  });

  group('UserProfile bot pool', () {
    test('fresh profile seeds bot pool at the initial ELO / zero counters', () {
      final p = UserProfile.fresh(id: 'abc');
      expect(p.eloBot, p.eloChess, reason: 'both pools start at initial ELO');
      expect(p.botGames, 0);
      expect(p.botWins, 0);
      expect(p.botLosses, 0);
      expect(p.botDraws, 0);
    });

    test('toJson/fromJson round-trips the bot pool', () {
      final p = UserProfile.fresh(id: 'abc').copyWith(
        eloBot: 1480,
        botGames: 12,
        botWins: 7,
        botLosses: 4,
        botDraws: 1,
        eloChess: 1100, // ranked stays independent
      );
      final back = UserProfile.fromJson(p.toJson());
      expect(back.eloBot, 1480);
      expect(back.botGames, 12);
      expect(back.botWins, 7);
      expect(back.botLosses, 4);
      expect(back.botDraws, 1);
      expect(back.eloChess, 1100);
    });

    test('old cloud/Hive docs without bot fields fall back to defaults', () {
      final legacy = UserProfile.fresh(id: 'abc').toJson()
        ..remove('eloBot')
        ..remove('botGames')
        ..remove('botWins')
        ..remove('botLosses')
        ..remove('botDraws');
      final back = UserProfile.fromJson(legacy);
      expect(back.eloBot, 1000);
      expect(back.botGames, 0);
    });
  });
}
