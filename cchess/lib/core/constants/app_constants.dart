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
  static const String routeCommunityFriends = '/community/friends';
  static const String routeCommunityLeaderboard = '/community/leaderboard';
  static const String routeCommunityClubs = '/community/clubs';
  static const String routeCommunityTournaments = '/community/tournaments';
  static const String routeProfile = '/profile';

  static const String routeGame = '/game';
  static const String routeMatchmaking = '/matchmaking';
  static const String routeBotSelect = '/bot-select';
  static const String routePuzzle = '/puzzle';
  // Endgame (tàn cục) progress dashboard. Distinct path so it doesn't collide
  // with the `/puzzle/:id` detail route.
  static const String routeEndgameStats = '/puzzle-stats';
  static const String routeBeginnerLessons = '/beginner-lessons';
  static const String routeSettings = '/settings';
  // Khám Phá (S16): hub → Thương Thành (shop) + Balo (inventory).
  static const String routeExplore = '/explore';
  static const String routeShop = '/shop';
  static const String routeInventory = '/inventory';
  static const String routeAchievements = '/achievements';
  static const String routeHistory = '/history';
  static const String routeDailyQuests = '/daily-quests';
  static const String routeReplay = '/replay';
  static const String routeAiCoach = '/ai-coach';
  static const String routeOpenings = '/openings';
  static const String routeCloudTest = '/cloud-test';
  static const String routeBackendTest = '/backend-test';
  static const String routeOnlineLobby = '/online-lobby';
  static const String routeOnlineGame = '/online-game';

  // Development-only route — only reachable when built with
  // `--dart-define=CALIBRATION=true` (see CalibrationScreen).
  static const String routeCalibration = '/calibration';

  // Storage keys.
  static const String boxSettings = 'cchess_settings';
  static const String boxGameHistory = 'cchess_game_history';
  static const String boxPuzzleProgress = 'cchess_puzzle_progress';
  // Offline cache of remote puzzles (B4 — Kho Tàn Cục). Lets the list/daily
  // screens fall back to the last-fetched server catalog when offline.
  static const String boxPuzzleCache = 'cchess_puzzle_cache';
  // Offline cache of the economy (S16 — Khám Phá): last-fetched shop catalog,
  // wallet, inventory and equipped loadout, so the shop renders and the equipped
  // board theme keeps applying when offline.
  static const String boxShop = 'cchess_shop';
  // Offline cache of clubs (S14 C3 — Kỳ Xã): last-fetched club list + the
  // caller's own memberships, so Cộng Đồng → Kỳ Xã still renders offline.
  static const String boxClubs = 'cchess_clubs';
  // Offline cache of tournaments (S14 C4 — Giải Đấu): last-fetched list, so
  // Cộng Đồng → Giải Đấu still renders offline.
  static const String boxTournaments = 'cchess_tournaments';

  // Hint usage caps.
  static const int dailyHintLimitFree = 3;
  static const int dailyHintLimitVip = 999;

  // Backend WebSocket endpoint.
  // - Mặc định = LAN dev (ws://192.168.1.6:8080)
  // - Override khi build release / prod bằng dart-define:
  //     flutter build apk --release \
  //       --dart-define=CCHESS_BACKEND_URL=wss://cchess-backend-XXXX.onrender.com
  //   (lưu ý: WSS không phải WS — Render serve HTTPS)
  /// True when the app was built with `--dart-define=CALIBRATION=true`.
  /// Gates the bot ELO calibration screen in settings + the /calibration route.
  static const bool calibrationEnabled = bool.fromEnvironment('CALIBRATION');

  static const String defaultBackendWsUrl = String.fromEnvironment(
    'CCHESS_BACKEND_URL',
    defaultValue: 'wss://cchess-backend.onrender.com',
  );

  // HTTP origin of the same cchess-backend that serves the WebSocket above.
  // The puzzle library REST API (B4) is mounted on this host at /puzzles.
  // Override per environment with:
  //   --dart-define=CCHESS_BACKEND_HTTP_URL=https://cchess-backend-XXXX.onrender.com
  static const String defaultBackendHttpUrl = String.fromEnvironment(
    'CCHESS_BACKEND_HTTP_URL',
    defaultValue: 'https://cchess-backend.onrender.com',
  );

  // Standalone HTTP engine service for online Pikafish analysis.
  // Override per environment:
  //   --dart-define=CCHESS_ENGINE_URL=https://cchess-engine-XXXX.onrender.com
  static const String defaultEngineHttpUrl = String.fromEnvironment(
    'CCHESS_ENGINE_URL',
    defaultValue: 'https://cchess-engine.onrender.com',
  );

  // A6 Spectate share link.
  // Base HTTPS origin for shareable room links (QR + invite text). The backend
  // serves a small landing page at `<base>/r/<roomId>` so the link opens
  // meaningfully in a browser; opening it inside the app deep-links straight to
  // spectate/join. Override per environment with dart-define if needed.
  static const String shareLinkBase = String.fromEnvironment(
    'CCHESS_SHARE_BASE',
    defaultValue: 'https://cchess-backend.onrender.com',
  );
}
