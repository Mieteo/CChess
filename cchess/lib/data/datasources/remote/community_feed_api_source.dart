import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../models/community_models.dart';
import 'puzzle_api_transport.dart';
import 'puzzle_api_transport_factory.dart';

/// Thrown when a community-feed REST call fails (network, non-2xx, or
/// malformed body). Mirrors the backend error envelope `{ code, message }`.
class FeedApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const FeedApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// True when the request never reached the server — the caller can fall
  /// back to the hardcoded feed.
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'FeedApiException($code): $message';
}

/// Talks to the cchess-backend community feed REST API (S14 C6 — Tin Tức +
/// Tàn Cục Thách Đấu). Public read, no auth. Throws [FeedApiException] on
/// failure — the repository decides when to fall back to the hardcoded feed.
class CommunityFeedApiSource {
  CommunityFeedApiSource({
    required this.baseUri,
    PuzzleApiTransport? transport,
    this.timeout = const Duration(seconds: 8),
  }) : _transport = transport ?? createDefaultPuzzleApiTransport();

  final Uri baseUri;
  final PuzzleApiTransport _transport;
  final Duration timeout;

  Future<List<CommunityFeedItem>> listFeed() async {
    try {
      final json = await _transport.getJson(_uri(), timeout: timeout);
      final raw = json['items'];
      return raw is List
          ? raw.whereType<Map>().map((m) => CommunityFeedItem.fromMap(m.cast<String, dynamic>())).toList(growable: false)
          : const <CommunityFeedItem>[];
    } on PuzzleApiException catch (e) {
      throw FeedApiException(statusCode: e.statusCode, code: e.code, message: e.message);
    }
  }

  void close() => _transport.close();

  Uri _uri() {
    final basePath = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();
    return baseUri.replace(pathSegments: [...basePath, 'community', 'feed']);
  }
}

/// Backend-backed feed source wired to the configured HTTP origin (the same
/// origin the shop/puzzle/clubs APIs are mounted on).
final communityFeedApiSourceProvider = Provider<CommunityFeedApiSource>((ref) {
  final source = CommunityFeedApiSource(baseUri: Uri.parse(AppConstants.defaultBackendHttpUrl));
  ref.onDispose(source.close);
  return source;
});
