import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../datasources/remote/shop_api_source.dart';
import '../models/inventory_item.dart';
import '../models/shop_item.dart';
import '../models/wallet.dart';

/// Repository for the economy (S16 — Khám Phá). Server-authoritative: the
/// backend owns balances and ownership; this layer fetches through
/// [ShopApiSource] and keeps a Hive cache of the last successful catalog,
/// wallet, inventory and equipped loadout so the shop still renders — and the
/// equipped board theme still applies — when offline.
class ShopRepository {
  ShopRepository({ShopApiSource? remote}) : _remote = remote;

  final ShopApiSource? _remote;

  static const String _boxName = AppConstants.boxShop;
  static const String _kCatalog = 'catalog';
  static const String _kWallet = 'wallet';
  static const String _kInventory = 'inventory';

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  // ── Catalog ───────────────────────────────────────────────────────────────

  /// The full catalog: backend → cache fallback. Optionally filtered by [kind].
  Future<List<ShopItem>> catalog({ShopItemKind? kind}) async {
    final remote = _remote;
    if (remote != null) {
      try {
        final items = await remote.listItems();
        await _cacheCatalog(items);
        return kind == null ? items : items.where((i) => i.kind == kind).toList();
      } on ShopApiException {
        // fall through to cache
      }
    }
    final cached = await cachedCatalog();
    return kind == null ? cached : cached.where((i) => i.kind == kind).toList();
  }

  Future<List<ShopItem>> cachedCatalog() async {
    final box = await _openBox();
    final raw = box.get(_kCatalog);
    if (raw is List) {
      return raw.whereType<Map>().map(ShopItem.fromJson).toList(growable: false);
    }
    return const [];
  }

  Future<void> _cacheCatalog(List<ShopItem> items) async {
    final box = await _openBox();
    await box.put(_kCatalog, items.map((i) => i.toJson()).toList());
  }

  // ── Wallet + equipped loadout ──────────────────────────────────────────────

  Future<Wallet> wallet() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final w = await remote.getWallet();
        await _cacheWallet(w);
        return w;
      } on ShopApiException {
        // fall through to cache
      }
    }
    return cachedWallet();
  }

  Future<Wallet> cachedWallet() async {
    final box = await _openBox();
    final raw = box.get(_kWallet);
    return raw is Map ? Wallet.fromJson(raw) : const Wallet();
  }

  /// The equipped loadout (cosmetic kind name → itemId) from cache. Drives the
  /// board theme without waiting on the network.
  Future<Map<String, String>> cachedEquipped() async =>
      (await cachedWallet()).equipped;

  Future<void> _cacheWallet(Wallet w) async {
    final box = await _openBox();
    await box.put(_kWallet, w.toJson());
  }

  // ── Inventory ───────────────────────────────────────────────────────────────

  Future<List<InventoryItem>> inventory() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final items = await remote.listInventory();
        await _cacheInventory(items);
        return items;
      } on ShopApiException {
        // fall through to cache
      }
    }
    return cachedInventory();
  }

  Future<List<InventoryItem>> cachedInventory() async {
    final box = await _openBox();
    final raw = box.get(_kInventory);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map(InventoryItem.fromJson)
          .toList(growable: false);
    }
    return const [];
  }

  Future<void> _cacheInventory(List<InventoryItem> items) async {
    final box = await _openBox();
    await box.put(_kInventory, items.map((i) => i.toJson()).toList());
  }

  // ── Mutations (server-authoritative) ────────────────────────────────────────

  /// Buy [item] with the chosen currency. Throws [ShopApiException] (e.g. 402
  /// insufficient funds) which the caller surfaces to the user. On success the
  /// returned wallet + the new inventory item are written to the cache.
  Future<PurchaseOutcome> purchase(ShopItem item, {required String currency}) async {
    final remote = _remote;
    if (remote == null) {
      throw const ShopApiException(
        code: 'offline',
        message: 'Không thể mua khi ngoại tuyến',
      );
    }
    final outcome = await remote.purchase(item.id, currency: currency);
    await _cacheWallet(outcome.wallet);
    await _mergeInventory(outcome.item);
    return outcome;
  }

  /// Equip [item] (or pass null to unequip [kind]). Returns the updated wallet
  /// (with the new `equipped` map), cached so the board theme updates offline.
  Future<Wallet> equip(ShopItemKind kind, InventoryItem? item) async {
    final remote = _remote;
    if (remote == null) {
      throw const ShopApiException(
        code: 'offline',
        message: 'Không thể trang bị khi ngoại tuyến',
      );
    }
    final w = await remote.equip(kind, item?.itemId);
    await _cacheWallet(w);
    return w;
  }

  Future<void> _mergeInventory(InventoryItem item) async {
    final current = [...await cachedInventory()];
    final idx = current.indexWhere((i) => i.itemId == item.itemId);
    if (idx >= 0) {
      current[idx] = item;
    } else {
      current.add(item);
    }
    await _cacheInventory(current);
  }
}

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository(remote: ref.watch(shopApiSourceProvider));
});
