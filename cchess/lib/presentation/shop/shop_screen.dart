import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/remote/shop_api_source.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/shop_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'shop_controller.dart';
import 'shop_visuals.dart';

/// Thương Thành (S16 — Shop). Catalog grouped by [ShopItemKind] tabs; tap an
/// item to buy it with coins or gems. Owned cosmetics show a badge and can't be
/// re-bought; consumables can be stacked.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(shopCatalogProvider);
    final wallet = ref.watch(walletProvider).valueOrNull;
    final owned =
        ref.watch(inventoryProvider).valueOrNull ?? const <InventoryItem>[];
    final ownedIds = {for (final i in owned) i.itemId};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Thương Thành'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              children: [
                CChessCurrencyDisplay(amount: wallet?.coins ?? 0),
                AppSpacing.hGapXs,
                CChessCurrencyDisplay(
                  amount: wallet?.gems ?? 0,
                  currency: CChessCurrency.gem,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: catalogAsync.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (e, _) => _Message(
            icon: Icons.cloud_off,
            title: 'Không tải được cửa hàng',
            detail: 'Kiểm tra kết nối mạng rồi thử lại.',
            onRetry: () => ref.invalidate(shopCatalogProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const _Message(
                icon: Icons.storefront_outlined,
                title: 'Cửa hàng trống',
                detail: 'Chưa có vật phẩm nào được bày bán.',
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
                          _ItemGrid(
                            items: items.where((i) => i.kind == kind).toList(),
                            ownedIds: ownedIds,
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

  List<ShopItemKind> _orderedKinds(List<ShopItem> items) {
    final present = items.map((i) => i.kind).toSet();
    return [
      for (final k in ShopItemKind.values)
        if (present.contains(k)) k,
    ];
  }
}

class _ItemGrid extends StatelessWidget {
  final List<ShopItem> items;
  final Set<String> ownedIds;
  const _ItemGrid({required this.items, required this.ownedIds});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return _ShopTile(
          item: item,
          owned: !item.consumable && ownedIds.contains(item.id),
        );
      },
    );
  }
}

class _ShopTile extends ConsumerWidget {
  final ShopItem item;
  final bool owned;
  const _ShopTile({required this.item, required this.owned});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = rarityColor(item.rarity);
    return CChessCard(
      onTap: owned ? null : () => _openPurchaseSheet(context, ref, item),
      borderColor: accent.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(child: ShopItemPreview(item: item, size: 56)),
          ),
          AppSpacing.vGapXs,
          Text(
            item.nameVi,
            style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            item.rarity.labelVi,
            style: AppTextStyles.captionSm.copyWith(
              color: accent,
              fontSize: 10,
            ),
          ),
          AppSpacing.vGapXs,
          if (owned)
            Row(
              children: const [
                Icon(
                  Icons.check_circle,
                  size: 14,
                  color: AppColors.tealSuccess,
                ),
                SizedBox(width: 4),
                Text(
                  'Đã sở hữu',
                  style: TextStyle(fontSize: 11, color: AppColors.tealSuccess),
                ),
              ],
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: 2,
              children: [
                if (item.sellsForCoins)
                  _PriceChip(
                    amount: item.priceCoins,
                    currency: CChessCurrency.coin,
                  ),
                if (item.sellsForGems)
                  _PriceChip(
                    amount: item.priceGems,
                    currency: CChessCurrency.gem,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  final int amount;
  final CChessCurrency currency;
  const _PriceChip({required this.amount, required this.currency});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = currency == CChessCurrency.gem
        ? (Icons.diamond_outlined, AppColors.tertiary)
        : (Icons.savings_outlined, AppColors.accentGold);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 2),
        Text('$amount', style: AppTextStyles.captionSm.copyWith(color: color)),
      ],
    );
  }
}

Future<void> _openPurchaseSheet(
  BuildContext context,
  WidgetRef ref,
  ShopItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceContainerHigh,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PurchaseSheet(item: item),
  );
}

class _PurchaseSheet extends ConsumerStatefulWidget {
  final ShopItem item;
  const _PurchaseSheet({required this.item});

  @override
  ConsumerState<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends ConsumerState<_PurchaseSheet> {
  bool _busy = false;
  // Shown INSIDE the sheet: a snackbar would render behind the modal barrier
  // and the user would see no feedback at all (e.g. not enough coins).
  String? _error;

  Future<void> _buy(String currency) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(shopControllerProvider)
          .purchase(widget.item, currency: currency);
      // Success closes the sheet first, so this snackbar is actually visible.
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Đã mua "${widget.item.nameVi}"! Vào Balo để trang bị.',
          ),
        ),
      );
    } on ShopApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isInsufficientFunds
            ? 'Không đủ ${currency == 'gems' ? 'ngọc' : 'xu'} để mua vật phẩm này.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Mua thất bại, thử lại sau.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShopItemPreview(item: item, size: 48),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nameVi, style: AppTextStyles.titleLg),
                    Text(
                      item.rarity.labelVi,
                      style: AppTextStyles.captionSm.copyWith(
                        color: rarityColor(item.rarity),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.descVi.isNotEmpty) ...[
            AppSpacing.vGapSm,
            Text(
              item.descVi,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
          AppSpacing.vGapLg,
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.vermilionRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.vermilionRed.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: AppColors.vermilionRed,
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.vermilionRed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.vGapSm,
          ],
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: BrushStrokeSpinner(),
              ),
            )
          else ...[
            if (item.sellsForCoins)
              CChessButton(
                label: 'Mua • ${item.priceCoins} xu',
                fullWidth: true,
                icon: Icons.savings_outlined,
                onPressed: () => _buy('coins'),
              ),
            if (item.sellsForCoins && item.sellsForGems) AppSpacing.vGapSm,
            if (item.sellsForGems)
              CChessButton(
                label: 'Mua • ${item.priceGems} ngọc',
                variant: CChessButtonVariant.outline,
                fullWidth: true,
                icon: Icons.diamond_outlined,
                onPressed: () => _buy('gems'),
              ),
          ],
        ],
      ),
    );
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
            Text(
              title,
              style: AppTextStyles.titleLg,
              textAlign: TextAlign.center,
            ),
            AppSpacing.vGapSm,
            Text(
              detail,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              AppSpacing.vGapMd,
              CChessButton(
                label: 'Thử lại',
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
