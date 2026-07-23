import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/economy_models.dart';
import '../../data/models/inventory_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../shop/shop_controller.dart';
import 'economy_controller.dart';
import 'economy_widgets.dart';

/// Đúc Bàn Cờ (S16 D7). Craft recipes burn ingredient items + coins into a
/// unique cosmetic. Ingredient availability is resolved against the player's
/// inventory; the craft itself is validated server-side in one transaction.
class CraftingScreen extends ConsumerWidget {
  const CraftingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesAsync = ref.watch(craftRecipesProvider);
    final wallet = ref.watch(walletProvider).valueOrNull;
    final owned =
        ref.watch(inventoryProvider).valueOrNull ?? const <InventoryItem>[];
    final ownedQty = {for (final i in owned) i.itemId: i.qty};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Đúc Bàn Cờ'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              children: [
                CChessCurrencyDisplay(amount: wallet?.coins ?? 0),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: recipesAsync.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (e, _) => EconomyMessage(
            icon: Icons.cloud_off,
            title: 'Không tải được công thức',
            detail: 'Kiểm tra kết nối mạng rồi thử lại.',
            onRetry: () => ref.invalidate(craftRecipesProvider),
          ),
          data: (recipes) {
            if (recipes.isEmpty) {
              return const EconomyMessage(
                icon: Icons.handyman_outlined,
                title: 'Chưa có công thức',
                detail:
                    'Công thức đúc bàn cờ độc bản sẽ xuất hiện ở đây. '
                    'Nguyên liệu rơi từ sự kiện và quà điểm danh.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.base,
                96,
              ),
              itemCount: recipes.length,
              itemBuilder: (context, i) => _RecipeCard(
                recipe: recipes[i],
                coins: wallet?.coins ?? 0,
                ownedQty: ownedQty,
                alreadyOwned: ownedQty.containsKey(recipes[i].output.itemId),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecipeCard extends ConsumerWidget {
  final CraftRecipe recipe;
  final int coins;
  final Map<String, int> ownedQty;
  final bool alreadyOwned;

  const _RecipeCard({
    required this.recipe,
    required this.coins,
    required this.ownedQty,
    required this.alreadyOwned,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(economyControllerProvider);
    final haveAllIngredients = recipe.ingredients
        .every((ing) => (ownedQty[ing.itemId] ?? 0) >= ing.qty);
    final haveCoins = coins >= recipe.costCoins;
    final canCraft = haveAllIngredients && haveCoins && !alreadyOwned;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: CChessCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: AppColors.accentGold, size: 20),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(recipe.nameVi, style: AppTextStyles.headingMd),
                ),
                if (alreadyOwned)
                  const Icon(Icons.check_circle, color: AppColors.tealSuccess),
              ],
            ),
            if (recipe.descVi.isNotEmpty) ...[
              AppSpacing.vGapXs,
              Text(
                recipe.descVi,
                style: AppTextStyles.captionSm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
            AppSpacing.vGapSm,
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final ing in recipe.ingredients)
                  _IngredientChip(
                    ingredient: ing,
                    have: ownedQty[ing.itemId] ?? 0,
                  ),
                if (recipe.costCoins > 0)
                  _CostChip(cost: recipe.costCoins, enough: haveCoins),
              ],
            ),
            AppSpacing.vGapMd,
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: canCraft
                      ? AppColors.accentGold
                      : AppColors.surfaceContainerHigh,
                  foregroundColor: canCraft
                      ? AppColors.inkBlack
                      : AppColors.onSurfaceVariant,
                ),
                icon: const Icon(Icons.handyman, size: 18),
                label: Text(
                  alreadyOwned
                      ? 'Đã sở hữu'
                      : !haveAllIngredients
                          ? 'Chưa đủ nguyên liệu'
                          : !haveCoins
                              ? 'Chưa đủ đồng'
                              : 'Đúc ngay',
                ),
                onPressed: !canCraft
                    ? null
                    : () async {
                        try {
                          final outcome = await controller.craft(recipe.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Đã đúc thành công ${recipe.nameVi}!',
                                ),
                                backgroundColor: AppColors.tealSuccess,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                          // The crafted cosmetic lands in the Balo; wallet +
                          // inventory providers are already re-synced.
                          // ignore: unused_local_variable
                          final _ = outcome;
                        } catch (e) {
                          if (context.mounted) showEconomyError(context, e);
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IngredientChip extends StatelessWidget {
  final CraftIngredient ingredient;
  final int have;
  const _IngredientChip({required this.ingredient, required this.have});

  @override
  Widget build(BuildContext context) {
    final enough = have >= ingredient.qty;
    final color = enough ? AppColors.tealSuccess : AppColors.vermilionRed;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${ingredient.itemId} $have/${ingredient.qty}',
        style: AppTextStyles.captionSm.copyWith(color: color),
      ),
    );
  }
}

class _CostChip extends StatelessWidget {
  final int cost;
  final bool enough;
  const _CostChip({required this.cost, required this.enough});

  @override
  Widget build(BuildContext context) {
    final color = enough ? AppColors.accentGold : AppColors.vermilionRed;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$cost đồng',
        style: AppTextStyles.captionSm.copyWith(color: color),
      ),
    );
  }
}
