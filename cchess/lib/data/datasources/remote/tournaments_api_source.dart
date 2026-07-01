import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../models/community_models.dart';
import 'puzzle_api_transport.dart';
import 'puzzle_api_transport_factory.dart';

typedef TournamentTokenProvider = Future<String?> Function();

/// Thrown when a tournament REST call fails (network, non-2xx, or malformed
/// body). Mirrors the backend error envelope `{ code, message }`.
class TournamentApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const TournamentApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'TournamentApiException($code): $message';
}

/// Talks to the cchess-backend tournaments REST API (S14 C4 — Giải Đấu).
///
/// Catalog reads (list/get/participants/matches) need no auth; register/
/// unregister send the Firebase ID token as a Bearer header. There is no
/// client-facing create/start — v1 ships admin/system-organized tournaments
/// only. All methods throw [TournamentApiException] on failure.
class TournamentsApiSource {
  TournamentsApiSource({
    required this.baseUri,
    TournamentTokenProvider? tokenProvider,
    PuzzleApiTransport? transport,
    this.timeout = const Duration(seconds: 8),
  }) : _tokenProvider = tokenProvider ?? _noToken,
       _transport = transport ?? createDefaultPuzzleApiTransport();

  final Uri baseUri;
  final TournamentTokenProvider _tokenProvider;
  final PuzzleApiTransport _transport;
  final Duration timeout;

  Future<List<CommunityTournament>> listTournaments() async {
    final json = await _get(const ['tournaments']);
    final raw = json['tournaments'];
    return raw is List
        ? raw
              .whereType<Map>()
              .map((m) => CommunityTournament.fromMap(m['id'] as String? ?? '', m.cast<String, dynamic>()))
              .toList(growable: false)
        : const <CommunityTournament>[];
  }

  Future<CommunityTournament?> getTournament(String id) async {
    try {
      final json = await _get(['tournaments', id]);
      return CommunityTournament.fromMap(id, json);
    } on TournamentApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<TournamentParticipant>> listParticipants(String tournamentId) async {
    final json = await _get(['tournaments', tournamentId, 'participants']);
    final raw = json['participants'];
    return raw is List
        ? raw
              .whereType<Map>()
              .map((m) => TournamentParticipant.fromMap(m.cast<String, dynamic>()))
              .toList(growable: false)
        : const <TournamentParticipant>[];
  }

  Future<List<TournamentMatch>> listMatches(String tournamentId) async {
    final json = await _get(['tournaments', tournamentId, 'matches']);
    final raw = json['matches'];
    return raw is List
        ? raw.whereType<Map>().map((m) => TournamentMatch.fromMap(m.cast<String, dynamic>())).toList(growable: false)
        : const <TournamentMatch>[];
  }

  Future<CommunityTournament> register(String tournamentId) async {
    final json = await _post(['tournaments', tournamentId, 'register'], body: const {});
    return CommunityTournament.fromMap(tournamentId, json);
  }

  Future<void> unregister(String tournamentId) async {
    await _post(['tournaments', tournamentId, 'unregister'], body: const {});
  }

  void close() => _transport.close();

  // ── Internals ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(List<String> segments) async {
    try {
      return await _transport.getJson(_uri(segments), timeout: timeout);
    } on PuzzleApiException catch (e) {
      throw _wrap(e);
    }
  }

  Future<Map<String, dynamic>> _post(
    List<String> segments, {
    required Map<String, dynamic> body,
  }) async {
    final headers = await _authHeader();
    try {
      return await _transport.postJson(_uri(segments), headers: headers, body: body, timeout: timeout);
    } on PuzzleApiException catch (e) {
      throw _wrap(e);
    }
  }

  Future<Map<String, String>> _authHeader() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const TournamentApiException(
        statusCode: 401,
        code: 'missing-token',
        message: 'Cần đăng nhập để đăng ký giải đấu',
      );
    }
    return {'authorization': 'Bearer $token'};
  }

  TournamentApiException _wrap(PuzzleApiException e) =>
      TournamentApiException(statusCode: e.statusCode, code: e.code, message: e.message);

  Uri _uri(List<String> segments) {
    final basePath = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();
    return baseUri.replace(pathSegments: [...basePath, ...segments]);
  }

  static Future<String?> _noToken() async => null;
}

final tournamentsApiSourceProvider = Provider<TournamentsApiSource>((ref) {
  final source = TournamentsApiSource(
    baseUri: Uri.parse(AppConstants.defaultBackendHttpUrl),
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.getIdToken();
    },
  );
  ref.onDispose(source.close);
  return source;
});
