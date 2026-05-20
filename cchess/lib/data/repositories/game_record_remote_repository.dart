import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_record.dart';

/// Cloud writer for `users/{uid}/game_records/{gameId}`.
///
/// Local/bot games are written client-side. Ranked online games will
/// be written by Cloud Functions (server-authoritative) — see
/// `functions/src/index.ts:recordRankedGame`.
class GameRecordRemoteRepository {
  GameRecordRemoteRepository(this._db, this._auth);
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>>? _col() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('game_records');
  }

  /// Write the whole game record once when it's first saved locally.
  ///
  /// Schema mostly matches doc 7 mục 6.2 + a few client-specific extras
  /// (`humanColor`, `endReason`, `eloDelta`) which rules don't enforce.
  Future<void> pushGameRecord(GameRecord r) async {
    final col = _col();
    if (col == null) return;
    await col.doc(r.id).set({
      'opponent': r.opponentLabel,
      'mode': r.mode.name,
      'humanColor': r.humanColor?.name,
      'startingPosition': r.startingFen,
      'moveList': r.moves,
      'result': r.result.name,
      'endReason': r.endReason?.name,
      'eloDelta': r.eloDelta,
      'duration': r.duration.inMilliseconds,
      'endedAt': Timestamp.fromDate(r.endedAt),
      'isFavorite': r.isFavorite,
    });
  }

  /// Only `isFavorite` is allowed to change after create — see firestore.rules.
  Future<void> updateFavorite(String gameId, bool isFavorite) async {
    final col = _col();
    if (col == null) return;
    await col.doc(gameId).update({'isFavorite': isFavorite});
  }
}

final gameRecordRemoteRepositoryProvider =
    Provider<GameRecordRemoteRepository>((ref) {
  return GameRecordRemoteRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
});
