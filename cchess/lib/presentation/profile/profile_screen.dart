import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

/// Hồ Sơ — user profile, stats, achievements, settings entry.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      children: [
        const _ProfileHeader(),
        AppSpacing.vGapLg,
        const _StatsGrid(),
        AppSpacing.vGapLg,
        const _WinLossBar(wins: 124, draws: 18, losses: 76),
        AppSpacing.vGapLg,
        SectionHeader(
          title: 'Huy Chương',
          actionLabel: 'Xem tất cả',
          onActionPressed: () {},
        ),
        AppSpacing.vGapMd,
        const _AchievementGrid(),
        AppSpacing.vGapLg,
        const _ProfileMenu(),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.charcoalDark, AppColors.woodDark],
      ),
      borderColor: AppColors.accentGold.withValues(alpha: 0.4),
      child: Column(
        children: [
          Row(
            children: [
              const CChessAvatar(initials: 'KV', size: 72, elo: 1820),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kỳ Vương Việt', style: AppTextStyles.titleLg),
                    AppSpacing.vGapXs,
                    Text(
                      'ID: #A91886313',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.parchmentTan,
                      ),
                    ),
                    AppSpacing.vGapSm,
                    const CChessRankBadge(elo: 1820),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.edit_outlined),
                color: AppColors.accentGold,
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              const Expanded(
                child: CChessCurrencyDisplay(amount: 2278, large: true),
              ),
              AppSpacing.hGapSm,
              const Expanded(
                child: CChessCurrencyDisplay(
                  amount: 1000,
                  currency: CChessCurrency.gem,
                  large: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.8,
      children: const [
        _StatTile(
          label: 'ELO Cờ Tướng',
          value: '1820',
          icon: Icons.show_chart,
          color: AppColors.accentGold,
        ),
        _StatTile(
          label: 'ELO Cờ Úp',
          value: '—',
          icon: Icons.help_outline,
          color: AppColors.parchmentTan,
        ),
        _StatTile(
          label: 'Tổng ván',
          value: '218',
          icon: Icons.dashboard_outlined,
          color: AppColors.tealSuccess,
        ),
        _StatTile(
          label: 'Tỷ lệ thắng',
          value: '56%',
          icon: Icons.flag_outlined,
          color: AppColors.vermilionRed,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      borderColor: color.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AppTextStyles.headingMd),
                Text(
                  label,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WinLossBar extends StatelessWidget {
  final int wins, draws, losses;

  const _WinLossBar({
    required this.wins,
    required this.draws,
    required this.losses,
  });

  @override
  Widget build(BuildContext context) {
    final total = wins + draws + losses;
    if (total == 0) return const SizedBox.shrink();
    final winRatio = wins / total;
    final drawRatio = draws / total;
    final lossRatio = losses / total;

    return CChessCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  flex: (winRatio * 1000).round(),
                  child: Container(height: 16, color: AppColors.tealSuccess),
                ),
                Expanded(
                  flex: (drawRatio * 1000).round(),
                  child: Container(height: 16, color: AppColors.accentGold),
                ),
                Expanded(
                  flex: (lossRatio * 1000).round(),
                  child: Container(height: 16, color: AppColors.vermilionRed),
                ),
              ],
            ),
          ),
          AppSpacing.vGapSm,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _legend('Thắng $wins', AppColors.tealSuccess),
              _legend('Hòa $draws', AppColors.accentGold),
              _legend('Thua $losses', AppColors.vermilionRed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          AppSpacing.hGapXs,
          Text(label, style: AppTextStyles.captionSm),
        ],
      );
}

class _AchievementGrid extends StatelessWidget {
  const _AchievementGrid();

  static const _achievements = <(IconData, String, bool)>[
    (Icons.emoji_events, 'Bách Thắng', true),
    (Icons.flag, 'Tân Thủ', true),
    (Icons.local_fire_department, 'Ngũ Liên', true),
    (Icons.shield, 'Phòng Thủ', false),
    (Icons.bolt, 'Tốc Chiến', false),
    (Icons.psychology, 'Học Giả', false),
    (Icons.diamond, 'Kỳ Vương', false),
    (Icons.star, 'Bí Ẩn', false),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.9,
      ),
      itemCount: _achievements.length,
      itemBuilder: (_, i) {
        final (icon, name, unlocked) = _achievements[i];
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: unlocked
                    ? AppColors.accentGold.withValues(alpha: 0.18)
                    : AppColors.surfaceContainerHigh,
                shape: BoxShape.circle,
                border: Border.all(
                  color: unlocked
                      ? AppColors.accentGold
                      : AppColors.outlineVariant,
                ),
              ),
              child: Icon(
                icon,
                color: unlocked ? AppColors.accentGold : AppColors.parchmentTan,
                size: 24,
              ),
            ),
            AppSpacing.vGapXs,
            Text(
              name,
              textAlign: TextAlign.center,
              style: AppTextStyles.captionSm.copyWith(
                color: unlocked
                    ? AppColors.onSurface
                    : AppColors.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu();

  static const _items = <(IconData, String, bool, String?)>[
    (Icons.workspace_premium, 'Hội Viên VIP', false, 'Vàng'),
    (Icons.analytics_outlined, 'Thống Kê Chi Tiết', false, null),
    (Icons.emoji_events_outlined, 'Huy Chương', false, null),
    (Icons.checkroom_outlined, 'Trang Phục Cá Nhân', false, null),
    (Icons.settings_outlined, 'Cài Đặt', false, null),
    (Icons.help_outline, 'Trợ Giúp & Phản Hồi', false, null),
    (Icons.share_outlined, 'Giới Thiệu Bạn Bè', false, null),
    (Icons.info_outline, 'Phiên bản', false, '1.0.0'),
  ];

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            _MenuRow(
              icon: _items[i].$1,
              title: _items[i].$2,
              trailingBadge: _items[i].$4,
              isVip: i == 0,
              onTap: () {},
            ),
            if (i != _items.length - 1)
              const Divider(height: 1, color: AppColors.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingBadge;
  final bool isVip;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.title,
    required this.trailingBadge,
    required this.isVip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isVip ? AppColors.accentGold : AppColors.primary,
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ),
            if (trailingBadge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isVip
                      ? AppColors.accentGold
                      : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trailingBadge!,
                  style: AppTextStyles.captionSm.copyWith(
                    color: isVip
                        ? AppColors.surfaceContainerLowest
                        : AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AppSpacing.hGapSm,
            ],
            const Icon(Icons.chevron_right,
                color: AppColors.parchmentTan, size: 20),
          ],
        ),
      ),
    );
  }
}
