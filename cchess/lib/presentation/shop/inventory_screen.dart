import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/inventory_item.dart';
import '../../data/models/shop_item.dart';
import '../../data/models/wallet.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'shop_controller.dart';
import 'shop_visuals.dart';

/// Balo Vật Phẩm (S16 — Inventory). Owned items grouped by [ShopItemKind] tabs.
/// Cosmetics can be equipped/unequipped (one per slot); equipping a board theme
/// re-skins every board in the app. Consumables show their remaining quantity.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invAsync = ref.watch(inventoryProvider);
    final wallet = ref.watch(walletProvider).valueOrNull ?? const Wallet();
    // Inventory docs only carry ids/payload keys — resolve pretty names from
    // the shop catalog (backend → Hive cache, so offline still works).
    final catalog =
        ref.watch(shopCatalogProvider).valueOrNull ?? const <ShopItem>[];
    final catalogNames = {
      for (final s in catalog)
        if (s.nameVi.isNotEmpty) s.id: s.nameVi,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Balo Vật Phẩm'),
      ),
      body: SafeArea(
        child: invAsync.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (e, _) => _Message(
            icon: Icons.cloud_off,
            title: 'Không tải được balo',
            detail: 'Kiểm tra kết nối mạng rồi thử lại.',
            onRetry: () => ref.invalidate(inventoryProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const _Message(
                icon: Icons.backpack_outlined,
                title: 'Balo trống',
                detail: 'Hãy ghé Thương Thành để sắm vật phẩm đầu tiên!',
              );
            }
            final kinds = _orderedKinds(items);
            return DefaultTabController(
              length: kinds.length,
              child: Column(
                children: [
                  Material(
                    color: AppColors.surfaceContainerHigh,
                    child: TabBar(
                      isScrollable: true,
                      labelColor: AppColors.accentGold,
                      unselectedLabelColor: AppColors.onSurfaceVariant,
                      indicatorColor: AppColors.accentGold,
                      tabs: [for (final k in kinds) Tab(text: k.labelVi)],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (final kind in kinds)
                          _KindList(
                            kind: kind,
                            items: items.where((i) => i.kind == kind).toList(),
                            wallet: wallet,
                            catalogNames: catalogNames,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<ShopItemKind> _orderedKinds(List<InventoryItem> items) {
    final present = items.map((i) => i.kind).toSet();
    return [
      for (final k in ShopItemKind.values)
        if (present.contains(k)) k,
    ];
  }
}

class _KindList extends StatelessWidget {
  final ShopItemKind kind;
  final List<InventoryItem> items;
  final Wallet wallet;
  final Map<String, String> catalogNames;
  const _KindList({
    required this.kind,
    required this.items,
    required this.wallet,
    required this.catalogNames,
  });

  @override
  Widget build(BuildContext context) {
    final equippedId = wallet.equippedFor(kind);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      children: [
        for (final item in items)
          _InventoryRow(
            item: item,
            equipped: item.itemId == equippedId,
            catalogNames: catalogNames,
          ),
      ],
    );
  }
}

class _InventoryRow extends ConsumerStatefulWidget {
  final InventoryItem item;
  final bool equipped;
  final Map<String, String> catalogNames;
  const _InventoryRow({
    required this.item,
    required this.equipped,
    required this.catalogNames,
  });

  @override
  ConsumerState<_InventoryRow> createState() => _InventoryRowState();
}

class _InventoryRowState extends ConsumerState<_InventoryRow> {
  bool _busy = false;

  Future<void> _toggleEquip() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(shopControllerProvider);
    try {
      if (widget.equipped) {
        await controller.equip(widget.item.kind, null);
      } else {
        await controller.equip(widget.item.kind, widget.item);
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Không trang bị được, thử lại sau.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // Build a lightweight ShopItem so the preview can reuse the catalog visuals.
    final preview = ShopItem(
      id: item.itemId,
      kind: item.kind,
      nameVi: '',
      descVi: '',
      priceCoins: 0,
      priceGems: 0,
      rarity: Rarity.common,
      payloadKey: item.payloadKey,
      consumable: item.kind == ShopItemKind.consumable,
      consumableQty: 1,
      sortOrder: 0,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CChessCard(
        borderColor:
            widget.equipped ? AppColors.tealSuccess.withValues(alpha: 0.6) : null,
        child: Row(
          children: [
            ShopItemPreview(item: preview, size: 44),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName(item),
                    style: AppTextStyles.bodyMd
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    item.kind == ShopItemKind.consumable
                        ? 'Số lượng: ${item.qty}'
                        : (widget.equipped ? 'Đang dùng' : 'Chưa trang bị'),
                    style: AppTextStyles.captionSm.copyWith(
                      color: widget.equipped
                          ? AppColors.tealSuccess
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (item.kind.isEquippable)
              _busy
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : CChessButton(
                      label: widget.equipped ? 'Gỡ' : 'Trang bị',
                      variant: widget.equipped
                          ? CChessButtonVariant.outline
                          : CChessButtonVariant.primary,
                      onPressed: _toggleEquip,
                    ),
          ],
        ),
      ),
    );
  }

  /// Prefer the pretty catalog name (nameVi); the inventory doc itself only
  /// carries ids. For board themes not in the catalog (e.g. crafted exclusives)
  /// we can still recover a nice label, otherwise fall back to the slot label.
  String _displayName(InventoryItem item) {
    final catalogName = widget.catalogNames[item.itemId];
    if (catalogName != null) return catalogName;
    if (item.kind == ShopItemKind.boardTheme) {
      return 'Bàn ${_boardName(item.payloadKey)}';
    }
    return '${item.kind.labelVi} • ${item.payloadKey}';
  }

  String _boardName(String key) {
    switch (key) {
      case 'sandalwood':
        return 'Đàn Hương';
      case 'jade':
        return 'Ngọc Bích';
      case 'midnight':
        return 'Mực Nửa Đêm';
      case 'festive':
        return 'Tết Đỏ';
      default:
        return key;
    }
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.parchmentTan),
            AppSpacing.vGapMd,
            Text(title, style: AppTextStyles.titleLg, textAlign: TextAlign.center),
            AppSpacing.vGapSm,
            Text(detail,
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center),
            if (onRetry != null) ...[
              AppSpacing.vGapMd,
              CChessButton(label: 'Thử lại', icon: Icons.refresh, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
