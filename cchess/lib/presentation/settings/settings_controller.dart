import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../data/repositories/settings_repository.dart';

class SettingsController extends StateNotifier<AsyncValue<AppSettings>> {
  final SettingsRepository _repo;

  SettingsController(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _repo.load();
      if (mounted) state = AsyncValue.data(settings);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> update(AppSettings Function(AppSettings) mutator) async {
    final current = state.valueOrNull ?? const AppSettings();
    final next = mutator(current);
    state = AsyncValue.data(next);
    await _repo.save(next);
  }

  // Convenience wrappers used directly by the UI.
  Future<void> setSound(bool v) => update((s) => s.copyWith(soundEnabled: v));
  Future<void> setMusic(bool v) => update((s) => s.copyWith(musicEnabled: v));
  Future<void> setVibration(bool v) =>
      update((s) => s.copyWith(vibrationEnabled: v));
  Future<void> setShowDots(bool v) =>
      update((s) => s.copyWith(showLegalMoveDots: v));
  Future<void> setFlipDefault(bool v) =>
      update((s) => s.copyWith(defaultBoardFlipped: v));
  Future<void> setDarkMode(bool v) => update((s) => s.copyWith(darkMode: v));
  Future<void> setHintLimit(int v) =>
      update((s) => s.copyWith(dailyHintsLimit: v));
  Future<void> setHealthyMinutes(int v) =>
      update((s) => s.copyWith(healthyGamingMinutes: v));
}

final settingsControllerProvider = StateNotifierProvider<
    SettingsController, AsyncValue<AppSettings>>((ref) {
  return SettingsController(ref.watch(settingsRepositoryProvider));
});
