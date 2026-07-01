import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../models/community_models.dart';
import 'puzzle_api_transport.dart';
import 'puzzle_api_transport_factory.dart';

typedef ClubTokenProvider = Future<String?> Function();

/// Thrown when a club REST call fails (network, non-2xx, or malformed body).
/// Mirrors the backend error envelope `{ code, message }`.
class ClubApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const ClubApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// True when the request never reached the server — the caller can fall
  /// back to the cached club list.
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'ClubApiException($code): $message';
}

/// One club id + the caller's role in it, as returned by GET /clubs/mine.
class MyClubEntry {
  final String clubId;
  final ClubRole role;
  const MyClubEntry({required this.clubId, required this.role});

  factory MyClubEntry.fromJson(Map<String, dynamic> json) => MyClubEntry(
    clubId: json['clubId'] as String? ?? '',
    role: ClubRole.fromValue(json['role']),
  );
}

/// Talks to the cchess-backend clubs REST API (S14 C3 — Kỳ Xã).
///
/// Catalog reads (`listClubs`, `getClub`, `listMembers`) need no auth; create/
/// join/leave/mine send the Firebase ID token as a Bearer header. All methods
/// throw [ClubApiException] on failure — the repository decides when to fall
/// back to the cache/seed.
class ClubsApiSource {
  ClubsApiSource({
    required this.baseUri,
    ClubTokenProvider? tokenProvider,
    PuzzleApiTransport? transport,
    this.timeout = const Duration(seconds: 8),
  }) : _tokenProvider = tokenProvider ?? _noToken,
       _transport = transport ?? createDefaultPuzzleApiTransport();

  final Uri baseUri;
  final ClubTokenProvider _tokenProvider;
  final PuzzleApiTransport _transport;
  final Duration timeout;

  Future<List<CommunityClub>> listClubs() async {
    final json = await _get(const ['clubs']);
    final raw = json['clubs'];
    return raw is List
        ? raw
              .whereType<Map>()
              .map((m) => CommunityClub.fromMap(m['id'] as String? ?? '', m.cast<String, dynamic>()))
              .toList(growable: false)
        : const <CommunityClub>[];
  }

  Future<CommunityClub?> getClub(String id) async {
    try {
      final json = await _get(['clubs', id]);
      return CommunityClub.fromMap(id, json);
    } on ClubApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<ClubMember>> listMembers(String clubId) async {
    final json = await _get(['clubs', clubId, 'members']);
    final raw = json['members'];
    return raw is List
        ? raw.whereType<Map>().map((m) => ClubMember.fromMap(m.cast<String, dynamic>())).toList(growable: false)
        : const <ClubMember>[];
  }

  Future<List<MyClubEntry>> listMine() async {
    final json = await _get(const ['clubs', 'mine'], auth: true);
    final raw = json['clubs'];
    return raw is List
        ? raw.whereType<Map>().map((m) => MyClubEntry.fromJson(m.cast<String, dynamic>())).toList(growable: false)
        : const <MyClubEntry>[];
  }

  Future<CommunityClub> create({
    required String name,
    required String region,
    required String description,
  }) async {
    final json = await _post(const ['clubs'], body: {
      'name': name,
      'region': region,
      'description': description,
    });
    return CommunityClub.fromMap(json['id'] as String? ?? '', json);
  }

  Future<CommunityClub> join(String clubId) async {
    final json = await _post(['clubs', clubId, 'join'], body: const {});
    return CommunityClub.fromMap(clubId, json);
  }

  Future<void> leave(String clubId) async {
    await _post(['clubs', clubId, 'leave'], body: const {});
  }

  void close() => _transport.close();

  // ── Internals ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
    List<String> segments, {
    bool auth = false,
  }) async {
    final headers = auth ? await _authHeader() : const <String, String>{};
    try {
      return await _transport.getJson(_uri(segments), headers: headers, timeout: timeout);
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
      throw const ClubApiException(
        statusCode: 401,
        code: 'missing-token',
        message: 'Cần đăng nhập để dùng tính năng Kỳ Xã',
      );
    }
    return {'authorization': 'Bearer $token'};
  }

  ClubApiException _wrap(PuzzleApiException e) =>
      ClubApiException(statusCode: e.statusCode, code: e.code, message: e.message);

  Uri _uri(List<String> segments) {
    final basePath = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();
    return baseUri.replace(pathSegments: [...basePath, ...segments]);
  }

  static Future<String?> _noToken() async => null;
}

/// Backend-backed clubs source wired to the configured HTTP origin + Firebase
/// token (the same origin the shop/puzzle APIs are mounted on).
final clubsApiSourceProvider = Provider<ClubsApiSource>((ref) {
  final source = ClubsApiSource(
    baseUri: Uri.parse(AppConstants.defaultBackendHttpUrl),
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.getIdToken();
    },
  );
  ref.onDispose(source.close);
  return source;
});
