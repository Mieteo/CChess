import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/cloud_sync_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/loading_overlay.dart';

/// Initial splash screen — ink-wash background, logo fade-in, brush spinner.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _logoFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();

    _navigateAfterSplash();
  }

  Future<void> _navigateAfterSplash() async {
    final sync = ref.read(cloudSyncServiceProvider);
    final results = await Future.wait([
      Future.delayed(const Duration(milliseconds: 2200)),
      sync.syncOnStart(),
    ]);
    if (!mounted) return;
    final result = results[1] as CloudSyncResult;
    final destination = result.profile.onboardingCompleted
        ? AppConstants.routeHome
        : AppConstants.routeOnboarding;
    context.go(destination);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 1.1,
            colors: [
              Color(0xFF231F1C),
              AppColors.background,
              Color(0xFF0A0805),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            alignment: Alignment.center,
            children: [
              const _InkWashBackdrop(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Column(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.goldButtonGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accentGold.withValues(alpha: 0.4),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '楚',
                              style: AppTextStyles.pieceText(
                                AppColors.inkBlack,
                                64,
                              ),
                            ),
                          ),
                          AppSpacing.vGapLg,
                          Text(
                            AppConstants.appNameVi,
                            style: AppTextStyles.displayCalligraphy,
                          ),
                          AppSpacing.vGapSm,
                          Text(
                            'Cờ Tướng Việt Nam',
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.parchmentTan,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AppSpacing.vGapXl,
                  const BrushStrokeSpinner(size: 44),
                ],
              ),
              Positioned(
                bottom: AppSpacing.lg,
                child: Text(
                  'v${AppConstants.appVersion}',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InkWashBackdrop extends StatelessWidget {
  const _InkWashBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _InkWashPainter()),
      ),
    );
  }
}

class _InkWashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.woodDark.withValues(alpha: 0.18);
    // Soft "ink mountain" silhouettes at the bottom.
    final path = Path()
      ..moveTo(0, size.height * 0.78)
      ..quadraticBezierTo(size.width * 0.18, size.height * 0.62,
          size.width * 0.36, size.height * 0.74)
      ..quadraticBezierTo(size.width * 0.52, size.height * 0.86,
          size.width * 0.7, size.height * 0.7)
      ..quadraticBezierTo(size.width * 0.86, size.height * 0.56,
          size.width, size.height * 0.72)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);

    paint.color = AppColors.charcoalDark.withValues(alpha: 0.35);
    final path2 = Path()
      ..moveTo(0, size.height * 0.88)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.78,
          size.width * 0.55, size.height * 0.88)
      ..quadraticBezierTo(size.width * 0.78, size.height * 0.98,
          size.width, size.height * 0.86)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant _InkWashPainter old) => false;
}
