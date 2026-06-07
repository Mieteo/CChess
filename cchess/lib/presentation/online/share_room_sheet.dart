import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import 'room_share.dart';

/// A6 Spectate share link — bottom sheet that lets the user invite others to
/// watch (or join) a room via QR code, copy-link, or the native share sheet.
class ShareRoomSheet extends StatelessWidget {
  const ShareRoomSheet({
    super.key,
    required this.roomId,
    this.spectate = true,
  });

  /// Room id to share.
  final String roomId;

  /// True → invite to watch (spectate). False → invite to join as a player.
  final bool spectate;

  /// Show the sheet. No-op if [roomId] is empty.
  static Future<void> show(
    BuildContext context, {
    required String? roomId,
    bool spectate = true,
  }) {
    final id = (roomId ?? '').trim();
    if (id.isEmpty) return Future<void>.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ShareRoomSheet(roomId: id, spectate: spectate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = RoomShare.normalizeRoomId(roomId);
    final link = RoomShare.linkFor(id, spectate: spectate);
    final title = spectate ? 'Mời xem ván' : 'Mời vào phòng';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  spectate ? Icons.visibility_outlined : Icons.group_add_outlined,
                  color: AppColors.accentGold,
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(title, style: AppTextStyles.headingMd),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            AppSpacing.vGapBase,
            // QR — dark modules on a white card so it scans on the dark theme.
            Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: link,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.inkBlack,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppColors.inkBlack,
                  ),
                ),
              ),
            ),
            AppSpacing.vGapBase,
            Text(
              'Mã phòng',
              textAlign: TextAlign.center,
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            AppSpacing.vGapXs,
            // Room id chip — tap to copy just the code.
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _copy(context, id, label: 'Đã sao chép mã phòng'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      id,
                      style: AppTextStyles.headingMd.copyWith(
                        color: AppColors.accentGold,
                        letterSpacing: 4,
                      ),
                    ),
                    AppSpacing.hGapSm,
                    const Icon(
                      Icons.copy,
                      size: 18,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            AppSpacing.vGapBase,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.link),
                    label: const Text('Sao chép link'),
                    onPressed: () =>
                        _copy(context, link, label: 'Đã sao chép link'),
                  ),
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text('Chia sẻ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentGold,
                      foregroundColor: AppColors.inkBlack,
                    ),
                    onPressed: () => _share(context, id),
                  ),
                ),
              ],
            ),
            AppSpacing.vGapSm,
            Text(
              spectate
                  ? 'Người nhận quét QR hoặc mở link để xem ván trực tiếp.'
                  : 'Gửi cho bạn bè để họ vào đánh cùng phòng.',
              textAlign: TextAlign.center,
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(
    BuildContext context,
    String text, {
    required String label,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _share(BuildContext context, String id) async {
    final text = RoomShare.inviteText(id, spectate: spectate);
    final subject = spectate
        ? 'Mời xem ván Cờ Tướng — phòng $id'
        : 'Mời đấu Cờ Tướng — phòng $id';
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: subject),
      );
    } catch (_) {
      // Share unavailable (e.g. desktop without a handler) → fall back to copy.
      if (!context.mounted) return;
      await _copy(context, text, label: 'Đã sao chép lời mời');
    }
  }
}
