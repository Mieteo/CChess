import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/remote/shop_api_source.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/shop_item.dart';
import '../../data/models/wallet.dart';
import '../../data/repositories/shop_repository.dart';
import '../../widgets/chess/board_theme.dart';

/// The whole shop catalog (backend → cache). The UI groups it by [ShopItemKind].
final shopCatalogProvider = FutureProvider.autoDispose<List<ShopItem>>((ref) {
  return ref.watch(shopRepositoryProvider).catalog();
});

/// The player's wallet (coins/gems + equipped-by-itemId). Authoritative balance.
final walletProvider = FutureProvider.autoDispose<Wallet>((ref) {
  return ref.watch(shopRepositoryProvider).wallet();
});

/// The player's owned items (Balo).
final inventoryProvider =
    FutureProvider.autoDispose<List<InventoryItem>>((ref) {
  return ref.watch(shopRepositoryProvider).inventory();
});

/// Active loadout as `kind name → payloadKey` (resolved from itemId via the
/// inventory), kept loaded for the whole app so every board reflects the
/// equipped theme. Not autoDispose — it outlives any single screen.
final equippedLoadoutProvider =
    StateNotifierProvider<EquippedLoadoutController, Map<String, String>>((ref) {
  return EquippedLoadoutController(ref.watch(shopRepositoryProvider));
});

/// The board theme currently equipped, defaulting to [BoardTheme.classic].
/// [ChessBoard] watches this so equipping a board cosmetic re-skins every board.
final equippedBoardThemeProvider = Provider<BoardTheme>((ref) {
  final loadout = ref.watch(equippedLoadoutProvider);
  return boardThemeForKey(loadout[ShopItemKind.boardTheme.name]);
});

class EquippedLoadoutController extends StateNotifier<Map<String, String>> {
  EquippedLoadoutController(this._repo) : super(const {}) {
    _load();
  }

  final ShopRepository _repo;

  Future<void> _load() async {
    // Cache first for an instant (offline-capable) loadout…
    try {
      final cachedEq = await _repo.cachedEquipped();
      final cachedInv = await _repo.cachedInventory();
      if (mounted) state = _resolve(cachedEq, cachedInv);
    } catch (_) {
      // ignore — fall through to the server refresh
    }
    // …then refresh from the server in the background.
    try {
      final wallet = await _repo.wallet();
      final inv = await _repo.inventory();
      if (mounted) state = _resolve(wallet.equipped, inv);
    } catch (_) {
      // offline / signed-out — keep whatever the cache gave us
    }
  }

  /// Reflect an equip/unequip locally without a refetch.
  void setEquipped(ShopItemKind kind, String? payloadKey) {
    final next = Map<String, String>.of(state);
    if (payloadKey == null || payloadKey.isEmpty) {
      next.remove(kind.name);
    } else {
      next[kind.name] = payloadKey;
    }
    state = next;
  }

  /// Resolve `kind name → itemId` (wallet.equipped) to `kind name → payloadKey`
  /// using the owned inventory, so unknown/uninstalled items simply drop out.
  Map<String, String> _resolve(
    Map<String, String> equippedByItemId,
    List<InventoryItem> inventory,
  ) {
    final payloadByItemId = {for (final i in inventory) i.itemId: i.payloadKey};
    final out = <String, String>{};
    equippedByItemId.forEach((kindName, itemId) {
      final payload = payloadByItemId[itemId];
      if (payload != null && payload.isNotEmpty) out[kindName] = payload;
    });
    return out;
  }
}

/// Action surface for the shop UI: purchase + equip, keeping the wallet,
/// inventory and equipped-loadout providers in sync afterward.
class ShopController {
  ShopController(this._ref, this._repo);

  final Ref _ref;
  final ShopRepository _repo;

  Future<PurchaseOutcome> purchase(ShopItem item, {required String currency}) async {
    final outcome = await _repo.purchase(item, currency: currency);
    _ref.invalidate(walletProvider);
    _ref.invalidate(inventoryProvider);
    return outcome;
  }

  Future<void> equip(ShopItemKind kind, InventoryItem? item) async {
    await _repo.equip(kind, item);
    _ref.invalidate(walletProvider);
    _ref.read(equippedLoadoutProvider.notifier).setEquipped(kind, item?.payloadKey);
  }
}

final shopControllerProvider = Provider<ShopController>((ref) {
  return ShopController(ref, ref.watch(shopRepositoryProvider));
});
