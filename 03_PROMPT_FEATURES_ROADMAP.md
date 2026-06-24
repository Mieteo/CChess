# ⚙️ PROMPT — TRIỂN KHAI TÍNH NĂNG THEO LỘ TRÌNH
# Game Cờ Tướng Việt Nam — CChess
# Dành cho: AI code assistant (GitHub Copilot, Cursor, Claude)
# File: 03_PROMPT_FEATURES_ROADMAP.md

> **Trạng thái triển khai**: doc này là **lộ trình prompt**, không phải status tracker. Để biết Sprint nào đã làm xong và còn gì, đọc [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md) (cập nhật sống). Tóm tắt 2026-05-21:
> - PROMPT 01-06 (Phase 1 MVP): ✅ Done (Sprint 1-7 + 8a + 8b + 9 + 10 + 11 + một phần PROMPT 04 online)
> - PROMPT 04 WebSocket: 🟡 Step 1+2 server xong, Step 3 chưa test (xem [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md))
> - PROMPT 07+: ⬜ Chưa bắt đầu

---

## HƯỚNG DẪN CHUNG CHO AI

```
Đây là dự án Flutter app cờ tướng Việt Nam "CChess".
Tech stack:
- Flutter 3.x (Dart)
- State management: Riverpod (flutter_riverpod)
- Navigation: GoRouter
- Backend: Firebase (Auth, Firestore, Realtime Database, Cloud Functions, Storage)
- Real-time game: WebSocket (dart:io WebSocket hoặc socket_io_client)
- Chess engine: Pikafish (engine cờ tướng riêng, phái sinh Stockfish — **KHÔNG phải** Fairy-Stockfish) — chạy **server-side** (xem [11_KE_HOACH_TICH_HOP_ENGINE.md](11_KE_HOACH_TICH_HOP_ENGINE.md)); bot offline dùng minimax Dart on-device
- Local DB: Hive
- HTTP: Dio + Retrofit

Cấu trúc thư mục (Clean Architecture):
lib/
├── core/           (constants, errors, utils)
├── data/           (models, datasources, repositories impl)
├── domain/         (entities, repositories abstract, usecases)
├── presentation/   (screens, widgets, providers)
├── theme/          (colors, text styles, theme)
└── main.dart

Khi implement: luôn viết theo pattern Repository + UseCase + Provider.
Luôn handle loading state, error state, empty state.
Tất cả String user-facing để trong const hoặc l10n.
```

---

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GIAI ĐOẠN 1 — MVP (Tháng 1–3)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## PHASE 1 — PROMPT 01: Cấu trúc dự án & Setup

```
Khởi tạo dự án Flutter CChess với cấu trúc sau:

1. Tạo project: flutter create cchess --org com.cchess.vn

2. pubspec.yaml — thêm dependencies:
   flutter_riverpod: ^2.x
   go_router: ^13.x
   firebase_core: ^2.x
   firebase_auth: ^4.x
   cloud_firestore: ^4.x
   firebase_database: ^10.x
   socket_io_client: ^2.x
   hive_flutter: ^1.x
   dio: ^5.x
   cached_network_image: ^3.x
   lottie: ^3.x
   google_fonts: ^6.x
   freezed_annotation: ^2.x
   json_annotation: ^4.x
   equatable: ^2.x
   dartz: ^0.10.x  (Either type)
   get_it: ^7.x    (Service locator)
   logger: ^2.x

3. dev_dependencies:
   build_runner
   freezed
   json_serializable
   hive_generator
   flutter_gen_runner

4. Tạo toàn bộ cấu trúc thư mục như mô tả ở trên.

5. Tạo file core/constants/:
   - app_constants.dart (API URLs, game constants)
   - elo_constants.dart (ELO tiers, K-factors)
   - piece_constants.dart (tên quân, ký hiệu Hán, movement rules)

6. Tạo Firebase project, download google-services.json (Android) + GoogleService-Info.plist (iOS)

7. Setup main.dart với ProviderScope + Firebase init + GoRouter

Output: Toàn bộ project scaffold ready to run.
```

---

## PHASE 1 — PROMPT 02: Chess Engine (Pikafish Integration)

> ⚠️ **Cập nhật 2026-06-07:** hướng tích hợp đã đổi từ **FFI on-device** sang **lai: minimax Dart offline + Pikafish server-side** (lý do GPL-3.0 + iOS App Store xung khắc GPL). Phần mô tả FFI bên dưới giữ lại làm lịch sử; kế hoạch hiện hành xem [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md).

```
Tích hợp chess engine Xiangqi vào Flutter:

1. CHESS LOGIC (pure Dart, không cần engine cho move validation):
   Tạo lib/core/chess_engine/xiangqi_game.dart:
   
   class XiangqiGame {
     List<List<Piece?>> board;  // 10x9 grid
     PieceColor currentTurn;
     GameStatus status;
     List<Move> moveHistory;
     
     // Methods:
     bool isValidMove(Position from, Position to);
     List<Position> getValidMoves(Position pos);
     void makeMove(Move move);
     void undoMove();
     bool isInCheck(PieceColor color);
     bool isCheckmate(PieceColor color);
     bool isStalemate(PieceColor color);
     bool isFacingGenerals(); // Chống tướng
     String toFEN();          // Serialize thành FEN string
     void loadFEN(String fen);
   }

2. PIECE MOVEMENT RULES (implement đầy đủ):
   - Tướng (将/帅): 1 ô theo chiều dọc/ngang, trong cung
   - Sĩ (士/仕): 1 ô chéo, trong cung
   - Tượng (象/相): 2 ô chéo, không qua sông, không bị cản chân
   - Mã (马/馬): L-shape (1+2), có thể bị chẹt chân
   - Xe (车/車): thẳng bất kỳ số ô, không có vật cản
   - Pháo (炮/砲): thẳng di chuyển, nhảy qua đúng 1 quân để ăn
   - Tốt (卒/兵): tiến thẳng trước khi qua sông, tiến/ngang sau qua sông

3. PIKAFISH AI INTEGRATION:
   Tạo lib/core/chess_engine/ai_engine.dart:
   - Download Pikafish binary cho Android ARM64 + iOS
   - Giao tiếp qua stdin/stdout UCI protocol
   - Wrapper class:
     class PikafishEngine {
       Future<void> init();
       Future<String> getBestMove(String fen, {int depth = 12, int timeMs = 1000});
       Future<PositionEvaluation> evaluate(String fen);
       void dispose();
     }
   - Chạy trong Isolate để không block UI

4. UNIT TESTS:
   - Test từng loại quân movement
   - Test check, checkmate detection
   - Test FEN serialization/deserialization

Output: lib/core/chess_engine/ hoàn chỉnh với unit tests.
```

---

## PHASE 1 — PROMPT 03: Authentication & User Management

```
Implement hệ thống authentication:

1. FIREBASE AUTH:
   Tạo lib/data/datasources/remote/auth_remote_datasource.dart
   - signInWithGoogle()
   - signInWithFacebook() 
   - signInWithApple()
   - signInAnonymously()   // Tạo account tạm thời khi cài app
   - linkAnonymousToSocial()
   - signOut()
   - getCurrentUser()
   - Stream<User?> authStateChanges()

2. USER MODEL (Firestore schema):
   Tạo lib/data/models/user_model.dart (Freezed):
   
   @freezed
   class UserModel with _$UserModel {
     const factory UserModel({
       required String uid,
       required String displayName,
       String? photoUrl,
       required String region,      // Vùng: "Hà Nội", "HCM", ...
       required int eloChess,       // ELO cờ tướng
       required int eloCup,         // ELO cờ úp
       required int totalGames,
       required int wins,
       required int losses,
       required int draws,
       required int creditScore,    // Điểm tín dụng (hành vi)
       required int coins,          // Đồng tiền game
       required int gems,           // Ngọc bội
       required String rank,        // "tap_su", "ky_si", ...
       required DateTime createdAt,
       required DateTime lastActiveAt,
       bool? isVip,
       DateTime? vipExpiresAt,
     });
   }

3. USER REPOSITORY:
   - createUser() — tạo document Firestore khi đăng ký
   - getUser(uid)
   - updateUser(uid, data)
   - updateElo(uid, newElo, gameType)
   - updateCurrency(uid, coins, gems)

4. AUTH PROVIDER (Riverpod):
   - authStateProvider: StreamProvider<User?>
   - currentUserProvider: FutureProvider<UserModel?>
   - authControllerProvider: StateNotifier với signIn, signOut methods

5. SCREENS:
   - LoginScreen: 3 nút (Google, Facebook, Chơi ngay - anonymous)
   - OnboardingScreen: chọn tên + khu vực (chỉ hiện lần đầu)

Output: lib/data/datasources/remote/auth_*, lib/domain/*, lib/presentation/auth/
```

---

## PHASE 1 — PROMPT 04: Online Multiplayer Game (WebSocket)

```
Implement online game với WebSocket:

1. GAME ROOM MODEL:
   @freezed
   class GameRoom with _$GameRoom {
     const factory GameRoom({
       required String roomId,
       required String player1Id,
       required String player2Id,
       required String boardFen,    // Trạng thái bàn cờ
       required List<String> moves, // Lịch sử nước đi (UCI format)
       required String currentTurn, // player1Id hoặc player2Id
       required GameStatus status,  // waiting, playing, finished
       required int player1TimeMs,
       required int player2TimeMs,
       DateTime? startedAt,
       String? winnerId,
       String? endReason,           // "checkmate", "timeout", "resign", "draw"
     });
   }

2. WEBSOCKET SERVICE:
   Tạo lib/data/datasources/remote/websocket_game_service.dart:
   
   class WebSocketGameService {
     // Connect đến game server
     Future<void> connect(String userId, String token);
     
     // Matchmaking
     Future<void> joinMatchmaking(int elo, String gameType);
     Future<void> cancelMatchmaking();
     
     // Game actions  
     Future<void> makeMove(String roomId, String move); // "e2e4" format
     Future<void> requestDraw(String roomId);
     Future<void> acceptDraw(String roomId);
     Future<void> resign(String roomId);
     
     // Streams
     Stream<MatchFoundEvent> get matchFound;
     Stream<MoveEvent> get moveReceived;
     Stream<GameEndEvent> get gameEnded;
     Stream<ChatEvent> get chatReceived;
     Future<void> sendChat(String roomId, String message);
     
     void disconnect();
   }

3. GAME SCREEN LOGIC:
   Tạo lib/presentation/game/providers/game_provider.dart:
   
   - GameState: Riverpod StateNotifier
     • board: XiangqiGame instance
     • roomId, playerColor, opponentInfo
     • myTimeMs, opponentTimeMs
     • gameStatus, lastMove, validMoves
     • chatMessages
   
   - Xử lý: onPieceTapped, onSquareTapped, onMoveReceived
   - Timer: countdown mỗi giây, auto-lose khi hết giờ
   - Reconnect logic: nếu mất kết nối, tự reconnect trong 30s

4. ELO CALCULATION (Cloud Function):
   Viết Firebase Cloud Function (Node.js):
   
   exports.calculateElo = functions.firestore
     .document('games/{gameId}')
     .onUpdate(async (change, context) => {
       // Khi game kết thúc:
       // 1. Tính ELO mới cho cả 2 người theo công thức Elo chuẩn
       // 2. Update Firestore user documents
       // 3. Cập nhật leaderboard
     });
   
   Công thức ELO:
   - K = 32 nếu < 30 ván, K = 24 nếu < 100 ván, K = 16 nếu >= 100 ván
   - Expected = 1 / (1 + 10^((opponentElo - myElo)/400))
   - NewElo = MyElo + K * (actual - expected)
   - actual: 1.0 thắng, 0.5 hòa, 0.0 thua

Output: lib/data/datasources/remote/websocket_game_service.dart,
        lib/presentation/game/providers/game_provider.dart,
        functions/src/calculate_elo.ts
```

---

## PHASE 1 — PROMPT 05: AI Bot Mode (Offline Play)

```
Implement chế độ chơi với AI (bot):

1. BOT DIFFICULTY LEVELS:
   enum BotDifficulty { veryEasy, easy, medium, hard, veryHard }
   
   Mapping depth:
   - veryEasy: depth 1, random move 50%
   - easy: depth 3
   - medium: depth 6
   - hard: depth 10
   - veryHard: depth 15 (Pikafish full power)

2. BOT GAME PROVIDER:
   - Tương tự GameProvider nhưng opponent là AI
   - Sau mỗi nước người dùng đi: gọi PikafishEngine.getBestMove()
   - Hiển thị "Đang suy nghĩ..." với loading dots animation
   - Add delay nhân tạo (500ms-2s) tùy độ khó để feel tự nhiên

3. BOT SELECTION SCREEN:
   - Grid 5 nút với icon mức độ khó
   - Mô tả: "Tập Sự — Phù hợp người mới", ...
   - ELO tương đương ước tính

Output: lib/core/chess_engine/bot_engine.dart, 
        lib/presentation/bot_game/
```

---

## PHASE 1 — PROMPT 06: Bài Tập Tàn Cục (Puzzle System)

```
Implement hệ thống bài tập cờ:

1. PUZZLE MODEL:
   @freezed
   class ChessPuzzle with _$ChessPuzzle {
     const factory ChessPuzzle({
       required String id,
       required String fen,           // Thế cờ ban đầu
       required List<String> solution, // Chuỗi nước đi đúng
       required int difficulty,        // 1-5
       required String theme,          // "checkmate_in_2", "fork", ...
       required String themeVi,        // Tên tiếng Việt
       int? ratingElo,                 // Độ khó ELO tương đương
     });
   }

2. PUZZLE REPOSITORY:
   - fetchDailyPuzzles(count: 10): lấy bài tập hôm nay
   - fetchPuzzlesByTheme(theme, difficulty)
   - markPuzzleSolved(puzzleId, userId)
   - getPuzzleProgress(userId): thống kê tỷ lệ đúng

3. PUZZLE SCREEN LOGIC:
   - Load FEN → hiển thị bàn cờ ở trạng thái puzzle
   - Người dùng đi nước → validate với solution[0]
   - Đúng: AI đi nước tiếp theo (solution[1]), chờ người tiếp (solution[2])
   - Sai: shake + đỏ + giảm 1 mạng thử
   - 3 lần sai: hiện solution
   - Hoàn thành: cộng XP + cập nhật streak

4. PUZZLE SEEDING:
   - Viết script Python convert Lichess Puzzle dataset (xiangqi format)
   - Upload 500 bài ban đầu lên Firestore
   - Script: tools/seed_puzzles.py

Output: lib/data/models/puzzle_model.dart,
        lib/presentation/puzzle/,
        tools/seed_puzzles.py
```

---

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GIAI ĐOẠN 2 — COMMUNITY (Tháng 4–6)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## PHASE 2 — PROMPT 07: Cờ Úp (Xiangqi Blind Variant)

```
Implement tính năng Cờ Úp:

1. RULES (khác với Cờ Tướng):
   - Setup bàn cờ: quân được xáo trộn ngẫu nhiên (trừ Tướng giữ đúng vị trí)
   - Tất cả quân đặt úp (face-down) ban đầu
   - Khi đến lượt: hoặc lật 1 quân (reveal) hoặc di chuyển quân đã lật
   - Khi lật: nếu là quân mình thì mình sở hữu, quân địch thì địch sở hữu
   - Sau khi lật đủ: đánh theo luật cờ tướng thường

2. XIANGQI_CUP_GAME class:
   - Extend XiangqiGame
   - board: mảng với trạng thái face-up/face-down
   - hiddenAssignment: mapping vị trí → loại quân (ẩn với cả 2 player)
   - randomizeHiddenPieces(): xáo trộn ban đầu
   - revealPiece(position): lật quân
   - getValidActions(): trả về cả reveal actions và move actions

3. UI modifications:
   - Quân úp: hiển thị mặt sau (pattern gỗ), không thấy chữ
   - Animation lật quân: flip 3D animation 300ms
   - Indicator "Có thể lật" khi hover quân úp

Output: lib/core/chess_engine/xiangqi_cup_game.dart
```

> **Thực tế đã implement (2026-06-25) — đính chính so với prompt trên:**
> - Reveal theo **nước đi**, không phải action "lật" riêng: quân úp đi theo **mặt phủ** (vai trò ô đang đứng), rồi **lật lộ danh tính thật ngay khi tới ô đích**. `getValidMoves` trả thẳng nước đi hợp lệ, không có "reveal action" tách biệt.
> - **Sĩ/Tượng đã mở KHÔNG theo luật cờ tướng thường** (khác dòng "đánh theo luật cờ tướng thường" ở trên): ngửa rồi thì **thoát giới hạn cung/sông** — Sĩ chéo 1 / Tượng chéo 2 đi **khắp bàn** (Tượng vẫn cản mắt), qua sông và áp sát/chiếu Tướng được. Quân **còn úp** trên ô Sĩ/Tượng vẫn bị giam theo mặt phủ.
> - `XiangqiCupGame implements ChessGameSession` (không extend `XiangqiGame`); phát hiện chiếu riêng `_cupInCheck` theo tầm Sĩ/Tượng ngửa. Khóa bằng test `xiangqi_cup_game_test.dart` (nhóm "revealed Sĩ/Tượng roam freely").

---

## PHASE 2 — PROMPT 08: Kỳ Phổ & Phục Bàn

```
Implement hệ thống lưu và phục bàn kỳ phổ:

1. GAME RECORD MODEL:
   @freezed
   class GameRecord with _$GameRecord {
     const factory GameRecord({
       required String id,
       required String player1Name,
       required String player2Name,
       required int player1Elo,
       required int player2Elo,
       required List<String> moves,  // List nước đi UCI format
       required String result,       // "1-0", "0-1", "0.5-0.5"
       required String endReason,
       required DateTime playedAt,
       required int durationSeconds,
       String? openingName,          // Tên khai cuộc
       bool? isFavorite,
     });
   }

2. GAME RECORD REPOSITORY:
   - saveGame(GameRecord): lưu lên Firestore
   - getMyGames(userId, {limit, offset}): phân trang
   - getFeaturedGames(): ván đấu hay (curator pick)
   - toggleFavorite(gameId)
   - *[VIP]*: unlimited storage; free: lưu tối đa 50 ván

3. REPLAY SCREEN:
   - Hiển thị bàn cờ ở vị trí nước 0 (ban đầu)
   - Controls: |< << Play/Pause >> >|
   - Slider timeline kéo đến nước bất kỳ
   - Move list panel: list tất cả nước đi, tap để nhảy đến
   - Tốc độ replay: 0.5x, 1x, 2x
   - Flip board button

4. AI SMART REPLAY (*[VIP]*):
   - Sau khi load game: chạy engine phân tích background
   - Đánh dấu màu từng nước:
     • Xanh lá: Nước tốt nhất
     • Vàng: Nước khá
     • Cam: Thiếu chính xác
     • Đỏ: Sai lầm lớn (blunder)
   - Tap vào nước để xem engine suggest nước tốt hơn
   - Báo cáo tổng kết: Accuracy %, số blunders

Output: lib/data/models/game_record_model.dart,
        lib/presentation/replay/
```

---

## PHASE 2 — PROMPT 09: Hệ Thống Bạn Bè & Social

```
Implement social features:

1. FRIEND SYSTEM:
   Firestore schema:
   - friendships/{uid}/friends/{friendUid}: {status: "pending"|"accepted", since}
   - Tìm bạn theo displayName (full-text search nhẹ: prefix match)
   
   Repository methods:
   - searchUsers(query): trả về List<UserModel>
   - sendFriendRequest(targetUid)
   - acceptFriendRequest(requesterUid)
   - getFriends(uid): List với online status real-time
   - getFriendRequests(uid)
   - removeFriend(targetUid)

2. REAL-TIME ONLINE STATUS:
   - Firebase Realtime Database: /status/{uid}: {online: true, lastSeen: timestamp}
   - Dùng onDisconnect() để tự set offline khi mất kết nối
   - Provider: friendsOnlineStatusProvider: Stream

3. FRIEND INVITE TO GAME:
   - Gửi notification mời đánh cờ qua Firebase Messaging
   - Deep link vào room khi chấp nhận

4. FRIEND SCREEN UI:
   - Tab "Danh Sách" + Tab "Tìm Bạn"
   - Mỗi friend item: avatar + tên + ELO + status (Online/Offline)
   - Online friends: nút "Xem ván" hoặc "Mời đấu"
   - Friend request list với Accept/Decline

Output: lib/data/repositories/friend_repository.dart,
        lib/presentation/friends/
```

---

## PHASE 2 — PROMPT 10: Bảng Xếp Hạng (Leaderboard)

```
Implement leaderboard system:

1. LEADERBOARD TYPES:
   - Toàn quốc (tất cả người chơi)
   - Theo tỉnh/thành phố
   - Bạn bè (chỉ trong danh sách bạn)
   - Riêng cho Cờ Tướng và Cờ Úp

2. FIRESTORE STRUCTURE:
   - leaderboard_chess/{uid}: {displayName, elo, rank, region, updatedAt}
   - Dùng Cloud Function update leaderboard sau mỗi game

3. QUERY OPTIMIZATION:
   - Dùng Firestore orderBy("elo", descending: true).limit(100)
   - Cache kết quả trong Hive, refresh mỗi 5 phút
   - Pagination với startAfter

4. MY RANK WIDGET:
   - Luôn hiển thị rank của bản thân + ELO
   - "Bạn đang ở vị trí #1,247 toàn quốc"
   - Animate khi rank thay đổi sau ván đấu

5. LEADERBOARD SCREEN:
   - Top 3: podium design (gold/silver/bronze)
   - Danh sách cuộn với số thứ tự
   - Highlight row của bản thân
   - Tap vào row: xem profile người dùng đó

Output: lib/data/repositories/leaderboard_repository.dart,
        lib/presentation/leaderboard/
```

---

## PHASE 2 — PROMPT 11: Huy Chương & Gamification

```
Implement achievement system:

1. ACHIEVEMENT MODEL:
   @freezed
   class Achievement with _$Achievement {
     const factory Achievement({
       required String id,
       required String nameVi,
       required String descVi,
       required String iconAsset,
       required AchievementCategory category,
       required AchievementTier tier,  // bronze, silver, gold
       required Map<String, dynamic> condition,  // {"wins": 10}
       bool? isUnlocked,
       DateTime? unlockedAt,
     });
   }

2. ACHIEVEMENT DEFINITIONS (hardcoded):
   [
     {id: "first_win", name: "Trận Thắng Đầu", condition: {wins: 1}},
     {id: "win_10", name: "Bách Chiến", condition: {wins: 10}},
     {id: "win_100", name: "Bách Thắng Tướng Quân", condition: {wins: 100}},
     {id: "win_streak_5", name: "Ngũ Liên Thắng", condition: {streak: 5}},
     {id: "win_streak_10", name: "Thập Liên Thắng", condition: {streak: 10}},
     {id: "puzzle_100", name: "Kỳ Thủ Học Giỏi", condition: {puzzles_solved: 100}},
     {id: "friends_10", name: "Quảng Giao Bạn Hữu", condition: {friends: 10}},
     {id: "elo_1600", name: "Kỳ Tướng", condition: {elo: 1600}},
     {id: "elo_2000", name: "Kỳ Vương", condition: {elo: 2000}},
     // ... thêm 20+ achievements
   ]

3. ACHIEVEMENT ENGINE:
   - Sau mỗi ván/sự kiện: check tất cả conditions
   - Khi unlock: save Firestore + trigger celebration animation
   - Cloud Function: recalculate achievements khi data thay đổi

4. UNLOCK CELEBRATION:
   - Toast nổi lên từ dưới: "[icon] Huy chương mới: Bách Thắng Tướng Quân!"
   - Tap vào toast: mở Achievement Detail screen

Output: lib/domain/achievements/, lib/presentation/achievements/
```

---

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GIAI ĐOẠN 3 — AI & MONETIZATION (Tháng 7–12)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## PHASE 3 — PROMPT 12: AI Coach (Gia Sư Cờ)

```
Implement AI coaching system:

1. ANALYSIS PIPELINE:
   Sau mỗi ván đấu hoàn thành (hoặc khi user yêu cầu):
   
   Step 1: Load game moves vào engine
   Step 2: Với mỗi nước đi, engine đánh giá:
     - centipawn score before/after move
     - best_move tại vị trí đó
     - classify: Brilliant/Good/Inaccuracy/Mistake/Blunder
   Step 3: Tổng hợp report:
     - Accuracy % = (sum good moves) / total moves * 100
     - Opening: match với ECO database → tên khai cuộc
     - Weak areas: khai cuộc/trung cuộc/tàn cuộc
   Step 4: Generate recommendations

2. COACH RECOMMENDATION ENGINE:
   Dựa trên lịch sử 20 ván gần nhất của người dùng:
   - Nếu blunder nhiều ở tàn cuộc → đề xuất bài tập tàn cuộc
   - Nếu khai cuộc yếu → đề xuất "Khai cuộc đại sư"
   - Nếu win rate thấp với Mã → đề xuất bài Mã pháo phối hợp
   
   Class AICoachRecommendation:
   - List<ChessPuzzle> recommendedPuzzles
   - List<String> weakPoints (["Tàn cuộc Xe-Tốt", "Phòng thủ Pháo đầu"])
   - String dailyTip
   - double overallAccuracy

3. AI COACH SCREEN:
   - Header: Avatar robot + "Gia Sư AI của bạn"
   - Accuracy score card: số lớn + vòng tròn tiến trình
   - "Điểm yếu cần cải thiện" section
   - "Bài tập được đề xuất hôm nay" — 5 puzzles
   - "Khai cuộc phổ biến của bạn" chart
   - *Free*: phân tích 3 ván/ngày
   - *VIP*: không giới hạn

Output: lib/core/chess_engine/game_analyzer.dart,
        lib/domain/usecases/analyze_game_usecase.dart,
        lib/presentation/ai_coach/
```

---

## PHASE 3 — PROMPT 13: Chụp Ảnh Nhận Diện Thế Cờ

```
Implement camera OCR để nhận dạng bàn cờ:

1. TECH APPROACH:
   - Option A (đơn giản): Dùng Google ML Kit (on-device) để detect hình tròn và text
   - Option B (chính xác hơn): Gửi ảnh lên Cloud Function, dùng Google Vision API
   
   Recommend: Option B cho accuracy cao hơn.

2. FLOW:
   1. Người dùng chụp ảnh bàn cờ thực
   2. App crop/detect vùng bàn cờ (OpenCV-like logic)
   3. Chia thành 90 ô (9x10 grid)
   4. OCR từng ô → nhận dạng ký tự Hán
   5. Map ký tự → loại quân + màu
   6. Validate thế cờ (có hợp lệ không)
   7. Load vào app → cho phép phân tích hoặc tiếp tục đánh

3. CAMERA SCREEN:
   - Camera live view với overlay grid 9x10 (hướng dẫn đặt bàn cờ)
   - Corner markers để căn chỉnh
   - Nút chụp → processing indicator → xem preview kết quả
   - Nếu nhận dạng sai: cho phép edit thủ công từng ô

4. MANUAL EDIT:
   - Tap vào ô trên preview: popup chọn loại quân
   - Confirm → load FEN vào puzzle/analysis mode

Output: lib/presentation/board_scanner/,
        functions/src/recognize_board.ts (Cloud Function)
```

---

## PHASE 3 — PROMPT 14: VIP & Monetization System

```
Implement monetization:

1. IN-APP PURCHASE (IAP):
   Dùng in_app_purchase package:
   - Product IDs:
     • vip_monthly: 29000đ (~$1.2)
     • vip_quarterly: 79000đ
     • vip_yearly: 249000đ
     • gem_pack_small: 50 gem = 20000đ
     • gem_pack_medium: 150 gem = 50000đ
     • gem_pack_large: 500 gem = 150000đ

2. VIP STATUS CHECK:
   - Lưu vipExpiresAt trong Firestore
   - isVipActiveProvider: FutureProvider<bool>
   - VIP Gate Widget: bọc quanh VIP features, hiện modal upgrade nếu không phải VIP

3. DAILY REWARD SYSTEM:
   - Điểm danh hàng ngày: Thứ 2-CN với phần thưởng tăng dần
   - Streak bonus: 7 ngày liên tiếp → phần thưởng đặc biệt
   - Xem quảng cáo để x2 phần thưởng (rewarded ads)
   - Sử dụng Google AdMob: rewarded + interstitial

4. CURRENCY TRANSACTIONS:
   - Tất cả giao dịch: ghi vào transaction_log/{uid}/{txId}
   - Cloud Function validate và execute (không tin client)
   - Atomic Firestore transaction: trừ gems + cộng item cùng lúc

5. VIP CENTER SCREEN:
   - Header: Card vàng với tên + avatar
   - VIP Benefits list với icon
   - "Kích hoạt VIP" button + giá
   - Lịch sử giao dịch

Output: lib/data/datasources/remote/iap_service.dart,
        lib/presentation/vip/,
        functions/src/process_purchase.ts
```

---

## PHASE 3 — PROMPT 15: Giải Đấu & Tournament System

```
Implement tournament system:

1. TOURNAMENT TYPES:
   - Daily Tournament: mỗi ngày 1 giải, top 3 nhận thưởng
   - Weekly Championship: cuối tuần, bracket 32/64 người
   - Club Tournament: CLB tự tổ chức

2. TOURNAMENT MODEL:
   @freezed
   class Tournament with _$Tournament {
     const factory Tournament({
       required String id,
       required String name,
       required TournamentType type,
       required TournamentFormat format,  // elimination, round_robin, swiss
       required DateTime startTime,
       required DateTime registrationDeadline,
       required int maxParticipants,
       required List<String> participantIds,
       required Map<String, dynamic> rewards,  // {1: {gems: 500}, 2: {gems: 200}}
       required TournamentStatus status,
       required int minElo,
       required int maxElo,
     });
   }

3. BRACKET SYSTEM:
   - Single elimination bracket
   - Auto-pair participants sau khi deadline đăng ký
   - Mỗi match: game bình thường với thời gian giới hạn
   - Tự động advance winner
   - Visualize bracket dạng cây nhị phân

4. TOURNAMENT SCREEN:
   - List giải đang mở đăng ký
   - Nút đăng ký + countdown
   - Bracket view (scrollable horizontal tree)
   - Live results / upcoming matches của mình

Output: lib/data/models/tournament_model.dart,
        lib/presentation/tournament/,
        functions/src/manage_tournament.ts
```

---

## PHASE 3 — PROMPT 16: Notification System

```
Implement push notification:

1. FIREBASE CLOUD MESSAGING setup:
   - Request permission on first launch
   - Save FCM token vào Firestore user document

2. NOTIFICATION TYPES:
   - game_invite: "Nguyễn A mời bạn đấu cờ"
   - friend_request: "Trần B muốn kết bạn"
   - daily_reminder: "Hôm nay bạn chưa chơi! Tàn cục hôm nay mới lắm"
   - tournament_start: "Giải đấu hôm nay bắt đầu trong 30 phút"
   - elo_change: "ELO của bạn đã thay đổi: 2278 → 2291 (+13)"
   - vip_expiring: "VIP của bạn hết hạn sau 3 ngày"

3. NOTIFICATION HANDLER:
   - Foreground: custom in-app banner (không dùng system notification)
   - Background/Terminated: system notification → deep link khi tap
   - NotificationService class xử lý routing

4. NOTIFICATION SETTINGS SCREEN:
   - Toggle từng loại notification
   - Quiet hours setting

Output: lib/core/services/notification_service.dart,
        lib/presentation/notifications/,
        functions/src/send_notifications.ts
```

---

## PHỤ LỤC — PROMPT BACKEND SCHEMA

```
Thiết kế Firestore schema đầy đủ cho CChess:

COLLECTIONS:
├── users/{uid}
│   ├── (UserModel fields)
│   └── subcollections:
│       ├── friends/{friendUid}
│       ├── achievements/{achievementId}
│       ├── game_records/{gameId} (reference)
│       └── notifications/{notifId}
│
├── games/{gameId}
│   ├── (GameRoom fields)
│   └── moves/{moveId}: {move, timestamp, playerId}
│
├── puzzles/{puzzleId}
│   └── (ChessPuzzle fields)
│
├── tournaments/{tournamentId}
│   ├── (Tournament fields)
│   └── matches/{matchId}
│
├── leaderboard_chess (collection group query)
│   └── {uid}: {elo, displayName, region}
│
├── clubs/{clubId}
│   ├── (Club fields)
│   └── members/{uid}
│
└── app_config/global
    └── {feature_flags, maintenance_mode, min_app_version}

REALTIME DATABASE:
├── status/{uid}: {online, lastSeen}
├── game_rooms/{roomId}: {fen, currentTurn, timers}  (real-time game state)
└── matchmaking_queue: {uid, elo, timestamp, gameType}

SECURITY RULES: viết rules đảm bảo:
- User chỉ đọc/write data của mình
- Game moves chỉ được validate bởi server
- Leaderboard chỉ đọc, không write từ client
```

---

## GHI CHÚ QUAN TRỌNG

1. **Server-side validation bắt buộc**: Tất cả nước đi game phải validate ở server. Client không được tin tưởng.
2. **Offline support**: Bài tập tàn cục và học cờ phải dùng được offline (cache Hive).
3. **Performance**: Chess board re-render tối ưu — chỉ repaint ô thay đổi.
4. **Anti-cheat**: Rate limiting, move timing analysis, engine detection.
5. **Analytics**: Firebase Analytics event cho mỗi action quan trọng.
6. **Crash reporting**: Firebase Crashlytics.
7. **Version management**: Remote Config cho feature flags + force update.
