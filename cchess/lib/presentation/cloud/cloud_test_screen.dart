import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class CloudTestScreen extends StatefulWidget {
  const CloudTestScreen({super.key});

  @override
  State<CloudTestScreen> createState() => _CloudTestScreenState();
}

class _CloudTestScreenState extends State<CloudTestScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _userDoc;
  String? _docStatus;
  List<_RuleTestResult>? _ruleTests;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = 'Auth: ${e.code} — ${e.message}');
    } on FirebaseException catch (e) {
      setState(() => _error = 'Firestore: ${e.code} — ${e.message}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInAnon() => _run(() async {
        await _auth.signInAnonymously();
      });

  Future<void> _signOut() => _run(() async {
        await _auth.signOut();
        setState(() {
          _userDoc = null;
          _docStatus = null;
          _ruleTests = null;
        });
        if (mounted) {
          context.go(AppConstants.routeSplash);
        }
      });

  Future<void> _readUserDoc(String uid) => _run(() async {
        final snap = await _db.collection('users').doc(uid).get();
        setState(() {
          if (snap.exists) {
            _userDoc = snap.data();
            _docStatus = 'exists';
          } else {
            _userDoc = null;
            _docStatus = 'missing';
          }
        });
      });

  Future<void> _runRuleTests(String uid) => _run(() async {
        final results = <_RuleTestResult>[];
        final ref = _db.collection('users').doc(uid);

        Future<_RuleTestResult> attempt({
          required String label,
          required Map<String, dynamic> update,
          required bool shouldAllow,
        }) async {
          try {
            await ref.update(update);
            return _RuleTestResult(
              label: label,
              pass: shouldAllow,
              detail: shouldAllow ? 'allowed (đúng)' : 'allowed (SAI — rules không chặn!)',
            );
          } on FirebaseException catch (e) {
            final denied = e.code == 'permission-denied';
            return _RuleTestResult(
              label: label,
              pass: !shouldAllow && denied,
              detail: denied
                  ? (shouldAllow ? 'denied (SAI — whitelist không hoạt động)' : 'denied (đúng)')
                  : 'lỗi khác: ${e.code}',
            );
          }
        }

        results.add(await attempt(
          label: 'Sửa eloChess = 9999',
          update: {'eloChess': 9999},
          shouldAllow: false,
        ));
        results.add(await attempt(
          label: 'Sửa coins = 999999',
          update: {'coins': 999999},
          shouldAllow: false,
        ));
        results.add(await attempt(
          label: 'Sửa displayName',
          update: {'displayName': 'Test ${DateTime.now().millisecondsSinceEpoch}'},
          shouldAllow: true,
        ));

        setState(() => _ruleTests = results);
        await _readUserDoc(uid);
      });

  Future<void> _createUserDoc(String uid) => _run(() async {
        await _db.collection('users').doc(uid).set({
          'displayName': 'Người chơi ẩn danh',
          'region': null,
          'avatarUrl': null,
          'eloChess': 1000,
          'eloCup': 1000,
          'totalGames': 0,
          'wins': 0,
          'losses': 0,
          'draws': 0,
          'coins': 100,
          'gems': 10,
          'creditScore': 100,
          'isVip': false,
          'vipExpiresAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'onboardingCompleted': false,
        });
        await _readUserDoc(uid);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Cloud (Test)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeSettings),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: _auth.authStateChanges(),
          builder: (context, snap) {
            final user = snap.data;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusCard(user: user),
                  AppSpacing.vGapLg,
                  if (user == null)
                    _ActionButton(
                      label: 'Đăng nhập ẩn danh',
                      icon: Icons.login,
                      onPressed: _busy ? null : _signInAnon,
                    )
                  else ...[
                    _ActionButton(
                      label: 'Đọc users/${user.uid.substring(0, 8)}…',
                      icon: Icons.cloud_download,
                      onPressed: _busy ? null : () => _readUserDoc(user.uid),
                    ),
                    AppSpacing.vGapBase,
                    if (_docStatus == 'missing')
                      _ActionButton(
                        label: 'Tạo profile cloud với default',
                        icon: Icons.add_circle_outline,
                        onPressed: _busy ? null : () => _createUserDoc(user.uid),
                      ),
                    AppSpacing.vGapBase,
                    if (_docStatus == 'exists')
                      _ActionButton(
                        label: 'Test rules chặn field nhạy cảm',
                        icon: Icons.security,
                        onPressed: _busy ? null : () => _runRuleTests(user.uid),
                      ),
                    AppSpacing.vGapBase,
                    _ActionButton(
                      label: 'Đăng xuất',
                      icon: Icons.logout,
                      onPressed: _busy ? null : _signOut,
                      destructive: true,
                    ),
                  ],
                  if (_busy) ...[
                    AppSpacing.vGapLg,
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_error != null) ...[
                    AppSpacing.vGapLg,
                    _ErrorCard(message: _error!),
                  ],
                  if (_ruleTests != null) ...[
                    AppSpacing.vGapLg,
                    _RuleTestCard(results: _ruleTests!),
                  ],
                  if (_docStatus != null) ...[
                    AppSpacing.vGapLg,
                    _DocCard(status: _docStatus!, data: _userDoc),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.user});
  final User? user;

  @override
  Widget build(BuildContext context) {
    final signedIn = user != null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchmentTan.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                signedIn ? Icons.check_circle : Icons.radio_button_unchecked,
                color: signedIn ? Colors.greenAccent : Colors.white54,
              ),
              const SizedBox(width: 8),
              Text(
                signedIn ? 'Đã đăng nhập' : 'Chưa đăng nhập',
                style: AppTextStyles.headingMd,
              ),
            ],
          ),
          if (signedIn) ...[
            const SizedBox(height: 8),
            Text('UID: ${user!.uid}', style: AppTextStyles.captionSm),
            Text(
              'Provider: ${user!.isAnonymous ? "anonymous" : user!.providerData.map((p) => p.providerId).join(", ")}',
              style: AppTextStyles.captionSm,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: destructive ? Colors.red.shade700 : AppColors.woodDark,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: AppTextStyles.headingMd,
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: AppTextStyles.captionSm)),
        ],
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.status, required this.data});
  final String status;
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    if (status == 'missing') {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: Colors.orange.shade900.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Document users/{uid} chưa tồn tại trên cloud.\nBấm "Tạo profile cloud" để khởi tạo với default.',
          style: AppTextStyles.captionSm,
        ),
      );
    }
    if (data == null) return const SizedBox.shrink();
    final entries = data!.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchmentTan.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('users/{uid} (${entries.length} fields)', style: AppTextStyles.headingMd),
          const SizedBox(height: 8),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${e.key}: ${_format(e.value)}',
                style: AppTextStyles.captionSm,
              ),
            ),
        ],
      ),
    );
  }

  String _format(dynamic v) {
    if (v == null) return 'null';
    if (v is Timestamp) return v.toDate().toIso8601String();
    return v.toString();
  }
}

class _RuleTestResult {
  _RuleTestResult({required this.label, required this.pass, required this.detail});
  final String label;
  final bool pass;
  final String detail;
}

class _RuleTestCard extends StatelessWidget {
  const _RuleTestCard({required this.results});
  final List<_RuleTestResult> results;

  @override
  Widget build(BuildContext context) {
    final allPass = results.every((r) => r.pass);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: (allPass ? Colors.green : Colors.red).shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: allPass ? Colors.greenAccent : Colors.redAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allPass ? Icons.verified_user : Icons.warning_amber,
                color: allPass ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Text(
                allPass ? 'Rules hoạt động đúng' : 'Có test FAIL — kiểm tra rules',
                style: AppTextStyles.headingMd,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final r in results)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${r.pass ? "✓" : "✗"}  ${r.label} → ${r.detail}',
                style: AppTextStyles.captionSm,
              ),
            ),
        ],
      ),
    );
  }
}
