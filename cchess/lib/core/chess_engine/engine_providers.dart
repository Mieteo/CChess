import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import 'engine_quota.dart';
import 'engine_router.dart';
import 'local_elephanteye_engine.dart';
import 'local_minimax_engine.dart';
import 'move_engine.dart';
import 'pikafish/pikafish_installer.dart';
import 'pikafish/pikafish_local_engine.dart';
import 'pikafish/pikafish_support.dart' as pikafish_support;
import 'remote_pikafish_engine.dart';

final localMinimaxEngineProvider = Provider<MoveEngine>((ref) {
  return LocalMinimaxEngine();
});

/// The on-device engine used as the router's local fallback. Prefers the native
/// ElephantEye search on Android and transparently degrades to pure-Dart
/// minimax elsewhere (or when the native library is unavailable).
final localEngineProvider = Provider<MoveEngine>((ref) {
  return LocalElephantEye();
});

final remotePikafishEngineProvider = Provider<RemotePikafishEngine>((ref) {
  final engine = RemotePikafishEngine(
    baseUri: Uri.parse(AppConstants.defaultEngineHttpUrl),
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.getIdToken();
    },
    timeout: const Duration(seconds: 3),
  );
  ref.onDispose(engine.close);
  return engine;
});

/// Offline Pikafish child-process engine, or null on platforms that can't
/// run one (web/iOS). Present ≠ usable: it only serves requests once the
/// NNUE is installed (see [pikafishInstallStatusProvider]).
final pikafishOfflineEngineProvider = Provider<PikafishLocalEngine?>((ref) {
  final engine = pikafish_support.createPikafishLocalEngine();
  if (engine != null) {
    ref.onDispose(() => engine.dispose());
  }
  return engine;
});

/// Manages the on-device NNUE download (Settings → "Engine Offline").
final pikafishInstallerProvider = Provider<PikafishInstaller>((ref) {
  return pikafish_support.createPikafishInstaller(
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      return user?.getIdToken();
    },
  );
});

/// Current install state; re-fetched whenever re-watched (autoDispose) so the
/// Settings screen updates right after a download/delete.
final pikafishInstallStatusProvider =
    FutureProvider.autoDispose<PikafishInstallStatus>((ref) {
  return ref.watch(pikafishInstallerProvider).status();
});

final engineRouterProvider = Provider<EngineRouter>((ref) {
  return EngineRouter(
    local: ref.watch(localEngineProvider),
    remote: ref.watch(remotePikafishEngineProvider),
    offline: ref.watch(pikafishOfflineEngineProvider),
    canUseRemote: () => true,
    canUseOffline: pikafish_support.pikafishOfflineReady,
  );
});

/// Today's free-tier engine allowance (hints/analyses left, VIP flag). Used to
/// show remaining quota and a VIP upsell. Auto-disposed so it re-fetches when
/// re-watched (e.g. after a hint is spent). Errors surface as AsyncError;
/// callers should treat that as "quota unknown" and not block the feature.
final engineQuotaProvider = FutureProvider.autoDispose<EngineQuotaStatus>((ref) {
  return ref.watch(remotePikafishEngineProvider).fetchQuota();
});
