import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/reconnect_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import 'online_match_controller.dart';

class OnlineLobbyScreen extends ConsumerStatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  ConsumerState<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends ConsumerState<OnlineLobbyScreen> {
  final _urlCtrl = TextEditingController(text: AppConstants.defaultBackendWsUrl);
  final _roomIdCtrl = TextEditingController();
  bool _busy = false;
  String? _localError;
  bool _reconnectAttempted = false;

  OnlineMatchController get _ctrl =>
      ref.read(onlineMatchControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Step 8: if a fresh reconnect state exists, auto-connect + reconnect.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_reconnectAttempted) return;
      _reconnectAttempted = true;
      // Only auto-reconnect if we're idle (not already in a flow)
      final s = ref.read(onlineMatchControllerProvider);
      if (s.phase != OnlineMatchPhase.idle) return;
      // Probe storage first — avoid touching network if no saved state
      final store = ref.read(reconnectStoreProvider);
      final saved = await store.readFresh();
      if (saved == null || !mounted) return;
      // Auto-connect then try reconnect
      await _run(() async {
        await _ctrl.connect(_urlCtrl.text.trim());
        // Wait for authed phase before sending reconnect-room
        const maxWaitMs = 5000;
        const stepMs = 50;
        var waited = 0;
        while (waited < maxWaitMs) {
          final phase = ref.read(onlineMatchControllerProvider).phase;
          if (phase == OnlineMatchPhase.authed) break;
          if (phase == OnlineMatchPhase.error) return;
          await Future<void>.delayed(const Duration(milliseconds: stepMs));
          waited += stepMs;
        }
        if (!mounted) return;
        if (ref.read(onlineMatchControllerProvider).phase ==
            OnlineMatchPhase.authed) {
          _ctrl.reconnectRoom(saved);
        }
      });
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _roomIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _localError = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _localError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
        await _ctrl.connect(_urlCtrl.text.trim());
      });

  void _createRoom() {
    setState(() => _localError = null);
    _ctrl.createRoom();
  }

  void _joinRoom() {
    final id = _roomIdCtrl.text.trim().toUpperCase();
    if (id.isEmpty) {
      setState(() => _localError = 'Nhập room ID');
      return;
    }
    setState(() => _localError = null);
    _ctrl.joinRoom(id);
  }

  Future<void> _leave() async {
    await _ctrl.leave();
    if (mounted) context.go(AppConstants.routeCompete);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onlineMatchControllerProvider);

    // Auto-navigate when game starts
    ref.listen<OnlineMatchState>(onlineMatchControllerProvider, (prev, next) {
      if (next.phase == OnlineMatchPhase.playing &&
          prev?.phase != OnlineMatchPhase.playing) {
        context.push(AppConstants.routeOnlineGame);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Xếp Hạng Online'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeCompete),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhaseBadge(phase: state.phase, roomId: state.roomId),
              AppSpacing.vGapBase,
              if (state.phase == OnlineMatchPhase.idle ||
                  state.phase == OnlineMatchPhase.error) ...[
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    helperText:
                        'default từ AppConstants.defaultBackendWsUrl',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                AppSpacing.vGapBase,
                ElevatedButton.icon(
                  icon: const Icon(Icons.cable),
                  label: const Text('Kết nối + Đăng nhập'),
                  onPressed: _busy ? null : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.woodDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
              if (state.phase == OnlineMatchPhase.authed) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo phòng mới'),
                  onPressed: _busy ? null : _createRoom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGold,
                    foregroundColor: AppColors.inkBlack,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                AppSpacing.vGapBase,
                const Text('— hoặc vào phòng có sẵn —',
                    textAlign: TextAlign.center),
                AppSpacing.vGapBase,
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _roomIdCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Room ID',
                          helperText: '6 ký tự',
                          prefixIcon: Icon(Icons.meeting_room_outlined),
                        ),
                      ),
                    ),
                    AppSpacing.hGapSm,
                    ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Vào'),
                      onPressed: _busy ? null : _joinRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.woodDark,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
              if (state.phase == OnlineMatchPhase.waitingForPeer) ...[
                AppSpacing.vGapLg,
                const Center(child: CircularProgressIndicator()),
                AppSpacing.vGapBase,
                Center(
                  child: Text(
                    'Đang chờ đối thủ vào phòng…',
                    style: AppTextStyles.bodyMd,
                  ),
                ),
                AppSpacing.vGapSm,
                Center(
                  child: SelectableText(
                    'Mã phòng: ${state.roomId ?? "—"}',
                    style: AppTextStyles.headingMd.copyWith(
                      color: AppColors.accentGold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                AppSpacing.vGapBase,
                Center(
                  child: Text(
                    '(Gửi mã này cho bạn để vào cùng phòng)',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (state.errorMessage != null) ...[
                AppSpacing.vGapBase,
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    state.errorMessage!,
                    style: AppTextStyles.captionSm,
                  ),
                ),
              ],
              if (_localError != null) ...[
                AppSpacing.vGapBase,
                Text(
                  _localError!,
                  style: AppTextStyles.captionSm
                      .copyWith(color: Colors.redAccent),
                ),
              ],
              const Spacer(),
              if (state.phase != OnlineMatchPhase.idle)
                TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Rời + ngắt kết nối'),
                  onPressed: _busy ? null : _leave,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.phase, required this.roomId});
  final OnlineMatchPhase phase;
  final String? roomId;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (phase) {
      OnlineMatchPhase.idle => ('Chưa kết nối', AppColors.parchmentTan, Icons.cloud_off),
      OnlineMatchPhase.connecting => ('Đang kết nối…', AppColors.parchmentTan, Icons.sync),
      OnlineMatchPhase.authed => ('Đã đăng nhập, sẵn sàng', AppColors.tealSuccess, Icons.check_circle),
      OnlineMatchPhase.waitingForPeer => ('Phòng ${roomId ?? "?"} — chờ đối thủ', AppColors.accentGold, Icons.hourglass_top),
      OnlineMatchPhase.playing => ('Đang đánh', AppColors.tealSuccess, Icons.sports_esports),
      OnlineMatchPhase.peerDisconnected => ('Đối thủ mất kết nối — chờ reconnect…', AppColors.accentGold, Icons.wifi_off),
      OnlineMatchPhase.reconnecting => ('Đang reconnect vào ván cũ…', AppColors.accentGold, Icons.refresh),
      OnlineMatchPhase.ended => ('Ván kết thúc', AppColors.parchmentTan, Icons.flag),
      OnlineMatchPhase.error => ('Lỗi', Colors.redAccent, Icons.error),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: AppTextStyles.bodyMd.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
