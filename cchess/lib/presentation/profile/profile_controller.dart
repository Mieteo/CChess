import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user_profile.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/user_remote_repository.dart';

class ProfileController extends StateNotifier<AsyncValue<UserProfile>> {
  ProfileController(this._repo, this._remote, this._auth)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final ProfileRepository _repo;
  final UserRemoteRepository _remote;
  final FirebaseAuth _auth;

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
    final current = state.valueOrNull;
    if (current == null) return;
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

    if (!anyChange) return;

    _remote
        .updateProfileFields(
          uid,
          displayName: displayName,
          region: region,
          avatarUrl: avatarUrl,
          onboardingCompleted: onboardingCompleted,
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

  /// Apply the result of a finished game to the user's stats + ELO.
  /// These fields are server-only on cloud; only local updates for now.
  Future<void> applyGameResult({
    required int eloDelta,
    required bool won,
    required bool drew,
  }) =>
      update((p) => p.copyWith(
            eloChess: p.eloChess + eloDelta,
            totalGames: p.totalGames + 1,
            wins: p.wins + (won ? 1 : 0),
            losses: p.losses + (!won && !drew ? 1 : 0),
            draws: p.draws + (drew ? 1 : 0),
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
