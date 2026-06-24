import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/user_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'profile_controller.dart';

/// Hồ Sơ — user profile backed by [profileControllerProvider].
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(profileControllerProvider);

    return asyncProfile.when(
      loading: () => const Center(child: BrushStrokeSpinner()),
      error: (e, _) => Center(child: Text('Lỗi: $e', style: AppTextStyles.bodyMd)),
      data: (profile) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.base,
            AppSpacing.base,
            96,
          ),
          children: [
            _ProfileHeader(profile: profile),
            AppSpacing.vGapLg,
            _StatsGrid(profile: profile),
            AppSpacing.vGapLg,
            _WinLossBar(
              wins: profile.wins,
              draws: profile.draws,
              losses: profile.losses,
            ),
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
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  const _ProfileHeader({required this.profile});

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
              CChessAvatar(
                initials: profile.displayName.isNotEmpty
                    ? profile.displayName[0]
                    : '?',
                size: 72,
                elo: profile.eloChess,
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: AppTextStyles.titleLg,
                      overflow: TextOverflow.ellipsis,
                    ),
                    AppSpacing.vGapXs,
                    Text(
                      '${profile.shortId} • ${profile.region}',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.parchmentTan,
                      ),
                    ),
                    AppSpacing.vGapSm,
                    CChessRankBadge(elo: profile.eloChess),
                    AppSpacing.vGapXs,
                    const _AccountChip(),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => context.go('${AppConstants.routeProfile}/edit'),
                icon: const Icon(Icons.edit_outlined),
                color: AppColors.accentGold,
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: CChessCurrencyDisplay(
                  amount: profile.coins,
                  large: true,
                ),
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: CChessCurrencyDisplay(
                  amount: profile.gems,
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
  final UserProfile profile;
  const _StatsGrid({required this.profile});

  @override
  Widget build(BuildContext context) {
    final winPercent = profile.totalGames == 0
        ? '—'
        : '${(profile.winRate * 100).round()}%';

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.8,
      children: [
        _StatTile(
          label: 'ELO Cờ Tướng',
          value: '${profile.eloChess}',
          icon: Icons.show_chart,
          color: AppColors.accentGold,
        ),
        const _StatTile(
          label: 'ELO Cờ Úp',
          value: '—',
          icon: Icons.help_outline,
          color: AppColors.parchmentTan,
        ),
        _StatTile(
          label: 'Tổng ván',
          value: '${profile.totalGames}',
          icon: Icons.dashboard_outlined,
          color: AppColors.tealSuccess,
        ),
        _StatTile(
          label: 'Tỷ lệ thắng',
          value: winPercent,
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
    if (total == 0) {
      return CChessCard(
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, color: AppColors.parchmentTan),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                'Chưa có ván đấu nào. Bắt đầu chơi để mở thống kê!',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
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
    (Icons.emoji_events, 'Bách Thắng', false),
    (Icons.flag, 'Tân Thủ', true),
    (Icons.local_fire_department, 'Ngũ Liên', false),
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

  @override
  Widget build(BuildContext context) {
    final items = <_MenuEntry>[
      _MenuEntry(
        icon: Icons.workspace_premium,
        label: 'Hội Viên VIP',
        trailingBadge: 'Vàng',
        isVip: true,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('VIP sẽ có ở Sprint 9.')),
          );
        },
      ),
      _MenuEntry(
        icon: Icons.history_edu,
        label: 'Kỳ Phổ Của Tôi',
        onTap: () => context.go(AppConstants.routeHistory),
      ),
      _MenuEntry(
        icon: Icons.emoji_events_outlined,
        label: 'Huy Chương',
        onTap: () => context.go(AppConstants.routeAchievements),
      ),
      _MenuEntry(
        icon: Icons.task_alt_outlined,
        label: 'Nhiệm Vụ Hôm Nay',
        onTap: () => context.go(AppConstants.routeDailyQuests),
      ),
      _MenuEntry(
        icon: Icons.storefront_outlined,
        label: 'Khám Phá (Cửa Hàng & Balo)',
        onTap: () => context.push(AppConstants.routeExplore),
      ),
      _MenuEntry(
        icon: Icons.settings_outlined,
        label: 'Cài Đặt',
        onTap: () => context.go(AppConstants.routeSettings),
      ),
      _MenuEntry(
        icon: Icons.help_outline,
        label: 'Trợ Giúp & Phản Hồi',
        onTap: () {},
      ),
      _MenuEntry(
        icon: Icons.share_outlined,
        label: 'Giới Thiệu Bạn Bè',
        onTap: () {},
      ),
      _MenuEntry(
        icon: Icons.info_outline,
        label: 'Phiên bản',
        trailingBadge: AppConstants.appVersion,
        onTap: () {},
      ),
    ];

    return CChessCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _MenuRow(entry: items[i]),
            if (i != items.length - 1)
              const Divider(height: 1, color: AppColors.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _MenuEntry {
  final IconData icon;
  final String label;
  final String? trailingBadge;
  final bool isVip;
  final VoidCallback onTap;

  _MenuEntry({
    required this.icon,
    required this.label,
    this.trailingBadge,
    this.isVip = false,
    required this.onTap,
  });
}

class _MenuRow extends StatelessWidget {
  final _MenuEntry entry;
  const _MenuRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: entry.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              entry.icon,
              color: entry.isVip ? AppColors.accentGold : AppColors.primary,
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Text(
                entry.label,
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ),
            if (entry.trailingBadge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: entry.isVip
                      ? AppColors.accentGold
                      : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  entry.trailingBadge!,
                  style: AppTextStyles.captionSm.copyWith(
                    color: entry.isVip
                        ? AppColors.surfaceContainerLowest
                        : AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AppSpacing.hGapSm,
            ],
            const Icon(
              Icons.chevron_right,
              color: AppColors.parchmentTan,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small chip under rank badge in profile header — shows account type
/// (anonymous vs Google) and routes to Settings for linking.
class _AccountChip extends StatelessWidget {
  const _AccountChip();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) {
          return const SizedBox.shrink();
        }
        final isAnon = user.isAnonymous;
        final label = isAnon
            ? 'Ẩn danh • Liên kết Google'
            : (user.email ?? user.displayName ?? 'Tài khoản đã liên kết');
        final icon = isAnon ? Icons.link : Icons.verified_user;
        final color = isAnon ? AppColors.parchmentTan : AppColors.tealSuccess;

        return InkWell(
          onTap: () => context.push(AppConstants.routeSettings),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: AppTextStyles.captionSm.copyWith(color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
