import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user_profile.dart';
import '../../data/repositories/profile_repository.dart';

class ProfileController extends StateNotifier<AsyncValue<UserProfile>> {
  final ProfileRepository _repo;

  ProfileController(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _repo.loadOrCreate();
      if (mounted) state = AsyncValue.data(profile);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> update(UserProfile Function(UserProfile) mutator) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = mutator(current);
    state = AsyncValue.data(next);
    await _repo.save(next);
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
  return ProfileController(ref.watch(profileRepositoryProvider));
});
