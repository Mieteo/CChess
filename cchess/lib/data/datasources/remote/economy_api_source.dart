import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../models/economy_models.dart';
import '../../models/inventory_item.dart';
import '../../models/shop_item.dart';
import '../../models/wallet.dart';
import 'puzzle_api_transport.dart';
import 'puzzle_api_transport_factory.dart';

typedef EconomyTokenProvider = Future<String?> Function();

/// Thrown when an economy REST call fails (network, non-2xx, malformed body).
/// Mirrors the backend error envelope `{ code, message }`.
class EconomyApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const EconomyApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// True when the request never reached the server (offline / timeout / web
  /// stub) — the caller can fall back to cached data.
  bool get isNetworkError => statusCode == null;

  /// True for a claim-once guard trip (already claimed / checked in).
  bool get isAlreadyClaimed => statusCode == 409;

  @override
  String toString() => 'EconomyApiException($code): $message';
}

/// Result of a successful claim: the credited wallet + what was granted.
class ClaimOutcome {
  final Wallet wallet;
  final RewardBundle reward;
  const ClaimOutcome({required this.wallet, required this.reward});
}

/// Result of a welfare claim: also carries the refreshed status.
class WelfareClaimOutcome extends ClaimOutcome {
  final WelfareStatus status;
  const WelfareClaimOutcome({
    required super.wallet,
    required super.reward,
    required this.status,
  });
}

/// Result of a craft: the debited wallet + the crafted item.
class CraftOutcome {
  final Wallet wallet;
  final InventoryItem item;
  const CraftOutcome({required this.wallet, required this.item});
}

/// Talks to the cchess-backend economy REST API (S16 — D4 Hộp Thư / D5 Sự Kiện
/// / D6 Phúc Lợi / D7 Đúc Bàn Cờ).
///
/// Event + crafting catalog reads need no auth; everything else sends the
/// Firebase ID token as a Bearer header. All methods throw
/// [EconomyApiException] on failure — the repository decides when to fall back
/// to the cache.
class EconomyApiSource {
  EconomyApiSource({
    required this.baseUri,
    EconomyTokenProvider? tokenProvider,
    PuzzleApiTransport? transport,
    this.timeout = const Duration(seconds: 8),
  })  : _tokenProvider = tokenProvider ?? _noToken,
        _transport = transport ?? createDefaultPuzzleApiTransport();

  final Uri baseUri;
  final EconomyTokenProvider _tokenProvider;
  final PuzzleApiTransport _transport;
  final Duration timeout;

  // ── Mail (D4) ─────────────────────────────────────────────────────────────

  Future<List<MailMessage>> listMail() async {
    final json = await _get(const ['mail'], auth: true);
    final raw = json['messages'];
    return raw is List
        ? raw.whereType<Map>().map(MailMessage.fromJson).toList(growable: false)
        : const [];
  }

  Future<void> markMailRead(String mailId) async {
    await _post(['mail', mailId, 'read']);
  }

  Future<ClaimOutcome> claimMail(String mailId) async {
    return _claimOutcome(await _post(['mail', mailId, 'claim']));
  }

  Future<void> deleteMail(String mailId) async {
    // POST alias — the shared transport only speaks GET/POST.
    await _post(['mail', mailId, 'delete']);
  }

  // ── Events (D5) ───────────────────────────────────────────────────────────

  Future<List<EconEvent>> listEvents() async {
    final json = await _get(const ['events']);
    final raw = json['events'];
    return raw is List
        ? raw.whereType<Map>().map(EconEvent.fromJson).toList(growable: false)
        : const [];
  }

  /// Claimed gift keys of the signed-in user, as `eventId__giftId`.
  Future<Set<String>> listEventClaims() async {
    final json = await _get(const ['events', 'claims'], auth: true);
    final raw = json['claims'];
    if (raw is! List) return const {};
    return raw
        .whereType<Map>()
        .map((c) => '${c['eventId']}__${c['giftId']}')
        .toSet();
  }

  Future<ClaimOutcome> claimEventGift(String eventId, String giftId) async {
    return _claimOutcome(
      await _post(['events', eventId, 'claim'], body: {'giftId': giftId}),
    );
  }

  // ── Welfare (D6) ──────────────────────────────────────────────────────────

  Future<WelfareStatus> getWelfare() async {
    return WelfareStatus.fromJson(await _get(const ['welfare'], auth: true));
  }

  Future<WelfareClaimOutcome> checkin() =>
      _welfareClaim(const ['welfare', 'checkin']);

  Future<WelfareClaimOutcome> claimNewbie() =>
      _welfareClaim(const ['welfare', 'newbie']);

  Future<WelfareClaimOutcome> claimComeback() =>
      _welfareClaim(const ['welfare', 'comeback']);

  // ── Crafting (D7) ─────────────────────────────────────────────────────────

  Future<List<CraftRecipe>> listRecipes() async {
    final json = await _get(const ['crafting']);
    final raw = json['recipes'];
    return raw is List
        ? raw.whereType<Map>().map(CraftRecipe.fromJson).toList(growable: false)
        : const [];
  }

  Future<CraftOutcome> craft(String recipeId) async {
    final json = await _post(['crafting', recipeId, 'craft']);
    final walletJson = json['wallet'];
    final itemJson = json['item'];
    return CraftOutcome(
      wallet: walletJson is Map ? Wallet.fromJson(walletJson) : const Wallet(),
      item: itemJson is Map
          ? InventoryItem.fromJson(itemJson)
          : const InventoryItem(
              itemId: '',
              kind: ShopItemKind.boardTheme,
              payloadKey: '',
              qty: 1,
            ),
    );
  }

  void close() => _transport.close();

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<WelfareClaimOutcome> _welfareClaim(List<String> segments) async {
    final json = await _post(segments);
    final base = _claimOutcome(json);
    final statusJson = json['status'];
    return WelfareClaimOutcome(
      wallet: base.wallet,
      reward: base.reward,
      status: statusJson is Map
          ? WelfareStatus.fromJson(statusJson)
          : const WelfareStatus(),
    );
  }

  ClaimOutcome _claimOutcome(Map<String, dynamic> json) {
    final walletJson = json['wallet'];
    final rewardJson = json['reward'];
    return ClaimOutcome(
      wallet: walletJson is Map ? Wallet.fromJson(walletJson) : const Wallet(),
      reward: rewardJson is Map
          ? RewardBundle.fromJson(rewardJson)
          : const RewardBundle(),
    );
  }

  Future<Map<String, dynamic>> _get(
    List<String> segments, {
    bool auth = false,
  }) async {
    final headers = auth ? await _authHeader() : const <String, String>{};
    try {
      return await _transport.getJson(_uri(segments),
          headers: headers, timeout: timeout);
    } on PuzzleApiException catch (e) {
      throw _wrap(e);
    }
  }

  Future<Map<String, dynamic>> _post(
    List<String> segments, {
    Map<String, dynamic> body = const {},
  }) async {
    final headers = await _authHeader();
    try {
      return await _transport.postJson(_uri(segments),
          headers: headers, body: body, timeout: timeout);
    } on PuzzleApiException catch (e) {
      throw _wrap(e);
    }
  }

  Future<Map<String, String>> _authHeader() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const EconomyApiException(
        statusCode: 401,
        code: 'missing-token',
        message: 'Cần đăng nhập để dùng tính năng này',
      );
    }
    return {'authorization': 'Bearer $token'};
  }

  EconomyApiException _wrap(PuzzleApiException e) => EconomyApiException(
      statusCode: e.statusCode, code: e.code, message: e.message);

  Uri _uri(List<String> segments) {
    final basePath = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();
    return baseUri.replace(pathSegments: [...basePath, ...segments]);
  }

  static Future<String?> _noToken() async => null;
}

/// Backend-backed economy source wired to the configured HTTP origin +
/// Firebase token (the same origin the shop/puzzle APIs are mounted on).
final economyApiSourceProvider = Provider<EconomyApiSource>((ref) {
  final source = EconomyApiSource(
    baseUri: Uri.parse(AppConstants.defaultBackendHttpUrl),
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.getIdToken();
    },
  );
  ref.onDispose(source.close);
  return source;
});
