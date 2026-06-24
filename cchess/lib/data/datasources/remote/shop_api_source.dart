import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../models/inventory_item.dart';
import '../../models/shop_item.dart';
import '../../models/wallet.dart';
import 'puzzle_api_transport.dart';
import 'puzzle_api_transport_factory.dart';

typedef ShopTokenProvider = Future<String?> Function();

/// Thrown when a shop REST call fails (network, non-2xx, or malformed body).
/// Mirrors the backend error envelope `{ code, message }`.
class ShopApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const ShopApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// True when the request never reached the server (offline / timeout / web
  /// stub) — the caller can fall back to the cached catalog/wallet.
  bool get isNetworkError => statusCode == null;

  /// True when the user is out of coins/gems for the chosen currency.
  bool get isInsufficientFunds => statusCode == 402;

  @override
  String toString() => 'ShopApiException($code): $message';
}

/// Result of a successful purchase: the debited wallet + the granted item.
class PurchaseOutcome {
  final Wallet wallet;
  final InventoryItem item;
  const PurchaseOutcome({required this.wallet, required this.item});
}

/// Talks to the cchess-backend economy REST API (S16 — Thương Thành / Balo).
///
/// Catalog reads (`listItems`, `getItem`) need no auth; the rest send the
/// Firebase ID token as a Bearer header. All methods throw [ShopApiException]
/// on failure — the repository decides when to fall back to the cache.
class ShopApiSource {
  ShopApiSource({
    required this.baseUri,
    ShopTokenProvider? tokenProvider,
    PuzzleApiTransport? transport,
    this.timeout = const Duration(seconds: 8),
  })  : _tokenProvider = tokenProvider ?? _noToken,
        _transport = transport ?? createDefaultPuzzleApiTransport();

  final Uri baseUri;
  final ShopTokenProvider _tokenProvider;
  final PuzzleApiTransport _transport;
  final Duration timeout;

  Future<List<ShopItem>> listItems({ShopItemKind? kind}) async {
    final json = await _get(
      const ['shop'],
      query: kind == null ? null : {'kind': kind.name},
    );
    return _items(json['items']);
  }

  Future<ShopItem?> getItem(String id) async {
    try {
      final json = await _get(['shop', id]);
      return ShopItem.fromJson(json);
    } on ShopApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Wallet> getWallet() async {
    final json = await _get(const ['wallet'], auth: true);
    return Wallet.fromJson(json);
  }

  Future<List<InventoryItem>> listInventory() async {
    final json = await _get(const ['inventory'], auth: true);
    final raw = json['items'];
    return raw is List
        ? raw.whereType<Map>().map(InventoryItem.fromJson).toList(growable: false)
        : const <InventoryItem>[];
  }

  Future<PurchaseOutcome> purchase(String itemId, {required String currency}) async {
    final json = await _post(
      ['shop', itemId, 'purchase'],
      body: {'currency': currency},
    );
    final walletJson = json['wallet'];
    final itemJson = json['item'];
    return PurchaseOutcome(
      wallet: walletJson is Map ? Wallet.fromJson(walletJson) : const Wallet(),
      item: itemJson is Map
          ? InventoryItem.fromJson(itemJson)
          : InventoryItem(itemId: itemId, kind: ShopItemKind.consumable, payloadKey: '', qty: 1),
    );
  }

  /// Equip [itemId] in [kind]'s slot, or pass `null` to unequip the slot.
  Future<Wallet> equip(ShopItemKind kind, String? itemId) async {
    final json = await _post(
      const ['inventory', 'equip'],
      body: {'kind': kind.name, 'itemId': itemId},
    );
    return Wallet.fromJson(json);
  }

  void close() => _transport.close();

  // ── Internals ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
    List<String> segments, {
    Map<String, String>? query,
    bool auth = false,
  }) async {
    final headers = auth ? await _authHeader() : const <String, String>{};
    try {
      return await _transport.getJson(_uri(segments, query),
          headers: headers, timeout: timeout);
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
      return await _transport.postJson(_uri(segments),
          headers: headers, body: body, timeout: timeout);
    } on PuzzleApiException catch (e) {
      throw _wrap(e);
    }
  }

  Future<Map<String, String>> _authHeader() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const ShopApiException(
        statusCode: 401,
        code: 'missing-token',
        message: 'Cần đăng nhập để dùng cửa hàng',
      );
    }
    return {'authorization': 'Bearer $token'};
  }

  List<ShopItem> _items(Object? raw) => raw is List
      ? raw.whereType<Map>().map(ShopItem.fromJson).toList(growable: false)
      : const <ShopItem>[];

  ShopApiException _wrap(PuzzleApiException e) =>
      ShopApiException(statusCode: e.statusCode, code: e.code, message: e.message);

  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final basePath = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();
    return baseUri.replace(
      pathSegments: [...basePath, ...segments],
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  static Future<String?> _noToken() async => null;
}

/// Backend-backed shop source wired to the configured HTTP origin + Firebase
/// token (the same origin the puzzle API is mounted on).
final shopApiSourceProvider = Provider<ShopApiSource>((ref) {
  final source = ShopApiSource(
    baseUri: Uri.parse(AppConstants.defaultBackendHttpUrl),
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.getIdToken();
    },
  );
  ref.onDispose(source.close);
  return source;
});
