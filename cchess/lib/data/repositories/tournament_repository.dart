import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../datasources/remote/tournaments_api_source.dart';
import '../models/community_models.dart';
import 'community_repository.dart' show seedCommunityTournaments;

/// Repository for tournaments (S14 C4 — Giải Đấu). Server-authoritative: the
/// backend owns registration/bracket state; this layer fetches through
/// [TournamentsApiSource] and keeps a Hive cache of the last successful list
/// so Cộng Đồng → Giải Đấu still renders offline.
class TournamentRepository {
  TournamentRepository({TournamentsApiSource? remote}) : _remote = remote;

  final TournamentsApiSource? _remote;

  static const String _boxName = AppConstants.boxTournaments;
  static const String _kTournaments = 'tournaments';

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  Future<List<CommunityTournament>> listTournaments() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final tournaments = await remote.listTournaments();
        await _cache(tournaments);
        return tournaments;
      } on TournamentApiException {
        // fall through to cache
      }
    }
    return cachedTournaments();
  }

  Future<List<CommunityTournament>> cachedTournaments() async {
    final box = await _openBox();
    final raw = box.get(_kTournaments);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => CommunityTournament.fromMap(m['id'] as String? ?? '', m.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return seedCommunityTournaments();
  }

  Future<void> _cache(List<CommunityTournament> tournaments) async {
    final box = await _openBox();
    await box.put(
      _kTournaments,
      tournaments
          .map(
            (t) => {
              'id': t.id,
              'name': t.name,
              'mode': t.mode,
              'statusLabel': t.statusLabel,
              'startsAtMs': t.startsAt.millisecondsSinceEpoch,
              'participantCount': t.registeredPlayers,
              'capacity': t.capacity,
              'prize': t.prize,
              'status': t.status.name == 'inProgress' ? 'in_progress' : t.status.name,
            },
          )
          .toList(),
    );
  }

  Future<List<TournamentParticipant>> participants(String tournamentId) async {
    final remote = _remote;
    if (remote == null) return const [];
    try {
      return await remote.listParticipants(tournamentId);
    } on TournamentApiException {
      return const [];
    }
  }

  Future<List<TournamentMatch>> matches(String tournamentId) async {
    final remote = _remote;
    if (remote == null) return const [];
    try {
      return await remote.listMatches(tournamentId);
    } on TournamentApiException {
      return const [];
    }
  }

  Future<CommunityTournament> register(String tournamentId) async {
    final remote = _remote;
    if (remote == null) {
      throw const TournamentApiException(code: 'offline', message: 'Không thể đăng ký khi ngoại tuyến');
    }
    return remote.register(tournamentId);
  }

  Future<void> unregister(String tournamentId) async {
    final remote = _remote;
    if (remote == null) {
      throw const TournamentApiException(code: 'offline', message: 'Không thể hủy đăng ký khi ngoại tuyến');
    }
    await remote.unregister(tournamentId);
  }
}

final tournamentRepositoryProvider = Provider<TournamentRepository>((ref) {
  return TournamentRepository(remote: ref.watch(tournamentsApiSourceProvider));
});
