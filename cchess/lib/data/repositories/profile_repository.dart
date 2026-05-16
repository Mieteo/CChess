import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/user_profile.dart';

class ProfileRepository {
  static const String _boxName = 'cchess_profile';
  static const String _key = 'me';

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  /// Returns the stored profile, or creates and persists a fresh one if
  /// nothing is there yet.
  Future<UserProfile> loadOrCreate() async {
    final box = await _openBox();
    final raw = box.get(_key);
    if (raw is Map) {
      return UserProfile.fromJson(raw);
    }
    final fresh = UserProfile.fresh();
    await save(fresh);
    return fresh;
  }

  Future<void> save(UserProfile profile) async {
    final box = await _openBox();
    await box.put(_key, profile.toJson());
  }

  Future<void> clear() async {
    final box = await _openBox();
    await box.delete(_key);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository();
});
