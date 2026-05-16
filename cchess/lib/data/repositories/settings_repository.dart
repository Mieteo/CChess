import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  static const String _boxName = AppConstants.boxSettings;
  static const String _key = 'app_settings';

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  Future<AppSettings> load() async {
    final box = await _openBox();
    final raw = box.get(_key);
    if (raw is Map) {
      return AppSettings.fromJson(raw);
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    final box = await _openBox();
    await box.put(_key, settings.toJson());
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});
