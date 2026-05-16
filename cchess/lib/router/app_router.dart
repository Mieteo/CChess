import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/chess_engine/ai/bot_difficulty.dart';
import '../core/constants/app_constants.dart';
import '../presentation/bot_game/bot_select_screen.dart';
import '../presentation/community/community_screen.dart';
import '../presentation/game/game_screen.dart';
import '../presentation/home/home_screen.dart';
import '../presentation/learning/learning_screen.dart';
import '../presentation/play/compete_screen.dart';
import '../presentation/profile/profile_screen.dart';
import '../presentation/puzzle/puzzle_list_screen.dart';
import '../presentation/puzzle/puzzle_screen.dart';
import '../presentation/shell/app_shell.dart';
import '../presentation/splash/splash_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppConstants.routeSplash,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: AppConstants.routeSplash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppConstants.routeBotSelect,
        builder: (context, state) => const BotSelectScreen(),
      ),
      GoRoute(
        path: AppConstants.routePuzzle,
        builder: (context, state) => const PuzzleListScreen(),
      ),
      GoRoute(
        path: '${AppConstants.routePuzzle}/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return PuzzleScreen(puzzleId: id);
        },
      ),
      GoRoute(
        path: AppConstants.routeGame,
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'] ?? 'local';
          final levelRaw = state.uri.queryParameters['level'];
          final level = BotDifficultyX.fromString(levelRaw);
          return GameScreen(mode: mode, botDifficulty: level);
        },
      ),
      ShellRoute(
        builder: (context, state, child) {
          final location = state.matchedLocation;
          final index = _tabIndexForLocation(location);
          return AppShell(
            currentIndex: index,
            currentLocation: location,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: AppConstants.routeHome,
            pageBuilder: (context, state) => _fade(state, const HomeScreen()),
          ),
          GoRoute(
            path: AppConstants.routeLearning,
            pageBuilder: (context, state) => _fade(state, const LearningScreen()),
          ),
          GoRoute(
            path: AppConstants.routeCompete,
            pageBuilder: (context, state) => _fade(state, const CompeteScreen()),
          ),
          GoRoute(
            path: AppConstants.routeCommunity,
            pageBuilder: (context, state) => _fade(state, const CommunityScreen()),
          ),
          GoRoute(
            path: AppConstants.routeProfile,
            pageBuilder: (context, state) => _fade(state, const ProfileScreen()),
          ),
        ],
      ),
    ],
  );
});

CustomTransitionPage<T> _fade<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 0),
    child: child,
    transitionsBuilder: (_, _, _, c) => c,
  );
}

int _tabIndexForLocation(String location) {
  // Tabs are: home(/), learning(/learning), compete(/compete),
  // community(/community), profile(/profile).
  // Match by prefix so /game etc. don't break navigation.
  if (location.startsWith(AppConstants.routeLearning)) return 1;
  if (location.startsWith(AppConstants.routeCompete)) return 2;
  if (location.startsWith(AppConstants.routeCommunity)) return 3;
  if (location.startsWith(AppConstants.routeProfile)) return 4;
  return 0;
}
