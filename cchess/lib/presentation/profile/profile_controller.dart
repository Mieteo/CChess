import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user_profile.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/user_remote_repository.dart';

class ProfileController extends StateNotifier<AsyncValue<UserProfile>> {
  ProfileController(this._repo, this._remote, this._auth)
      : super(const AsyncValue.loading()) {
    _initialLoad = _load();
  }

  final ProfileRepository _repo;
  final UserRemoteRepository _remote;
  final FirebaseAuth _auth;

  /// Completes once the first Hive read has populated [state]. Mutations await
  /// this because the controller is created lazily: a caller's very first
  /// `ref.read` can be immediately followed by an update (vd OnboardingScreen
  /// reads the notifier inside `_finish()` and calls [completeOnboarding]
  /// right after). Without the await, `update()` saw a loading state and
  /// silently dropped the mutation — the S16 QA bug where finishing
  /// onboarding never persisted and a force-stop bounced the user back.
  late final Future<void> _initialLoad;

  Future<void> _load() async {
    try {
      final profile = await _repo.loadOrCreate();
      if (mounted) state = AsyncValue.data(profile);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  /// Re-read the profile from local Hive — call AFTER an external write
  /// (vd `CloudSyncService.refreshFromCloud()`) so the in-memory state matches.
  Future<void> refresh() => _load();

  Future<void> update(UserProfile Function(UserProfile) mutator) async {
    await _initialLoad;
    final current = state.valueOrNull;
    if (current == null) return; // initial load failed — nothing to mutate
    final next = mutator(current);
    state = AsyncValue.data(next);
    await _repo.save(next);
    _pushWhitelistChangesToCloud(current, next);
  }

  void _pushWhitelistChangesToCloud(UserProfile before, UserProfile after) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    String? displayName;
    String? region;
    String? avatarUrl;
    bool? onboardingCompleted;
    int? eloBot;
    int? botGames;
    int? botWins;
    int? botLosses;
    int? botDraws;
    var anyChange = false;

    if (before.displayName != after.displayName) {
      displayName = after.displayName;
      anyChange = true;
    }
    if (before.region != after.region) {
      region = after.region;
      anyChange = true;
    }
    if (before.avatarUrl != after.avatarUrl) {
      avatarUrl = after.avatarUrl;
      anyChange = true;
    }
    if (before.onboardingCompleted != after.onboardingCompleted) {
      onboardingCompleted = after.onboardingCompleted;
      anyChange = true;
    }
    // Bot pool is client-owned — push it so it survives splash sync.
    if (before.eloBot != after.eloBot) {
      eloBot = after.eloBot;
      anyChange = true;
    }
    if (before.botGames != after.botGames) {
      botGames = after.botGames;
      anyChange = true;
    }
    if (before.botWins != after.botWins) {
      botWins = after.botWins;
      anyChange = true;
    }
    if (before.botLosses != after.botLosses) {
      botLosses = after.botLosses;
      anyChange = true;
    }
    if (before.botDraws != after.botDraws) {
      botDraws = after.botDraws;
      anyChange = true;
    }

    if (!anyChange) return;

    _remote
        .updateProfileFields(
          uid,
          displayName: displayName,
          region: region,
          avatarUrl: avatarUrl,
          onboardingCompleted: onboardingCompleted,
          eloBot: eloBot,
          botGames: botGames,
          botWins: botWins,
          botLosses: botLosses,
          botDraws: botDraws,
        )
        .ignore();
  }

  Future<void> rename(String newName) =>
      update((p) => p.copyWith(displayName: newName));

  Future<void> changeRegion(String region) =>
      update((p) => p.copyWith(region: region));

  Future<void> completeOnboarding({
    required String displayName,
    required String region,
  }) =>
      update((p) => p.copyWith(
            displayName: displayName,
            region: region,
            onboardingCompleted: true,
          ));

  /// Apply the result of a finished **vs-bot** game to the practice pool.
  ///
  /// Bot games update the client-owned bot pool ([eloBot] + bot W/L/D), NOT the
  /// server-authoritative ranked stats (eloChess/totalGames/wins/losses/draws).
  /// `update()` pushes these to cloud so they survive splash sync — fixing the
  /// bug where bot ELO was written into eloChess and then clobbered by the
  /// cloud merge (09_BACKEND §8). [eloDelta] is 0 for legacy/Cờ Úp bot games.
  Future<void> applyGameResult({
    required int eloDelta,
    required bool won,
    required bool drew,
  }) =>
      update((p) => p.copyWith(
            eloBot: p.eloBot + eloDelta,
            botGames: p.botGames + 1,
            botWins: p.botWins + (won ? 1 : 0),
            botLosses: p.botLosses + (!won && !drew ? 1 : 0),
            botDraws: p.botDraws + (drew ? 1 : 0),
            lastActiveAt: DateTime.now(),
          ));
}

final profileControllerProvider =
    StateNotifierProvider<ProfileController, AsyncValue<UserProfile>>((ref) {
  return ProfileController(
    ref.watch(profileRepositoryProvider),
    ref.watch(userRemoteRepositoryProvider),
    FirebaseAuth.instance,
  );
});
