import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import 'engine_quota.dart';
import 'engine_router.dart';
import 'local_minimax_engine.dart';
import 'move_engine.dart';
import 'remote_pikafish_engine.dart';

final localMinimaxEngineProvider = Provider<MoveEngine>((ref) {
  return LocalMinimaxEngine();
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

final engineRouterProvider = Provider<EngineRouter>((ref) {
  return EngineRouter(
    local: ref.watch(localMinimaxEngineProvider),
    remote: ref.watch(remotePikafishEngineProvider),
    canUseRemote: () => true,
  );
});

/// Today's free-tier engine allowance (hints/analyses left, VIP flag). Used to
/// show remaining quota and a VIP upsell. Auto-disposed so it re-fetches when
/// re-watched (e.g. after a hint is spent). Errors surface as AsyncError;
/// callers should treat that as "quota unknown" and not block the feature.
final engineQuotaProvider = FutureProvider.autoDispose<EngineQuotaStatus>((ref) {
  return ref.watch(remotePikafishEngineProvider).fetchQuota();
});
