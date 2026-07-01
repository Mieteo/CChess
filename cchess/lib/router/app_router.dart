import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/chess_engine/chess_engine.dart';
import '../core/constants/app_constants.dart';
import '../core/matchmaking/bot_matchmaker.dart';
import '../presentation/achievements/achievements_screen.dart';
import '../presentation/bot_game/bot_select_screen.dart';
import '../presentation/coach/ai_coach_screen.dart';
import '../presentation/cloud/backend_test_screen.dart';
import '../presentation/cloud/cloud_test_screen.dart';
import '../presentation/community/clubs_screen.dart';
import '../presentation/community/club_detail_screen.dart';
import '../presentation/community/tournament_detail_screen.dart';
import '../presentation/online/online_game_screen.dart';
import '../presentation/online/online_lobby_screen.dart';
import '../presentation/community/community_screen.dart';
import '../presentation/game/game_screen.dart';
import '../presentation/community/tournaments_screen.dart';
import '../presentation/friends/friends_screen.dart';
import '../presentation/history/game_history_screen.dart';
import '../presentation/home/home_screen.dart';
import '../presentation/learning/beginner_lesson_detail_screen.dart';
import '../presentation/learning/beginner_lesson_list_screen.dart';
import '../presentation/learning/learning_screen.dart';
import '../presentation/leaderboard/leaderboard_screen.dart';
import '../presentation/onboarding/onboarding_screen.dart';
import '../presentation/openings/opening_detail_screen.dart';
import '../presentation/openings/opening_list_screen.dart';
import '../presentation/play/compete_screen.dart';
import '../presentation/profile/edit_profile_screen.dart';
import '../presentation/profile/profile_screen.dart';
import '../presentation/puzzle/endgame_stats_screen.dart';
import '../presentation/puzzle/puzzle_list_screen.dart';
import '../presentation/puzzle/puzzle_screen.dart';
import '../presentation/quests/daily_quests_screen.dart';
import '../presentation/replay/game_replay_screen.dart';
import '../presentation/calibration/calibration_screen.dart';
import '../presentation/settings/settings_screen.dart';
import '../presentation/shop/explore_screen.dart';
import '../presentation/shop/inventory_screen.dart';
import '../presentation/shop/shop_screen.dart';
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
        path: AppConstants.routeOnboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppConstants.routeSettings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppConstants.routeCloudTest,
        builder: (context, state) => const CloudTestScreen(),
      ),
      GoRoute(
        path: AppConstants.routeBackendTest,
        builder: (context, state) => const BackendTestScreen(),
      ),
      if (AppConstants.calibrationEnabled)
        GoRoute(
          path: AppConstants.routeCalibration,
          builder: (context, state) => const CalibrationScreen(),
        ),
      GoRoute(
        path: AppConstants.routeOnlineLobby,
        builder: (context, state) {
          // A6 share link deep-link: `/online-lobby?spectate=ID` (watch) or
          // `?join=ID` (play). Lobby auto-connects then enters the room.
          final q = state.uri.queryParameters;
          final spectateId = q['spectate'];
          final joinId = q['join'];
          final casual = q['casual'] == '1' || q['mode'] == 'casual';
          final variant = q['variant'] == 'cup' ? 'cup' : 'standard';
          return OnlineLobbyScreen(
            deepLinkRoomId: spectateId ?? joinId,
            deepLinkSpectate: joinId == null,
            initialCasual: casual,
            variant: variant,
            // S14 C4 "Vào trận": `/online-lobby?tournamentId=X&matchId=Y`.
            tournamentId: q['tournamentId'],
            matchId: q['matchId'],
          );
        },
      ),
      GoRoute(
        path: AppConstants.routeOnlineGame,
        builder: (context, state) => const OnlineGameScreen(),
      ),
      GoRoute(
        path: '${AppConstants.routeProfile}/edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppConstants.routeAchievements,
        builder: (context, state) => const AchievementsScreen(),
      ),
      GoRoute(
        path: AppConstants.routeHistory,
        builder: (context, state) => const GameHistoryScreen(),
      ),
      GoRoute(
        path: AppConstants.routeDailyQuests,
        builder: (context, state) => const DailyQuestsScreen(),
      ),
      GoRoute(
        path: '${AppConstants.routeReplay}/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return GameReplayScreen(recordId: id);
        },
      ),
      GoRoute(
        // No id → coach the most recent finished game (Học Cờ "AI Tư Vấn").
        path: AppConstants.routeAiCoach,
        builder: (context, state) => const AiCoachScreen(),
      ),
      GoRoute(
        path: '${AppConstants.routeAiCoach}/:id',
        builder: (context, state) =>
            AiCoachScreen(recordId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppConstants.routeOpenings,
        builder: (context, state) => const OpeningListScreen(),
      ),
      GoRoute(
        path: '${AppConstants.routeOpenings}/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return OpeningDetailScreen(openingId: id);
        },
      ),
      GoRoute(
        path: AppConstants.routeBotSelect,
        builder: (context, state) => BotSelectScreen(
          variant:
              state.uri.queryParameters['variant'] == 'cup' ? 'cup' : 'standard',
        ),
      ),
      // Khám Phá (S16): hub → shop + inventory. Top-level routes (pushed over
      // the shell), like the puzzle screens.
      GoRoute(
        path: AppConstants.routeExplore,
        builder: (context, state) => const ExploreScreen(),
      ),
      GoRoute(
        path: AppConstants.routeShop,
        builder: (context, state) => const ShopScreen(),
      ),
      GoRoute(
        path: AppConstants.routeInventory,
        builder: (context, state) => const InventoryScreen(),
      ),
      GoRoute(
        path: AppConstants.routePuzzle,
        builder: (context, state) => const PuzzleListScreen(),
      ),
      GoRoute(
        path: AppConstants.routeEndgameStats,
        builder: (context, state) => const EndgameStatsScreen(),
      ),
      GoRoute(
        path: AppConstants.routeBeginnerLessons,
        builder: (context, state) => const BeginnerLessonListScreen(),
      ),
      GoRoute(
        path: '${AppConstants.routeBeginnerLessons}/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return BeginnerLessonDetailScreen(lessonId: id);
        },
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
          final q = state.uri.queryParameters;
          final mode = q['mode'] ?? 'local';
          final levelRaw = q['level'];
          final engineLevel = engineLevelFromString(levelRaw);
          final level =
              BotDifficultyX.fromString(levelRaw) ??
              (engineLevel == EngineLevel.grandmaster
                  ? BotDifficulty.veryHard
                  : null);
          // ELO-ladder standard play: `?mode=bot&botElo=1600&bracket=higher`.
          final botElo = int.tryParse(q['botElo'] ?? '');
          return GameScreen(
            mode: mode,
            botDifficulty: level,
            engineLevel: engineLevel,
            botElo: botElo,
            bracket: _bracketFromString(q['bracket']),
          );
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
            pageBuilder: (context, state) =>
                _fade(state, const LearningScreen()),
          ),
          GoRoute(
            path: AppConstants.routeCompete,
            pageBuilder: (context, state) =>
                _fade(state, const CompeteScreen()),
          ),
          GoRoute(
            path: AppConstants.routeCommunity,
            pageBuilder: (context, state) =>
                _fade(state, const CommunityScreen()),
            routes: [
              GoRoute(
                path: 'friends',
                pageBuilder: (context, state) =>
                    _fade(state, const FriendsScreen()),
              ),
              GoRoute(
                path: 'leaderboard',
                pageBuilder: (context, state) =>
                    _fade(state, const LeaderboardScreen()),
              ),
              GoRoute(
                path: 'clubs',
                pageBuilder: (context, state) =>
                    _fade(state, const ClubsScreen()),
                routes: [
                  GoRoute(
                    path: ':clubId',
                    pageBuilder: (context, state) => _fade(
                      state,
                      ClubDetailScreen(clubId: state.pathParameters['clubId']!),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'tournaments',
                pageBuilder: (context, state) =>
                    _fade(state, const TournamentsScreen()),
                routes: [
                  GoRoute(
                    path: ':tournamentId',
                    pageBuilder: (context, state) => _fade(
                      state,
                      TournamentDetailScreen(
                        tournamentId: state.pathParameters['tournamentId']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: AppConstants.routeProfile,
            pageBuilder: (context, state) =>
                _fade(state, const ProfileScreen()),
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

EloBracket? _bracketFromString(String? value) {
  if (value == null) return null;
  for (final b in EloBracket.values) {
    if (b.name == value) return b;
  }
  return null;
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
