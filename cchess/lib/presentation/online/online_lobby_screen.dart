import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../data/datasources/remote/tournaments_api_source.dart';
import '../../data/services/reconnect_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import 'online_match_controller.dart';
import 'room_share.dart';
import 'share_room_sheet.dart';

class OnlineLobbyScreen extends ConsumerStatefulWidget {
  const OnlineLobbyScreen({
    super.key,
    this.deepLinkRoomId,
    this.deepLinkSpectate = true,
    this.initialCasual = false,
    this.variant = 'standard',
    this.tournamentId,
    this.matchId,
  });

  /// A6 share link: when arriving via a shared link the room id is passed here;
  /// the lobby auto-connects then spectates ([deepLinkSpectate] true) or joins.
  final String? deepLinkRoomId;
  final bool deepLinkSpectate;
  final bool initialCasual;

  /// Game variant for matchmaking / private rooms created here. `cup` queues in
  /// the Cờ Úp pool (own ELO bucket, never paired against standard players).
  final String variant;

  /// S14 C4 "Vào trận": when both are set, the lobby auto-connects then either
  /// creates a tournament-tagged room (first player) or joins the room the
  /// other player already created (discovered via GET /tournaments/:id/matches
  /// — see tournament_detail_screen.dart), instead of the normal manual
  /// create/find-match UI.
  final String? tournamentId;
  final String? matchId;

  @override
  ConsumerState<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends ConsumerState<OnlineLobbyScreen> {
  final _urlCtrl = TextEditingController(
    text: AppConstants.defaultBackendWsUrl,
  );
  final _roomIdCtrl = TextEditingController();
  bool _busy = false;
  String? _localError;
  bool _reconnectAttempted = false;

  /// Step A5: clock per side khi tạo phòng. Default 10 phút.
  int _selectedClockMin = 10;
  static const List<int> _clockOptions = [3, 5, 10, 15, 30];

  OnlineMatchController get _ctrl =>
      ref.read(onlineMatchControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_reconnectAttempted) return;
      _reconnectAttempted = true;
      // Only auto-act if we're idle (not already in a flow)
      final s = ref.read(onlineMatchControllerProvider);
      if (s.phase != OnlineMatchPhase.idle) return;

      // A6 share link: a deep-link room id takes priority over reconnect —
      // connect then spectate (or join) the shared room.
      final deepLinkId = widget.deepLinkRoomId;
      if (deepLinkId != null && RoomShare.isValidRoomId(deepLinkId)) {
        final roomId = RoomShare.normalizeRoomId(deepLinkId);
        await _run(() async {
          if (!await _connectAndWaitAuthed() || !mounted) return;
          if (widget.deepLinkSpectate) {
            _ctrl.spectateRoom(roomId);
          } else {
            _ctrl.joinRoom(roomId);
          }
        });
        return;
      }

      // S14 C4 "Vào trận": create the tagged room (first player) or join the
      // one the other player already created.
      final tournamentId = widget.tournamentId;
      final matchId = widget.matchId;
      if (tournamentId != null && matchId != null) {
        await _run(() async {
          if (!await _connectAndWaitAuthed() || !mounted) return;
          final matches = await ref.read(tournamentsApiSourceProvider).listMatches(tournamentId);
          final match = matches.where((m) => m.id == matchId).firstOrNull;
          if (!mounted) return;
          if (match == null) {
            throw const TournamentApiException(code: 'not-found', message: 'Không tìm thấy trận đấu');
          }
          if (match.roomId != null) {
            _ctrl.joinRoom(match.roomId!);
          } else {
            _ctrl.createRoom(
              clockMs: 15 * 60 * 1000,
              tournamentTag: {'tournamentId': tournamentId, 'matchId': matchId},
            );
          }
        });
        return;
      }

      // Step 8: if a fresh reconnect state exists, auto-connect + reconnect.
      // Probe storage first — avoid touching network if no saved state.
      final store = ref.read(reconnectStoreProvider);
      final saved = await store.readFresh();
      if (saved == null || !mounted) return;
      await _run(() async {
        if (!await _connectAndWaitAuthed() || !mounted) return;
        _ctrl.reconnectRoom(saved);
      });
    });
  }

  /// Connect, then wait until the controller reaches the `authed` phase.
  /// Returns false if the connection errored or timed out. Shared by the
  /// reconnect and the A6 share-link deep-link flows.
  Future<bool> _connectAndWaitAuthed() async {
    await _ctrl.connect(_urlCtrl.text.trim());
    const maxWaitMs = 5000;
    const stepMs = 50;
    var waited = 0;
    while (waited < maxWaitMs) {
      final phase = ref.read(onlineMatchControllerProvider).phase;
      if (phase == OnlineMatchPhase.authed) return true;
      if (phase == OnlineMatchPhase.error) return false;
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
      waited += stepMs;
    }
    return ref.read(onlineMatchControllerProvider).phase ==
        OnlineMatchPhase.authed;
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

  String? get _variantArg => widget.variant == 'cup' ? 'cup' : null;

  void _createRoom() {
    setState(() => _localError = null);
    _ctrl.createRoom(
      clockMs: _selectedClockMin * 60 * 1000,
      casual: widget.initialCasual,
      variant: _variantArg,
    );
  }

  void _findMatch() {
    setState(() => _localError = null);
    _ctrl.findMatch(
      clockMs: _selectedClockMin * 60 * 1000,
      variant: _variantArg,
    );
  }

  void _cancelMatching() {
    setState(() => _localError = null);
    _ctrl.cancelMatching();
  }

  void _refreshActiveRooms() {
    setState(() => _localError = null);
    _ctrl.requestActiveRooms();
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

  void _spectateRoom() {
    final id = _roomIdCtrl.text.trim().toUpperCase();
    if (id.isEmpty) {
      setState(() => _localError = 'Nhập room ID');
      return;
    }
    setState(() => _localError = null);
    _ctrl.spectateRoom(id);
  }

  void _spectateRoomId(String roomId) {
    setState(() => _localError = null);
    _ctrl.spectateRoom(roomId);
  }

  Future<void> _leave() async {
    await _ctrl.leave();
    if (mounted) context.go(AppConstants.routeCompete);
  }

  String _lobbyTitle() {
    final isCup = widget.variant == 'cup';
    if (isCup) return widget.initialCasual ? 'Cờ Úp Casual' : 'Cờ Úp Online';
    return widget.initialCasual ? 'Cờ Casual' : 'Xếp Hạng Online';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onlineMatchControllerProvider);

    // Auto-navigate when game starts, or when spectate snapshot arrives.
    ref.listen<OnlineMatchState>(onlineMatchControllerProvider, (prev, next) {
      if (next.phase == OnlineMatchPhase.authed &&
          prev?.phase != OnlineMatchPhase.authed) {
        _ctrl.requestActiveRooms();
      }
      final enteredBoard =
          next.phase == OnlineMatchPhase.playing ||
          next.phase == OnlineMatchPhase.spectating;
      if (enteredBoard &&
          prev?.phase != next.phase &&
          !ref.read(onlineGameOpenProvider)) {
        context.push(AppConstants.routeOnlineGame);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: Text(_lobbyTitle()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeCompete),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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
                    helperText: 'default từ AppConstants.defaultBackendWsUrl',
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
                Text(
                  'Thời gian mỗi bên',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppSpacing.vGapXs,
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in _clockOptions)
                      ChoiceChip(
                        label: Text('$m phút'),
                        selected: _selectedClockMin == m,
                        onSelected: _busy
                            ? null
                            : (v) {
                                if (v) setState(() => _selectedClockMin = m);
                              },
                      ),
                  ],
                ),
                AppSpacing.vGapBase,
                if (!widget.initialCasual) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: Text('Tìm trận tự động ($_selectedClockMin phút)'),
                    onPressed: _busy ? null : _findMatch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentGold,
                      foregroundColor: AppColors.inkBlack,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  AppSpacing.vGapBase,
                  const Text(
                    '— hoặc tạo / vào phòng riêng —',
                    textAlign: TextAlign.center,
                  ),
                ],
                AppSpacing.vGapBase,
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(
                    widget.initialCasual
                        ? 'Tạo phòng casual $_selectedClockMin phút'
                        : 'Tạo phòng riêng $_selectedClockMin phút',
                  ),
                  onPressed: _busy ? null : _createRoom,
                ),
                AppSpacing.vGapBase,
                const Text(
                  '— vào phòng có sẵn theo ID —',
                  textAlign: TextAlign.center,
                ),
                AppSpacing.vGapBase,
                TextField(
                  controller: _roomIdCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Room ID',
                    helperText: '6 ký tự',
                    prefixIcon: Icon(Icons.meeting_room_outlined),
                  ),
                ),
                AppSpacing.vGapSm,
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Vào'),
                        onPressed: _busy ? null : _joinRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.woodDark,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    AppSpacing.hGapSm,
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Xem'),
                        onPressed: _busy ? null : _spectateRoom,
                      ),
                    ),
                  ],
                ),
                AppSpacing.vGapBase,
                _ActiveRoomsPanel(
                  rooms: state.activeRooms,
                  updatedAtMs: state.activeRoomsUpdatedAtMs,
                  onRefresh: _busy ? null : _refreshActiveRooms,
                  onSpectate: _busy ? null : _spectateRoomId,
                ),
              ],
              if (state.phase == OnlineMatchPhase.matching) ...[
                AppSpacing.vGapLg,
                const Center(child: CircularProgressIndicator()),
                AppSpacing.vGapBase,
                Center(
                  child: Text('Đang tìm đối thủ…', style: AppTextStyles.bodyMd),
                ),
                AppSpacing.vGapBase,
                Center(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Hủy tìm trận'),
                    onPressed: _busy ? null : _cancelMatching,
                  ),
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
                if (state.isCasual) ...[
                  AppSpacing.vGapSm,
                  Center(
                    child: Text(
                      'Cờ giao hữu — không tính ELO',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.tealSuccess,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                AppSpacing.vGapBase,
                ElevatedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Chia sẻ phòng (link / QR)'),
                  onPressed: () => ShareRoomSheet.show(
                    context,
                    roomId: state.roomId,
                    spectate: false,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGold,
                    foregroundColor: AppColors.inkBlack,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                  style: AppTextStyles.captionSm.copyWith(
                    color: Colors.redAccent,
                  ),
                ),
              ],
              AppSpacing.vGapBase,
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

class _ActiveRoomsPanel extends StatelessWidget {
  const _ActiveRoomsPanel({
    required this.rooms,
    required this.updatedAtMs,
    required this.onRefresh,
    required this.onSpectate,
  });

  final List<OnlineActiveRoom> rooms;
  final int? updatedAtMs;
  final VoidCallback? onRefresh;
  final ValueChanged<String>? onSpectate;

  String _updatedLabel() {
    final ts = updatedAtMs;
    if (ts == null) return 'Chưa tải';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return 'Cập nhật $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 18,
              color: AppColors.accentGold,
            ),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                'Ván đang diễn ra',
                style: AppTextStyles.headingMd.copyWith(
                  color: AppColors.accentGold,
                ),
              ),
            ),
            Text(
              _updatedLabel(),
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: 'Làm mới',
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
            ),
          ],
        ),
        if (rooms.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Text(
              'Chưa có ván đang chơi',
              style: AppTextStyles.captionSm,
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rooms.length,
            separatorBuilder: (context, _) => AppSpacing.vGapSm,
            itemBuilder: (context, index) {
              final room = rooms[index];
              return _ActiveRoomTile(room: room, onSpectate: onSpectate);
            },
          ),
      ],
    );
  }
}

class _ActiveRoomTile extends StatelessWidget {
  const _ActiveRoomTile({required this.room, required this.onSpectate});

  final OnlineActiveRoom room;
  final ValueChanged<String>? onSpectate;

  String _shortUid(String? uid) {
    if (uid == null || uid.isEmpty) return '—';
    return uid.length > 8 ? uid.substring(0, 8) : uid;
  }

  String _formatClock(int? ms) {
    if (ms == null) return '--:--';
    if (ms <= 0) return '00:00';
    final s = (ms / 1000).floor();
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _elapsedLabel(int? startedAtMs) {
    if (startedAtMs == null) return '—';
    final elapsed = DateTime.now().millisecondsSinceEpoch - startedAtMs;
    if (elapsed <= 0) return '0p';
    final minutes = elapsed ~/ 60000;
    if (minutes < 60) return '${minutes}p';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return '${hours}h${rest.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final turnLabel = room.currentTurn == PieceColor.red
        ? 'Đỏ'
        : room.currentTurn == PieceColor.black
        ? 'Đen'
        : '—';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  room.roomId,
                  style: AppTextStyles.monoTimer.copyWith(
                    color: AppColors.accentGold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Chia sẻ link xem',
                icon: const Icon(Icons.share, size: 18),
                onPressed: () => ShareRoomSheet.show(
                  context,
                  roomId: room.roomId,
                  spectate: true,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Xem'),
                onPressed: onSpectate == null
                    ? null
                    : () => onSpectate!(room.roomId),
              ),
            ],
          ),
          AppSpacing.vGapXs,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _RoomMeta(
                icon: Icons.circle,
                color: AppColors.vermilionRed,
                label: 'Đỏ ${_shortUid(room.redUid)}',
              ),
              _RoomMeta(
                icon: Icons.circle,
                color: AppColors.inkBlack,
                label: 'Đen ${_shortUid(room.blackUid)}',
              ),
              _RoomMeta(
                icon: Icons.swap_horiz,
                color: AppColors.accentGold,
                label: 'Lượt $turnLabel',
              ),
              _RoomMeta(
                icon: Icons.sports_score_outlined,
                color: AppColors.onSurfaceVariant,
                label: '${room.moveCount} nước',
              ),
              _RoomMeta(
                icon: Icons.visibility_outlined,
                color: AppColors.onSurfaceVariant,
                label: '${room.spectatorCount} xem',
              ),
              _RoomMeta(
                icon: Icons.schedule,
                color: AppColors.onSurfaceVariant,
                label: _elapsedLabel(room.startedAtMs),
              ),
              _RoomMeta(
                icon: room.mode == 'casual'
                    ? Icons.group_add_outlined
                    : Icons.military_tech_outlined,
                color: room.mode == 'casual'
                    ? AppColors.tealSuccess
                    : AppColors.accentGold,
                label: room.mode == 'casual' ? 'Casual' : 'Ranked',
              ),
            ],
          ),
          AppSpacing.vGapXs,
          Text(
            'Đỏ ${_formatClock(room.redClockMs)}  ·  Đen ${_formatClock(room.blackClockMs)}',
            style: AppTextStyles.monoSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomMeta extends StatelessWidget {
  const _RoomMeta({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.captionSm),
      ],
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
      OnlineMatchPhase.idle => (
        'Chưa kết nối',
        AppColors.parchmentTan,
        Icons.cloud_off,
      ),
      OnlineMatchPhase.connecting => (
        'Đang kết nối…',
        AppColors.parchmentTan,
        Icons.sync,
      ),
      OnlineMatchPhase.authed => (
        'Đã đăng nhập, sẵn sàng',
        AppColors.tealSuccess,
        Icons.check_circle,
      ),
      OnlineMatchPhase.matching => (
        'Đang tìm đối thủ…',
        AppColors.accentGold,
        Icons.search,
      ),
      OnlineMatchPhase.waitingForPeer => (
        'Phòng ${roomId ?? "?"} — chờ đối thủ',
        AppColors.accentGold,
        Icons.hourglass_top,
      ),
      OnlineMatchPhase.playing => (
        'Đang đánh',
        AppColors.tealSuccess,
        Icons.sports_esports,
      ),
      OnlineMatchPhase.spectating => (
        'Đang xem phòng ${roomId ?? "?"}',
        AppColors.tealSuccess,
        Icons.visibility,
      ),
      OnlineMatchPhase.peerDisconnected => (
        'Đối thủ mất kết nối — chờ reconnect…',
        AppColors.accentGold,
        Icons.wifi_off,
      ),
      OnlineMatchPhase.reconnecting => (
        'Đang reconnect vào ván cũ…',
        AppColors.accentGold,
        Icons.refresh,
      ),
      OnlineMatchPhase.ended => (
        'Ván kết thúc',
        AppColors.parchmentTan,
        Icons.flag,
      ),
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
            child: Text(
              label,
              style: AppTextStyles.bodyMd.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
