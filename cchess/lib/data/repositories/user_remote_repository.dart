import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';

/// Read/write the cloud user document at `users/{uid}`.
///
/// Layout of fields here must match firestore.rules whitelist + create check.
class UserRemoteRepository {
  UserRemoteRepository(this._db);
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  Future<Map<String, dynamic>?> read(String uid) async {
    final snap = await _doc(uid).get();
    return snap.exists ? snap.data() : null;
  }

  /// Create the cloud doc seeded from local profile.
  ///
  /// Sensitive fields are forced to defaults — rules reject anything else.
  Future<void> createFromLocal(String uid, UserProfile local) async {
    await _doc(uid).set({
      'displayName': local.displayName,
      'region': local.region,
      'avatarUrl': local.avatarUrl,
      'eloChess': 1000,
      'eloCup': 1000,
      'totalGames': 0,
      'wins': 0,
      'losses': 0,
      'draws': 0,
      'coins': 100,
      'gems': 10,
      'creditScore': 100,
      'isVip': false,
      'vipExpiresAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'onboardingCompleted': local.onboardingCompleted,
    });
  }

  Future<void> touchLastActive(String uid) async {
    await _doc(uid).update({
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update whitelist fields only — rules enforce this.
  Future<void> updateProfileFields(
    String uid, {
    String? displayName,
    String? region,
    String? avatarUrl,
    bool? onboardingCompleted,
  }) async {
    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (region != null) updates['region'] = region;
    if (avatarUrl != null) updates['avatarUrl'] = avatarUrl;
    if (onboardingCompleted != null) {
      updates['onboardingCompleted'] = onboardingCompleted;
    }
    updates['lastActiveAt'] = FieldValue.serverTimestamp();
    await _doc(uid).update(updates);
  }
}

final userRemoteRepositoryProvider = Provider<UserRemoteRepository>((ref) {
  return UserRemoteRepository(FirebaseFirestore.instance);
});
