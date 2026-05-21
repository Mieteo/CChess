/// App-wide constants that don't belong to a single feature.
class AppConstants {
  AppConstants._();

  static const String appName = 'CChess';
  static const String appNameVi = 'Kỳ Vương Việt';
  static const String appVersion = '1.0.0';

  // Routes — keep names in one place so we can refactor safely.
  static const String routeSplash = '/splash';
  static const String routeLogin = '/login';
  static const String routeOnboarding = '/onboarding';
  static const String routeHome = '/';
  static const String routeLearning = '/learning';
  static const String routeCompete = '/compete';
  static const String routeCommunity = '/community';
  static const String routeProfile = '/profile';

  static const String routeGame = '/game';
  static const String routeMatchmaking = '/matchmaking';
  static const String routeBotSelect = '/bot-select';
  static const String routePuzzle = '/puzzle';
  static const String routeSettings = '/settings';
  static const String routeShop = '/shop';
  static const String routeAchievements = '/achievements';
  static const String routeHistory = '/history';
  static const String routeDailyQuests = '/daily-quests';
  static const String routeReplay = '/replay';
  static const String routeOpenings = '/openings';
  static const String routeCloudTest = '/cloud-test';
  static const String routeBackendTest = '/backend-test';

  // Storage keys.
  static const String boxSettings = 'cchess_settings';
  static const String boxGameHistory = 'cchess_game_history';
  static const String boxPuzzleProgress = 'cchess_puzzle_progress';

  // Hint usage caps.
  static const int dailyHintLimitFree = 3;
  static const int dailyHintLimitVip = 999;
}
