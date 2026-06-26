import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../repositories/user_remote_repository.dart';

enum CloudSyncOutcome {
  /// Cloud created from local (first sign-in)
  seededFromLocal,

  /// Local cache refreshed from cloud
  pulledFromCloud,

  /// Offline / Firebase unreachable; only local was used
  offline,
}

class CloudSyncResult {
  CloudSyncResult({required this.profile, required this.outcome, this.uid});
  final UserProfile profile;
  final CloudSyncOutcome outcome;
  final String? uid;
}

/// Orchestrates Sprint 8 sync flow described in
/// `07_HUONG_DAN_THIET_LAP_FIREBASE.md` mục 9.2.
class CloudSyncService {
  CloudSyncService({
    required this.auth,
    required this.local,
    required this.remote,
  });

  final FirebaseAuth auth;
  final ProfileRepository local;
  final UserRemoteRepository remote;

  /// Lightweight refresh — assumes user is already signed in.
  /// Re-reads `users/{uid}` from Firestore, merges into local Hive,
  /// and returns the latest profile. Useful for post-game-ended ELO refresh.
  /// Caller should invoke `ProfileController.refresh()` afterwards if the
  /// in-memory profile state needs to mirror the new Hive value.
  Future<CloudSyncResult> refreshFromCloud() async {
    final user = auth.currentUser;
    final localProfile = await local.loadOrCreate();
    if (user == null) {
      return CloudSyncResult(
        profile: localProfile,
        outcome: CloudSyncOutcome.offline,
      );
    }
    final uid = user.uid;
    try {
      final cloud = await remote.read(uid);
      if (cloud == null) {
        return CloudSyncResult(
          profile: localProfile,
          outcome: CloudSyncOutcome.offline,
          uid: uid,
        );
      }
      final merged = _mergeCloudIntoLocal(uid, cloud, localProfile);
      await local.save(merged);
      return CloudSyncResult(
        profile: merged,
        outcome: CloudSyncOutcome.pulledFromCloud,
        uid: uid,
      );
    } on FirebaseException {
      return CloudSyncResult(
        profile: localProfile,
        outcome: CloudSyncOutcome.offline,
        uid: uid,
      );
    }
  }

  Future<CloudSyncResult> syncOnStart() async {
    final localProfile = await local.loadOrCreate();

    final String uid;
    try {
      final current = auth.currentUser;
      uid = current?.uid ??
          (await auth.signInAnonymously()).user!.uid;
    } catch (_) {
      return CloudSyncResult(
        profile: localProfile,
        outcome: CloudSyncOutcome.offline,
      );
    }

    try {
      final cloud = await remote.read(uid);
      if (cloud == null) {
        await remote.createFromLocal(uid, localProfile);
        final seeded = _withCloudUid(localProfile, uid);
        await local.save(seeded);
        return CloudSyncResult(
          profile: seeded,
          outcome: CloudSyncOutcome.seededFromLocal,
          uid: uid,
        );
      }

      final merged = _mergeCloudIntoLocal(uid, cloud, localProfile);
      await local.save(merged);
      remote.touchLastActive(uid).ignore();
      return CloudSyncResult(
        profile: merged,
        outcome: CloudSyncOutcome.pulledFromCloud,
        uid: uid,
      );
    } on FirebaseException {
      return CloudSyncResult(
        profile: localProfile,
        outcome: CloudSyncOutcome.offline,
        uid: uid,
      );
    }
  }

  UserProfile _withCloudUid(UserProfile local, String uid) {
    return UserProfile(
      id: uid,
      displayName: local.displayName,
      region: local.region,
      avatarUrl: local.avatarUrl,
      eloChess: local.eloChess,
      eloCup: local.eloCup,
      totalGames: local.totalGames,
      wins: local.wins,
      losses: local.losses,
      draws: local.draws,
      eloBot: local.eloBot,
      botGames: local.botGames,
      botWins: local.botWins,
      botLosses: local.botLosses,
      botDraws: local.botDraws,
      coins: local.coins,
      gems: local.gems,
      creditScore: local.creditScore,
      isVip: local.isVip,
      vipExpiresAt: local.vipExpiresAt,
      createdAt: local.createdAt,
      lastActiveAt: local.lastActiveAt,
      onboardingCompleted: local.onboardingCompleted,
    );
  }

  UserProfile _mergeCloudIntoLocal(
    String uid,
    Map<String, dynamic> cloud,
    UserProfile fallback,
  ) {
    // Sprint 12 strategy (updated after Step A2 ELO):
    // - Whitelist fields (displayName, region, avatarUrl, onboardingCompleted):
    //   cloud is source of truth (client writes via UserRemoteRepository).
    // - Ranked stats (eloChess, eloCup, totalGames, wins, losses, draws):
    //   cloud is source of truth — server backend updates these via Admin SDK
    //   after every ranked game ends (see cchess-backend/src/persistence.ts).
    //   Bot/local games never touch these — they use the bot pool below.
    // - Bot pool (eloBot, botGames, botWins, botLosses, botDraws):
    //   CLIENT-owned (bot games run on-device). The client both writes these to
    //   its own cloud doc (UserRemoteRepository) and reads them back here, so
    //   cloud stays the synced source of truth. This is the fix for the bug
    //   where bot ELO lived only in local eloChess and got clobbered here.
    // - Currency + VIP (coins, gems, creditScore, isVip, vipExpiresAt):
    //   keep local for now. Will become cloud-driven when Shop launches
    //   (Sprint 16) + IAP (Sprint 17).
    // - createdAt / lastActiveAt: cloud is source of truth (server timestamps).
    DateTime asDate(String key, DateTime fallbackValue) {
      final v = cloud[key];
      if (v is Timestamp) return v.toDate();
      return fallbackValue;
    }

    int asInt(String key, int fallbackValue) {
      final v = cloud[key];
      if (v is num) return v.toInt();
      return fallbackValue;
    }

    return UserProfile(
      id: uid,
      displayName: (cloud['displayName'] as String?) ?? fallback.displayName,
      region: (cloud['region'] as String?) ?? fallback.region,
      avatarUrl: cloud['avatarUrl'] as String?,
      eloChess: asInt('eloChess', fallback.eloChess),
      eloCup: asInt('eloCup', fallback.eloCup),
      totalGames: asInt('totalGames', fallback.totalGames),
      wins: asInt('wins', fallback.wins),
      losses: asInt('losses', fallback.losses),
      draws: asInt('draws', fallback.draws),
      eloBot: asInt('eloBot', fallback.eloBot),
      botGames: asInt('botGames', fallback.botGames),
      botWins: asInt('botWins', fallback.botWins),
      botLosses: asInt('botLosses', fallback.botLosses),
      botDraws: asInt('botDraws', fallback.botDraws),
      coins: fallback.coins,
      gems: fallback.gems,
      creditScore: fallback.creditScore,
      isVip: fallback.isVip,
      vipExpiresAt: fallback.vipExpiresAt,
      createdAt: asDate('createdAt', fallback.createdAt),
      lastActiveAt: asDate('lastActiveAt', fallback.lastActiveAt),
      onboardingCompleted:
          (cloud['onboardingCompleted'] as bool?) ?? fallback.onboardingCompleted,
    );
  }
}

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  return CloudSyncService(
    auth: FirebaseAuth.instance,
    local: ref.read(profileRepositoryProvider),
    remote: ref.read(userRemoteRepositoryProvider),
  );
});
