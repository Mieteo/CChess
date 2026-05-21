import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/game_socket_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Debug-only screen to verify Step 2 (auth handshake) with cchess-backend.
class BackendTestScreen extends ConsumerStatefulWidget {
  const BackendTestScreen({super.key});

  @override
  ConsumerState<BackendTestScreen> createState() => _BackendTestScreenState();
}

class _BackendTestScreenState extends ConsumerState<BackendTestScreen> {
  /// Default endpoints to try (in order):
  /// - `10.0.2.2:8080` → Android emulator host loopback
  /// - `localhost:8080` → iOS simulator / desktop
  /// - For physical phone, replace với LAN IP của máy chạy backend
  final _urlCtrl = TextEditingController(text: 'ws://10.0.2.2:8080');

  final _log = <String>[];
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _busy = false;
  String? _error;

  GameSocketService get _svc => ref.read(gameSocketServiceProvider);

  @override
  void dispose() {
    _urlCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  void _appendLog(String line) {
    setState(() {
      _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)}  $line');
      if (_log.length > 30) _log.removeLast();
    });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _appendLog('▶ $label');
      await action();
    } catch (e) {
      setState(() => _error = e.toString());
      _appendLog('✗ $label: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run('connect ${_urlCtrl.text}', () async {
        if (_svc.isConnected) await _svc.disconnect();
        await _svc.connect(_urlCtrl.text.trim());
        _appendLog('✓ socket open');
        _sub?.cancel();
        _sub = _svc.messages.listen(
          (msg) => _appendLog('← $msg'),
          onError: (Object e) => _appendLog('✗ stream error: $e'),
          onDone: () => _appendLog('· socket closed'),
        );
      });

  Future<void> _authenticate() => _run('authenticate', () async {
        await _svc.authenticate();
        _appendLog('→ {type:auth, token:<idToken>}');
      });

  Future<void> _sendPing() => _run('send ping', () async {
        _svc.send({'type': 'ping', 'at': DateTime.now().toIso8601String()});
        _appendLog('→ {type:ping}');
      });

  Future<void> _disconnect() => _run('disconnect', () async {
        await _svc.disconnect();
      });

  @override
  Widget build(BuildContext context) {
    final connected = _svc.isConnected;
    final authed = _svc.authedUid != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Backend WS Test'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeSettings),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'WebSocket URL',
                  helperText:
                      'ws://10.0.2.2:8080 (Android emulator) hoặc ws://<host LAN IP>:8080 (máy thật)',
                  prefixIcon: Icon(Icons.link),
                ),
                enabled: !_busy && !connected,
              ),
              AppSpacing.vGapBase,
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.power_settings_new),
                      label: Text(connected ? 'Disconnect' : 'Connect'),
                      onPressed: _busy
                          ? null
                          : (connected ? _disconnect : _connect),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            connected ? Colors.red.shade700 : AppColors.woodDark,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.vpn_key),
                      label: const Text('Authenticate'),
                      onPressed: (!_busy && connected && !authed)
                          ? _authenticate
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.woodDark,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('Ping'),
                      onPressed:
                          (!_busy && connected && authed) ? _sendPing : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.woodDark,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.vGapBase,
              _StatusRow(
                connected: connected,
                authed: authed,
                uid: _svc.authedUid,
              ),
              if (_error != null) ...[
                AppSpacing.vGapBase,
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: AppTextStyles.captionSm),
                ),
              ],
              AppSpacing.vGapBase,
              Text('Log', style: AppTextStyles.headingMd),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: ListView.builder(
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Text(
                      _log[i],
                      style: AppTextStyles.captionSm.copyWith(
                        fontFamily: 'monospace',
                        color: AppColors.onSurface,
                      ),
                    ),
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

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.connected,
    required this.authed,
    required this.uid,
  });
  final bool connected;
  final bool authed;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.parchmentTan.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: connected ? Colors.greenAccent : Colors.white54,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text('connected', style: AppTextStyles.captionSm),
          const SizedBox(width: 16),
          Icon(
            authed ? Icons.check_circle : Icons.radio_button_unchecked,
            color: authed ? Colors.greenAccent : Colors.white54,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text('authed', style: AppTextStyles.captionSm),
          if (uid != null) ...[
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'uid: ${uid!.substring(0, 8)}…',
                style: AppTextStyles.captionSm,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
