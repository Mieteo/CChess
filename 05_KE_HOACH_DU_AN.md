# 📊 KẾ HOẠCH & TIẾN ĐỘ DỰ ÁN — CChess

> Tài liệu sống — cập nhật ngày **2026-06-20**: chốt đợt T16–T24. Backend `npm test` **86/86** (14 file), Flutter `flutter test` **233/233** (22 file); `backend-ci` đã chạy `lint` + `lab:check` + `npm test` + lab/load/fuzz, `flutter-ci` chạy analyze/test, thêm gate thủ công `post-deploy-smoke` và `engine-smoke`. Engine service `https://cchess-engine.onrender.com` đã smoke thật **8/8 PASS** gồm quota `429 quota-exceeded`. Việc còn lại chuyển sang hardening sản phẩm: quota/VIP bền vững, license NNUE, test tay cuối D4/M5/H4 và AI Coach B3.
> Mục đích: tổng kết **đã làm**, **chưa làm**, **đang chờ phụ thuộc** theo từng Sprint.
> Tham chiếu chéo: [`01_FEATURE_SPECIFICATION.md`](01_FEATURE_SPECIFICATION.md), [`02_PROMPT_UI_UX.md`](02_PROMPT_UI_UX.md), [`03_PROMPT_FEATURES_ROADMAP.md`](03_PROMPT_FEATURES_ROADMAP.md), [`07_HUONG_DAN_THIET_LAP_FIREBASE.md`](07_HUONG_DAN_THIET_LAP_FIREBASE.md), [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md), [`09_BACKEND_SERVER_HOAT_DONG.md`](09_BACKEND_SERVER_HOAT_DONG.md), [`10_KE_HOACH_TEST.md`](10_KE_HOACH_TEST.md) — **kế hoạch test các mục online chưa xác nhận**.

---

## 0. Quy ước trạng thái

| Ký hiệu | Ý nghĩa |
|---|---|
| ✅ | Hoàn thành & đã merge, có test xanh |
| 🟢 | Hoàn thành về mặt code/UI nhưng **chờ Sprint khác** để chạy thật (thường là chờ Firebase ở Sprint 8) |
| 🟡 | Đang làm dở / mới có khung |
| ⬜ | Chưa bắt đầu |
| 🔒 | Bị chặn bởi sprint tiền đề |

---

## 1. Bảng tổng tiến độ Sprint

| Sprint | Tên | Trạng thái | Ghi chú |
|---:|---|:---:|---|
| 1 | Foundation — theme, constants | ✅ | `lib/theme/`, `lib/core/constants/` |
| 2 | App Shell + Navigation 5-tab | ✅ | GoRouter, AppShell, BottomNav, Splash |
| 3 | Xiangqi Engine (Pure Dart) | ✅ | `lib/core/chess_engine/` + 41 unit test |
| 4 | ChessBoard UI (CustomPainter) | ✅ | `widgets/chess/`, `presentation/game/` |
| 5 | Bot AI (Minimax + Evaluator) | ✅ | 5 mức độ, `chess_engine/ai/` |
| 6 | Puzzle System (Tàn Cục) | ✅ | Seed 5+ bài, controller + UI + test |
| 7 | Settings, Profile, Hồ sơ chi tiết | ✅ | Settings + EditProfile + Onboarding |
| 8a | Firebase setup (config + Auth + Firestore) | ✅ | `cchess-dev`/`cchess-prod`, rules + indexes deployed, Anonymous + Google linking, splash auto-sync |
| 8b | Firestore sync + Cloud Functions code | ✅ | `users/`, `game_records/` sync local↔cloud; `createFirestoreUser` + `recordRankedGame` deployed (Blaze) |
| 8c | Backend WebSocket scaffold | ✅ | `cchess-backend/`: Step 1-8 đầy đủ + Xiangqi engine port + ELO + matchmaking. Deploy production https://cchess-backend.onrender.com (Render free tier) ✓ verified ranked E2E 2 phone qua Internet 2026-05-24 |
| 9 | Game History + Replay AI | 🟢 | Local Hive + push `game_records` lên cloud subcollection ✓; backend cũng ghi mirror record có ELO change cho ván ranked |
| 10 | Achievements + Daily Quests | 🟢 | Engine + UI xong, chờ Cloud Functions trigger server-side khi ván ranked đạt mốc |
| 11 | Opening Library (Khai cuộc Đại sư) | 🟢 | Seed cứng 5 khai cuộc, chờ CMS |
| 12 | Online Matchmaking + Spectate (A1, A5, A6) | 🟡 | **A1 Ranked done**; **A5 chat cơ bản + chip nhanh done**; **A6 Spectate/share link/QR done**; **Rematch done**; R/S đã đóng test tay. Đợt 2026-06-19/20 đã tự động hóa lõi C/D/M/G/ELO + widget online + smoke deploy. Còn lại: vòng nhìn-mắt cuối trên thiết bị thật cho D4 OS lifecycle, M5 Firebase thật, H4 chất lượng gợi ý, C2/D/G4 visual + nâng Render Starter khi có user thật |
| 13 | Cờ Úp + Cờ Casual (A3, A2) | 🟡 | **A3 Cờ Úp DONE end-to-end 2026-06-25**: local + backend online + Bot + **client online** (engine cup phía client `CupClientGame` chỉ thấy mặt phủ, áp `reveal`/`cup` snapshot, render mặt úp trong ván online; vào từ Đối Đầu → "Cờ Úp Online", ELO `eloCup` riêng). Còn: A2 Cờ Casual invite-by-link |
| 14 | Community (Bạn bè, Leaderboard, CLB) | 🔒 | Chờ S12 |
| 15 | AI Coach (B3) + AI Replay nâng cao (B5) | 🟡 | **Engine lai đã qua smoke thật 2026-06-20** — service Pikafish backend + abstraction Flutter + bot Đại Sư+ + replay analyze + **nút Gợi ý in-game** + attribution GPL + `cchess-engine` Render smoke 8/8 gồm quota. Còn: quota/VIP bền vững, đối chiếu FEN/UCI nhiều thế cố định, NNUE license, AI Coach B3 UI/diễn giải — xem [11](11_KE_HOACH_TICH_HOP_ENGINE.md) §10 |
| 16 | Khám Phá (Shop, Inventory, Mail, Event) | 🟡 | **Shop + Inventory + Explore UI + repo + backend routes/store + shop.test.ts DONE** (route `/shop` `/inventory`, Explore là hub); còn Mail/Event/Welfare/Crafting + nối ví/kinh tế thật |
| 17 | VIP Center + IAP | ⬜ | Phụ thuộc store account |
| 18 | OCR thế cờ (B7), học thuộc kỳ phổ (B8) | ⬜ | Giai đoạn 3 |

> **Trục thời gian cập nhật (cuối 5/2026):**
> - Sprint 8 hoàn thành 3 lát: 8a (Firebase Auth + Firestore + rules deployed), 8b (sync local↔cloud + Cloud Functions deployed Blaze), 8c (backend Node.js WebSocket production-deployed Render).
> - **Sprint 12 phase 1 A1 hoàn thành 2026-05-24**: matchmaking tự động + per-room clock (3/5/10/15/30 phút) + Xiangqi rule validation server-side + ELO Elo K=32 + reconnect grace 60s + Firestore persistence mirror records. Verified ván 10 phút giữa 2 thiết bị Android thật qua Internet (Render free tier endpoint). Group 1 polish 2026-05-31 đã nâng matchmaking lên ELO bucket/tolerance.
> - Sprint 9–11 đã unblock (cloud sync chạy). Sprint 12 group 1 polish đã xong 2026-05-31: ELO bucket matchmaking, rollback khi server reject move, profile auto-refresh sau game-ended. Sprint 12 phase 2 đã có A5 chat text, A6 Spectate theo room ID và danh sách ván đang diễn ra.
> - **2026-06-07 A6 share link/QR**: helper `room_share.dart` build/parse link (`/r/<ID>` spectate, `?mode=join`), `ShareRoomSheet` (QR + copy + native share), nút chia sẻ ở lobby/tile ván đang diễn ra/app bar ván, deep-link in-app `online-lobby?spectate|join=ID`, landing page backend `GET /r/:id`. Test `room_share_test.dart` 17/17.
> - **2026-06-07 (đợt 2) — đóng hết test tự động Sprint 12**: refactor `cchess-backend/src/server.ts` thành factory `createCChessServer({authenticate, persist})` (giữ nguyên hành vi production; entry point production được bọc trong guard `CCHESS_NO_LISTEN`). Thêm `server.test.ts` (integration WS thật, in-process, không cần Firebase): T3 rematch handshake (cả-2-mời → `game-start{rematch:true}` đổi màu / decline / not-finished), T7 reconnect snapshot trong grace, T8 chat broadcast + rate-limit + cap 120 ký tự + chặn sau `game-ended`. Backend `npm test` **17/17** (rooms 3 + match 8 + server 6).
> - **2026-06-07 (đợt 3) — Sprint 15 khởi động sớm (engine lai)**: dựng `cchess-backend/src/engine-service/` (UCI wrapper + pool + cache + quota + HTTP API), `Dockerfile.engine`, service `cchess-engine` trong `render.yaml`; phía Flutter thêm `MoveEngine`/`LocalMinimaxEngine`/`RemotePikafishEngine`/`EngineRouter` + bot **Đại Sư+** + replay analyze qua router. Chi tiết [11](11_KE_HOACH_TICH_HOP_ENGINE.md) §10.
> - **2026-06-11 — đợt code các phần không bị chặn**: (1) **nút Gợi ý in-game** (`EngineUseCase.hint`, remote → fallback minimax, marker xanh ngọc trên bàn, 6 unit test mới); (2) **attribution Pikafish GPL-3.0 + NNUE** trong Cài đặt → Giới thiệu; (3) **chip chat nhanh** trong chat sheet online (A5); (4) **hardening double-disconnect** (D5): `Room.disconnectGrace` map theo uid (2 người cùng rớt giữ 2 cửa sổ reconnect riêng), snapshot `reconnected` thêm `peerInGrace`, phòng tự dọn khi kết thúc không còn ai, grace override được qua env cho test — `server.disconnect.test.ts` 2 integration test mới. Backend **25/25**, Flutter **148/148**.
> - **2026-06-19/20 — đợt tự động hóa và smoke hạ tầng**: backend M/G/ELO, persistence idempotency, checkmate fixture G1, Flutter chat/reconnect/result widgets, `backend-ci` lab/load/fuzz, `post-deploy-smoke` opt-in ranked-write, `engine-smoke` HTTP cho `cchess-engine`, quota gate `engine:smoke:quota`. Backend **69/69**, Flutter **226/226**; engine product smoke trên Render **8/8 PASS** gồm `quota-exceeded`.

---

## 2. Chi tiết các Sprint đã hoàn thành

### ✅ Sprint 1 — Foundation
**Đã làm:**
- Theme thủy mặc Á Đông: [app_colors.dart](cchess/lib/theme/app_colors.dart), [app_spacing.dart](cchess/lib/theme/app_spacing.dart), [app_text_styles.dart](cchess/lib/theme/app_text_styles.dart), [app_theme.dart](cchess/lib/theme/app_theme.dart) (Material 3 dark, nâu gỗ + vàng đồng).
- Hằng số dự án: [app_constants.dart](cchess/lib/core/constants/app_constants.dart), [elo_constants.dart](cchess/lib/core/constants/elo_constants.dart) (7 cấp bậc: Tập Sự → Kỳ Thánh, K-factor), [piece_constants.dart](cchess/lib/core/constants/piece_constants.dart).

**Chưa làm:** —

---

### ✅ Sprint 2 — App Shell & Navigation
**Đã làm:**
- 5 tab: **Trang Chủ / Học Tập / Đối Đầu / Cộng Đồng / Hồ Sơ** (theo mockup, KHÔNG dùng tên trong spec gốc).
- [app_router.dart](cchess/lib/router/app_router.dart): GoRouter + ShellRoute + 18 route con.
- [app_shell.dart](cchess/lib/presentation/shell/app_shell.dart), [cchess_app_bar.dart](cchess/lib/presentation/shell/cchess_app_bar.dart), [cchess_bottom_nav.dart](cchess/lib/presentation/shell/cchess_bottom_nav.dart).
- [splash_screen.dart](cchess/lib/presentation/splash/splash_screen.dart): animated logo + chuyển hướng.

**Chưa làm:** chuyển tab có animation hấp dẫn hơn (hiện đang fade 0ms để tránh giật).

---

### ✅ Sprint 3 — Xiangqi Engine (Pure Dart)
**Đã làm:**
- Lõi: [board.dart](cchess/lib/core/chess_engine/board.dart), [piece.dart](cchess/lib/core/chess_engine/piece.dart), [position.dart](cchess/lib/core/chess_engine/position.dart), [move.dart](cchess/lib/core/chess_engine/move.dart).
- Luật đi đầy đủ 7 loại quân + chiếu, chiếu bí, chống tướng: [move_rules.dart](cchess/lib/core/chess_engine/move_rules.dart).
- Game state machine: [xiangqi_game.dart](cchess/lib/core/chess_engine/xiangqi_game.dart) (FEN, undo, status).
- Barrel export: [chess_engine.dart](cchess/lib/core/chess_engine/chess_engine.dart).
- **Test:** 41 unit test xanh ([board_test.dart](cchess/test/chess_engine/board_test.dart), [move_rules_test.dart](cchess/test/chess_engine/move_rules_test.dart), [xiangqi_game_test.dart](cchess/test/chess_engine/xiangqi_game_test.dart)).

**Quy ước đã chốt** (xem [memory/project_xiangqi_engine.md](.claude/projects/F--Flutter-Copilot-CChess-CChess/memory/project_xiangqi_engine.md)):
- Row 0 = Đen ở đỉnh, Row 9 = Đỏ ở đáy.
- Flying-general là **luật toàn cục**, KHÔNG phải pseudo-move.
- Stalemate = **thua** cho bên đi (đúng luật cờ tướng).

**Chưa làm:** repetition rule (4 nước lặp = thua bên chiếu liên tục), 60-move rule chính thức.

---

### ✅ Sprint 4 — ChessBoard UI
**Đã làm:**
- CustomPainter vẽ bàn cờ 9×10 + sông + cung: [board_painter.dart](cchess/lib/widgets/chess/board_painter.dart).
- Widget tương tác: [chess_board.dart](cchess/lib/widgets/chess/chess_board.dart), [chess_piece_widget.dart](cchess/lib/widgets/chess/chess_piece_widget.dart).
- Màn chơi local: [game_screen.dart](cchess/lib/presentation/game/game_screen.dart), [game_controller.dart](cchess/lib/presentation/game/game_controller.dart).
- Phụ kiện: [game_action_bar.dart](cchess/lib/presentation/game/widgets/game_action_bar.dart), [player_info_panel.dart](cchess/lib/presentation/game/widgets/player_info_panel.dart), [game_result_overlay.dart](cchess/lib/presentation/game/widgets/game_result_overlay.dart).
- Bộ widget chung 10 thành phần trong [widgets/common/](cchess/lib/widgets/common/) (Button, Card, Dialog, Avatar, RankBadge, ProgressBar, CurrencyDisplay, LoadingOverlay, SectionHeader, common barrel).
- Onboarding 4 trang: [onboarding_screen.dart](cchess/lib/presentation/onboarding/onboarding_screen.dart).
- **Test:** [game_controller_test.dart](cchess/test/game/game_controller_test.dart) (93 dòng).

**Chưa làm:** animation di chuyển quân (slide + fade), highlight nước cuối, hiệu ứng âm thanh.

---

### ✅ Sprint 5 — Bot AI (Minimax)
**Đã làm:**
- Đánh giá thế cờ: [evaluator.dart](cchess/lib/core/chess_engine/ai/evaluator.dart) (giá trị quân + bonus vị trí).
- Tìm kiếm: [minimax.dart](cchess/lib/core/chess_engine/ai/minimax.dart) (alpha-beta).
- 5 mức độ với randomness điều chỉnh: [bot_difficulty.dart](cchess/lib/core/chess_engine/ai/bot_difficulty.dart) (Tập Sự → Đại Sư).
- Wrapper bất đồng bộ: [bot_engine.dart](cchess/lib/core/chess_engine/ai/bot_engine.dart) (`minThinkTime` cho UX).
- Màn chọn bot: [bot_select_screen.dart](cchess/lib/presentation/bot_game/bot_select_screen.dart).
- **Test:** [evaluator_test.dart](cchess/test/chess_engine/ai/evaluator_test.dart), [minimax_test.dart](cchess/test/chess_engine/ai/minimax_test.dart).

**Chưa làm:** transposition table, opening book riêng cho bot, tích hợp Pikafish (server-side, đẩy sang Sprint 15 — xem [11_KE_HOACH_TICH_HOP_ENGINE.md](11_KE_HOACH_TICH_HOP_ENGINE.md)).

---

### ✅ Sprint 6 — Puzzle System (Tàn Cục)
**Đã làm:**
- Model: [chess_puzzle.dart](cchess/lib/data/models/chess_puzzle.dart).
- Seed dữ liệu cứng: [puzzle_seed.dart](cchess/lib/data/datasources/local/puzzle_seed.dart).
- Repository: [puzzle_repository.dart](cchess/lib/data/repositories/puzzle_repository.dart).
- UI: [puzzle_list_screen.dart](cchess/lib/presentation/puzzle/puzzle_list_screen.dart), [puzzle_screen.dart](cchess/lib/presentation/puzzle/puzzle_screen.dart), [puzzle_controller.dart](cchess/lib/presentation/puzzle/puzzle_controller.dart).
- **Test:** [puzzle_seed_test.dart](cchess/test/puzzle/puzzle_seed_test.dart), [puzzle_controller_test.dart](cchess/test/puzzle/puzzle_controller_test.dart).

**Chưa làm:** mục tiêu 10.000+ bài (spec B4) — hiện chỉ vài bài demo, cần content team + CMS (sau Sprint 8).

---

### ✅ Sprint 7 — Settings, Profile, Edit Profile
**Đã làm:**
- Settings đầy đủ: [settings_screen.dart](cchess/lib/presentation/settings/settings_screen.dart), [settings_controller.dart](cchess/lib/presentation/settings/settings_controller.dart), model [app_settings.dart](cchess/lib/data/models/app_settings.dart), repo [settings_repository.dart](cchess/lib/data/repositories/settings_repository.dart) (lưu local qua SharedPreferences/Hive).
- Profile: [profile_screen.dart](cchess/lib/presentation/profile/profile_screen.dart), [profile_controller.dart](cchess/lib/presentation/profile/profile_controller.dart), [edit_profile_screen.dart](cchess/lib/presentation/profile/edit_profile_screen.dart), model [user_profile.dart](cchess/lib/data/models/user_profile.dart), repo [profile_repository.dart](cchess/lib/data/repositories/profile_repository.dart).
- **Test:** [settings_profile_test.dart](cchess/test/data/settings_profile_test.dart).

**Chưa làm:** —

---

### ✅ Sprint 8a — Firebase setup (auth + Firestore)
**Đã làm:**
- Project Firebase: `cchess-dev` + `cchess-prod`, region `asia-southeast1` (Singapore).
- Package ID đồng bộ 5 platforms: `vn.cchess.app` (Android/iOS/macOS/Web/Windows).
- FlutterFire configure → [firebase_options.dart](cchess/lib/firebase_options.dart) + `google-services.json` + `GoogleService-Info.plist`.
- Auth: **Anonymous** bật, **Google Sign-In** bật + SHA-1 fingerprint thêm vào console.
- `Firebase.initializeApp` trong [main.dart](cchess/lib/main.dart).
- Account linking: [google_auth_service.dart](cchess/lib/data/services/google_auth_service.dart) (google_sign_in 7.x + Web serverClientId).
- UI: "Tài khoản" section trong Settings + account chip trong Profile header.

**Chưa làm:** Facebook/Apple sign-in (defer Sprint 17 cùng IAP).

---

### ✅ Sprint 8b — Firestore sync + Cloud Functions
**Đã làm:**
- Rules + indexes deployed cho `cchess-dev`: [firestore.rules](cchess/firestore.rules), [firestore.indexes.json](cchess/firestore.indexes.json).
- Sync local↔cloud: [user_remote_repository.dart](cchess/lib/data/repositories/user_remote_repository.dart), [cloud_sync_service.dart](cchess/lib/data/services/cloud_sync_service.dart) — splash auto sign-in + merge cloud whitelist vào local.
- ProfileController auto-push whitelist (`displayName`, `region`, `avatarUrl`, `onboardingCompleted`) lên cloud.
- Game history cũng sync: [game_record_remote_repository.dart](cchess/lib/data/repositories/game_record_remote_repository.dart) — push toàn bộ record khi save, update isFavorite riêng (rules-compliant).
- Cloud Functions deployed lên prod (`cchess-dev`, upgraded Blaze): [functions/src/index.ts](cchess/functions/src/index.ts) — `createFirestoreUser` (us-east1 v1 auth trigger) + `recordRankedGame` (asia-southeast1 v2 callable).
- Cloud Test screen debug (gated `kDebugMode`): [cloud_test_screen.dart](cchess/lib/presentation/cloud/cloud_test_screen.dart) — test rules + linking.

**Chưa làm:** retry queue cho writes khi offline (data có thể bị stale-rollback). Sprint 11 nếu cần.

---

### ✅ Sprint 8c — Backend WebSocket scaffold
**Đã làm:**
- Project mới: [`cchess-backend/`](cchess-backend/) — Node 20 + TypeScript + `ws` + `firebase-admin`.
- **Step 1** echo server: [server.ts](cchess-backend/src/server.ts) ✓ verified.
- **Step 2** auth handshake: [auth.ts](cchess-backend/src/auth.ts) — verify Firebase ID token, gắn `uid` vào socket, 10s timeout ✓ verified (Android phone qua LAN + Firebase Admin SDK).
- **Step 3** rooms: [rooms.ts](cchess-backend/src/rooms.ts) — create/join/leave/broadcast với 6-ký-tự roomId, auto-cleanup on disconnect ✓ verified E2E (Flutter phone + Chrome console cùng PC, cả 2 hướng broadcast + peer-left khi đóng tab).
- **Step 4** move transport: server.ts handler `move` → UCI regex `^[a-i][0-9][a-i][0-9]$` + room đủ 2 người + forward sang peer kèm `moveNumber` tăng dần ✓ verified E2E.
- **Step 5** move validation server-side: TypeScript Xiangqi engine port từ Dart, reject `illegal-move`, auto-finish checkmate/stalemate.
- **Step 6** clock + game lifecycle: [match.ts](cchess-backend/src/match.ts) — clock theo lựa chọn lobby, `game-start` khi đủ 2 người, turn validation theo socket reference, timeout/resign/disconnect. ✓ verified E2E.
- **Step 7** persistence + ELO: [persistence.ts](cchess-backend/src/persistence.ts) — Admin SDK ghi 2 record mirror, update `eloChess` + counters trong transaction.
- **Step 8** reconnect: grace 60s, `reconnect-room`, snapshot move/chat, peer-disconnect banner.
- **Deploy**: Render production endpoint `https://cchess-backend.onrender.com`; client dùng `wss://...` qua `CCHESS_BACKEND_URL`.
- Flutter client: [game_socket_service.dart](cchess/lib/data/services/game_socket_service.dart), [online_lobby_screen.dart](cchess/lib/presentation/online/online_lobby_screen.dart), [online_game_screen.dart](cchess/lib/presentation/online/online_game_screen.dart), [online_match_controller.dart](cchess/lib/presentation/online/online_match_controller.dart).

**Chưa làm:** server restart graceful / room persistence backend. Double-disconnect và online flow lõi đã có lab/integration/widget test; vẫn giữ một vòng test tay cuối cho lifecycle OS thật.

---

## 3. Các Sprint đã code xong, sync cloud một phần

> Sprint 9, 10, 11 vẫn dựa trên local Hive là chính, nhưng đã có cầu nối lên cloud Firestore qua Sprint 8b.

### 🟢 Sprint 9 — Game History + Replay AI
- Model lưu ván: [game_record.dart](cchess/lib/data/models/game_record.dart).
- Repository (Hive): [game_history_repository.dart](cchess/lib/data/repositories/game_history_repository.dart).
- Màn lịch sử: [game_history_screen.dart](cchess/lib/presentation/history/game_history_screen.dart).
- Replay engine + UI: [replay_controller.dart](cchess/lib/presentation/replay/replay_controller.dart), [game_replay_screen.dart](cchess/lib/presentation/replay/game_replay_screen.dart).
- AI phân tích nước hay/dở: [game_analyzer.dart](cchess/lib/core/chess_engine/ai/game_analyzer.dart) (351 dòng).
- **Test:** [game_history_test.dart](cchess/test/game/game_history_test.dart), [replay_controller_test.dart](cchess/test/replay/replay_controller_test.dart).

**Cloud sync:** mỗi ván local/bot saved sẽ push lên `users/{uid}/game_records/{gameId}` (Sprint 8b). Ván ranked online sẽ do server backend ghi qua `recordRankedGame` (Sprint 12).

---

### 🟢 Sprint 10 — Achievements + Daily Quests
- Model huy chương + engine kích hoạt: [achievement.dart](cchess/lib/data/models/achievement.dart), [achievement_definitions.dart](cchess/lib/data/datasources/local/achievement_definitions.dart), [achievement_repository.dart](cchess/lib/data/repositories/achievement_repository.dart).
- Màn huy chương: [achievements_screen.dart](cchess/lib/presentation/achievements/achievements_screen.dart).
- Quest hàng ngày: [daily_quest.dart](cchess/lib/data/models/daily_quest.dart), [daily_quest_repository.dart](cchess/lib/data/repositories/daily_quest_repository.dart), [daily_quests_screen.dart](cchess/lib/presentation/quests/daily_quests_screen.dart).
- **Test:** [achievement_engine_test.dart](cchess/test/achievement/achievement_engine_test.dart), [daily_quest_test.dart](cchess/test/quest/daily_quest_test.dart).

**Phụ thuộc Sprint 8:** chia sẻ thành tích trên leaderboard, gửi thưởng quest từ server (chống cheat).

---

### 🟢 Sprint 11 — Opening Library (Khai cuộc Đại sư — B6)
- Model: [opening.dart](cchess/lib/data/models/opening.dart).
- Seed khai cuộc cổ điển: [opening_seed.dart](cchess/lib/data/datasources/local/opening_seed.dart) (5 khai cuộc, ~148 dòng).
- Repo: [opening_repository.dart](cchess/lib/data/repositories/opening_repository.dart).
- UI: [opening_list_screen.dart](cchess/lib/presentation/openings/opening_list_screen.dart), [opening_detail_screen.dart](cchess/lib/presentation/openings/opening_detail_screen.dart) (cây biến thể tương tác).
- **Test:** [opening_seed_test.dart](cchess/test/opening/opening_seed_test.dart).

**Phụ thuộc Sprint 8:** CMS để tăng từ 5 → 50+ khai cuộc, tải nội dung từ server, gắn video.

---

## 4. Các Sprint **chưa làm** (theo thứ tự ưu tiên)

### 🟡 Sprint 12 — Online Matchmaking + Spectate (A1, A5, A6)

**Phase 1 hoàn thành 2026-05-24** (A1 Cờ Tướng Online Ranked):
- ✅ Step 1-8 backend (echo + auth + rooms + move transport + clock + reconnect + persistence)
- ✅ Step 5 Xiangqi rule validation server-side (engine port từ Dart sang TypeScript)
- ✅ Matchmaking ELO bucket/tolerance queue
- ✅ Per-room clock config (3/5/10/15/30 phút) chọn từ lobby
- ✅ ELO tính chuẩn Elo K=32, ghi cloud cùng game_records mirror cho cả 2 player
- ✅ Reconnect grace 60s sau disconnect, snapshot phục hồi
- ✅ Production deploy https://cchess-backend.onrender.com (Render free tier)
- ✅ Verified ván 10 phút giữa 2 phone Android thật qua Internet (Mieteo/CChess repo)

**Phase 2 còn lại**:
- ✅ A6 Spectate cơ bản — viewer join bằng room ID, nhận snapshot moves/chat/clock, xem board read-only, không có quyền move/resign
- ✅ A6 polish bước 1 — `list-active-rooms` + lobby hiển thị ván đang diễn ra để xem nhanh
- ✅ A6 test tự động bước 1 — backend `rooms.test.ts` cover spectator read-only, spectator leave, active room filtering
- ✅ **A6 share link/QR — code done 2026-06-07.** Helper `room_share.dart` (build link `/r/<ID>`, invite text, parse roomId từ link/deep-link), `ShareRoomSheet` (QR + sao chép + native share via `share_plus`), nút chia sẻ trong lobby (đang chờ đối thủ), tile "ván đang diễn ra", và app bar màn hình ván. Deep-link in-app `online-lobby?spectate=ID`/`?join=ID` tự kết nối + vào phòng. Backend landing page `GET /r/:id`. Unit test `room_share_test.dart` 17/17.
- ✅ **Đấu lại (rematch) — code done 2026-06-07.** Backend `rematch-offer/decline` + `startRematch` (đổi màu, reset clock/engine) + UI dialog kết quả reactive (mời/chờ/đồng ý/từ chối/huỷ, chặn khi đối thủ rời, tự đóng khi ván mới bắt đầu). Test tự động handshake WS đã có (T3); **test tay E2E đa thiết bị** → xem Nhóm R trong [`10_KE_HOACH_TEST.md`](10_KE_HOACH_TEST.md).
- ✅ **Test tự động WS đóng hết 2026-06-07 (đợt 2).** `server.test.ts` integration WS thật (in-process, inject auth/persist giả): T3 rematch handshake + T7 reconnect snapshot + T8 chat (broadcast/rate-limit/cap/chặn-sau-ended). Refactor `server.ts` → `createCChessServer()` factory + guard `CCHESS_NO_LISTEN`. Backend `npm test` 17/17.
- ✅ A6 share link / QR done (2026-06-07) — còn moderation cho viewer public nếu mở cộng đồng
- ✅ **A5 Chat polish — chip tin nhắn nhanh done 2026-06-11.** Hàng `ActionChip` preset (👋🍀🔥😅👏🤝) trong chat sheet, gửi qua `chat-message` thường nên rate-limit/cap server áp dụng nguyên vẹn. Còn lại nếu cần: mute/report khi mở public.
- ✅ **Hardening double-disconnect (D5) done 2026-06-11.** `Room.disconnectGrace: Map<uid, {timer, deadline}>` — cả 2 người chơi cùng rớt vẫn giữ cửa sổ reconnect riêng (bug cũ: người rớt sau ghi đè marker của người rớt trước → người trước không thể reconnect). Người rớt trước hết grace trước → xử thua trước. `reconnected` snapshot thêm `peerInGrace{uid, remainingMs}`. Phòng kết thúc khi cả 2 vắng mặt tự dọn khỏi memory. Test: `server.disconnect.test.ts` (2 integration test).
- ⏳ **(việc của bạn) Render free tier** ngủ sau 15 phút → upgrade Starter $7/tháng khi launch thật
- ⏳ **(việc của bạn) Test tay cuối 2 thiết bị** — R/S đã đóng; còn D4 OS-thật, M5 với Firebase thật, H4 chất lượng gợi ý và một vòng nhìn-mắt cho C2/D/G4 theo [`10_KE_HOACH_TEST.md`](10_KE_HOACH_TEST.md)
- Online hardening còn lại (tuỳ chọn, chưa làm): graceful server restart / room persistence backend

### 🟡 Sprint 13 — Biến thể: Cờ Úp (A3), Cờ Casual (A2)
**Đã làm — A3 Cờ Úp bản local (2026-06-25):**
- Engine `XiangqiCupGame` ([xiangqi_cup_game.dart](cchess/lib/core/chess_engine/xiangqi_cup_game.dart)): úp ngẫu nhiên mọi quân trừ Tướng; quân úp đi theo **mặt phủ** (vai trò ô đang đứng), lật lộ danh tính thật khi đi nước đầu của quân đó.
- **Luật Sĩ/Tượng đã mở đúng cờ úp**: ngửa rồi thì **thoát giới hạn cung/sông** — Sĩ chéo 1 ô khắp bàn (qua sông, áp sát/chi chiếu Tướng được), Tượng chéo 2 ô khắp bàn (vẫn cản mắt Tượng); phát hiện chiếu (`_cupInCheck`) cũng tính theo tầm mới này.
- UI bàn cờ: mặt quân úp **trơn** (bỏ icon mắt + gạch chéo), sửa **nhấp nháy toàn bàn khi chọn quân** bằng cách gắn `Key` theo ô cho mọi con của `Stack`. Vào từ Trang Chủ / Đối Đầu → `?mode=cup` (local 2 người).
- Test: nhóm "revealed Sĩ/Tượng roam freely" trong [xiangqi_cup_game_test.dart](cchess/test/chess_engine/xiangqi_cup_game_test.dart).

**Đã làm — backend foundation Cờ Úp online + Bot Cờ Úp (2026-06-25):**
- **Engine cup server-side** ([cupGame.ts](cchess-backend/src/engine/cupGame.ts)): port `XiangqiCupGame` sang TS, **shuffle + hidden-assignment do server giữ** (seed cho test), validate đúng luật cờ úp (Sĩ/Tượng ngửa đi tự do), `publicSnapshot()` = view công khai (mặt phủ + quân đã lộ + danh sách ô úp) **không lộ danh tính ẩn**.
- **match.ts variant-aware**: phòng `variant:'cup'` dùng engine cup; `applyMove` trả **reveal** (danh tính quân vừa lộ + quân bị ăn) để broadcast; `cupSnapshot()` cho reconnect.
- **Matchmaking theo variant** ([matchmaking.ts](cchess-backend/src/matchmaking.ts)): cup ↔ standard **không bao giờ ghép chéo**; `find-match` lấy `eloCup` cho cup; protocol `opponent-move`/`move-ack` kèm `reveal`, `reconnected` kèm `cup` snapshot.
- **ELO Cờ Úp riêng** ([persistence.ts](cchess-backend/src/persistence.ts)): ván cup ranked ghi `eloCup` (pool riêng, không đụng `eloChess`) + game record gắn `variant:'cup'`; counters tổng (`wins/losses/draws/totalGames`) dùng chung.
- **Bot Cờ Úp** ([cup_bot_engine.dart](cchess/lib/core/chess_engine/ai/cup_bot_engine.dart)): minimax cup riêng (Pikafish/minimax chuẩn không hiểu quân ẩn), **không gian lận** — chỉ nhận bàn nhìn thấy + tập ô úp; quân úp định giá theo **kỳ vọng** (~320cp). Vào từ Đối Đầu → "Cờ Úp với Máy" (`GameMode.cupVsBot`, chọn cấp độ).
- Test: [cupGame.test.ts](cchess-backend/src/engine/cupGame.test.ts) (16), [match.cup.test.ts](cchess-backend/src/match.cup.test.ts) (6), +matchmaking variant +persistence eloCup; Flutter [cup_bot_engine_test.dart](cchess/test/chess_engine/ai/cup_bot_engine_test.dart) (3).

**Đã làm — client online Cờ Úp (2026-06-25, đợt 3):** engine cup phía client [cup_client_game.dart](cchess/lib/core/chess_engine/cup_client_game.dart) (`CupClientGame implements ChessGameSession`) chỉ thấy **mặt phủ + quân đã lộ**, KHÔNG bao giờ biết danh tính ẩn; áp `reveal` từ `move-ack` (lật quân mình) và `opponent-move` (lật quân đối thủ), dựng lại bàn từ `cup` snapshot khi reconnect/spectate. Luật sinh nước/chiếu tách ra [cup_rules.dart](cchess/lib/core/chess_engine/cup_rules.dart) dùng chung với `XiangqiCupGame` (validate local đúng vì hợp lệ chỉ phụ thuộc mặt phủ + quân đã lộ). Nối vào luồng online: controller `game` → `ChessGameSession?`, `find-match`/`create-room` mang `variant`, render mặt úp trong ván online (`hiddenPositions`); backend bổ sung `cup` snapshot vào `spectate-started`. Vào từ Đối Đầu → **"Cờ Úp Online"** (`?variant=cup`). Test: [cup_client_game_test.dart](cchess/test/chess_engine/cup_client_game_test.dart) (8).

**Chưa làm:** A2 Cờ Casual (không tính ELO) + mời bạn qua link/ID. Bot cup v1 giả định lật-thành-mặt-phủ trong cây tìm kiếm (chưa expectiminimax đầy đủ).

### 🔒 Sprint 14 — Community (Module C) (cần S12 + Cloud Functions cho leaderboard aggregation)
- Bạn bè (C1): tìm theo ID, danh sách online/offline.
- Leaderboard server-side (C2): toàn quốc + khu vực.
- Câu lạc bộ Kỳ Xã (C3).
- Giải đấu định kỳ (C4).
- Tin tức + Tàn Cục Thách Đấu hàng ngày (C6).

### 🟡 Sprint 15 — AI Coach (B3) + Pikafish server-side (engine lai) — engine smoke thật xong, chờ hardening sản phẩm
> **Kế hoạch chi tiết + trạng thái:** [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md) §10. Hướng cũ "Pikafish FFI on-device" đã **bỏ** do ràng buộc GPL-3.0 (app thương mại) + iOS App Store xung khắc GPL.
- ✅ **Đã code/chạy (2026-06-07/11, cập nhật 2026-06-20):** engine-service backend (UCI wrapper/pool/cache/quota/HTTP API + 7 test), Dockerfile.engine + render.yaml service riêng, Flutter `MoveEngine`/`EngineRouter` + fallback, bot **Đại Sư+**, replay analyze qua router, **nút Gợi ý in-game**, **attribution GPL trong Cài đặt**, smoke gate `engine:smoke` + `engine:smoke:quota`, `cchess-engine` Render smoke thật **8/8 PASS** gồm quota.
- ⬜ **Còn lại:** quota/VIP bền vững (Firestore/Redis thay in-memory), xác nhận **NNUE license thương mại**, đối chiếu FEN/UCI thêm nhiều thế cố định + H4 chất lượng gợi ý, upgrade engine lên Standard trước traffic thật, AI Coach lớp diễn giải rule-based (B3 UI).

### 🟡 Sprint 16 — Khám Phá (Module D)
**Đã làm:** Shop (D1) + Inventory (D2) + màn **Explore** (hub) — UI `presentation/shop/` (`shop_screen`, `inventory_screen`, `explore_screen`, `shop_visuals`, `shop_controller`); models `shop_item`/`inventory_item`/`wallet`; `shop_repository` + `shop_api_source`; route `/shop` `/inventory` trong `app_router`. Backend `src/shop/` (routes/store/types) + `scripts/import_shop.ts` + `shop.seed.json` + `shop.test.ts`; `firestore.rules` cho inventory/ví.
**Chưa làm:** Khung Avatar (D3) gắn thật, Mail (D4), Event (D5), Welfare/điểm danh (D6), Crafting (D7); nối ví/kinh tế thật (mua bằng coin/VIP) end-to-end; quyết định **tab thứ 6 hay gộp** (hiện 5 tab).

### ⬜ Sprint 17 — VIP & In-App Purchase (Module E5)
- Tích hợp Google Play Billing + Apple StoreKit.
- VIP tháng/quý/năm.
- Quyền lợi: bỏ giới hạn AI hint, AI Coach, lưu kỳ phổ.

### ⬜ Sprint 18 — Tính năng nâng cao (Giai đoạn 3)
- OCR chụp thế cờ (B7) — cần ML model (MobileNet/YOLO).
- Học thuộc kỳ phổ (B8).
- Livestream ván đấu (C5).
- Diễn đàn (C7).

---

## 5. Mapping spec → trạng thái (tóm tắt)

| Mã spec | Tính năng | Trạng thái | Sprint |
|---|---|:---:|:---:|
| A1 | Cờ Tướng Online Ranked | ✅ | **MVP done 2026-05-24** — matchmaking, ELO, ranked verified prod Render |
| A2 | Cờ Casual + mời bạn | 🔒 | 13 |
| A3 | Cờ Úp | 🟢 | 13 — **DONE end-to-end (2026-06-25)**: local + backend online (engine cup TS server-authoritative, matchmaking theo variant, ELO `eloCup` riêng, protocol reveal/snapshot) + Bot cup offline + **client online** (`CupClientGame` cover-only, áp reveal/snapshot, render mặt úp, vào từ "Cờ Úp Online"). Còn lại: chỉ test tay đa thiết bị |
| A5 | Chat + emoji + AI hint trong ván | 🟡 | Chat text done + **chip preset/emoji done 2026-06-11**; **AI hint done cho ván bot/local 2026-06-11** (EngineRouter, fallback minimax); hint trong ván online ranked cân nhắc sau (fair-play) |
| A6 | Spectate | 🟡 | Phase 2 — cơ bản done với `spectate-room`/`stop-spectating`, read-only board, active room list, backend read-only tests; **share link/QR done 2026-06-07** (link/QR + deep-link in-app + landing page); còn moderation public |
| A7 | Đấu Bot AI | ✅ | 5 |
| B1 | Khóa học vỡ lòng | 🟡 | UI placeholder, content chưa có |
| B2 | Khóa học video | ⬜ | sau S15 |
| B3 | AI Coach | 🟢 | 15 — **engine + lớp diễn giải `CoachAnalyzer` + màn `AiCoachScreen` done 2026-06-23** (phân tích theo giai đoạn + gợi ý luyện tập, remote→fallback); còn tinh chỉnh chất lượng theo Pikafish thật |
| B4 | Kho bài tập 10.000+ | 🟡 | Engine xong (S6), content thiếu |
| B5 | Kỳ phổ + Replay AI | 🟢 | 9 — đã sync `game_records` cloud |
| B6 | Khai cuộc Đại sư | 🟢 | 11 (chờ CMS) |
| B7 | OCR thế cờ | ⬜ | 18 |
| B8 | Học thuộc kỳ phổ | ⬜ | 18 |
| C1–C4 | Bạn bè, Leaderboard, CLB, Giải đấu | 🔒 | 14 |
| C5 | Livestream | ⬜ | 18 |
| C6 | Tin tức + Tàn cục hàng ngày | 🔒 | 14 |
| C7 | Diễn đàn | ⬜ | 18 |
| D1–D7 | Khám Phá (Shop, Inventory, ...) | ⬜ | 16 |
| E1 | Hồ sơ + cấp bậc | ✅ | 7 |
| E2 | Thống kê chi tiết | 🟡 | UI có, cần thêm chart |
| E3 | Huy chương | 🟢 | 10 |
| E4 | Nhiệm vụ | 🟢 | 10 |
| E5 | VIP Center | ⬜ | 17 |
| E6 | Tài khoản & bảo mật | ✅ | 8a — Anonymous + Google linking + sign out |
| E7 | Cài đặt | ✅ | 7 + 8a (thêm section Tài khoản) |

---

## 6. Số liệu tổng (cập nhật 2026-06-25)

- **Tổng file Dart `lib/`:** ~95 file (thêm `core/chess_engine/` lớp engine lai: move_engine / engine_router / local_minimax_engine / remote_pikafish_engine + transports / engine_providers).
- **Backend TypeScript:** realtime server + lab + engine-service (server, UCI wrapper, pool, analysis, cache, quota, FEN) đã có CI riêng.
- **Test tự động:** Backend `npm test` **142/142** (21 file) + `lab` 22/22 + `backend-ci` chạy `lab`, `lab:load`, `lab:fuzz`; Flutter `flutter test` **316/316** (33 file) + `flutter analyze`. (2026-06-25 đợt 3: +client online Cờ Úp `cup_client_game_test.dart` (8); cùng ngày +backend foundation Cờ Úp online — `cupGame.test.ts`, `match.cup.test.ts`, matchmaking variant, persistence eloCup — và Bot Cờ Úp `cup_bot_engine_test.dart`; trước đó +nhóm "revealed Sĩ/Tượng roam freely".) Phân loại nguồn test: xem bảng cuối [`10_KE_HOACH_TEST.md`](10_KE_HOACH_TEST.md).
- **Test tay:** R **ĐÓNG 12/12**; S **ĐÓNG 15/15**; C8 + H1–H3 PASS. Còn lại chủ yếu là vòng thật/visual: D4 OS lifecycle, M5 Firebase thật, H4 chất lượng gợi ý, C2/D/G4 nhìn-mắt.
- **Sprint hoàn thành (1 chiều):** 10/18 (1–7 + 8a + 8b + 8c).
- **Sprint code xong, sync một phần:** 3/18 (S9, S10, S11).
- **Sprint MVP done phase 1:** 1/18 (S12 — A1 Ranked production).
- **Sprint đang dở:** S12 phase 2 (chỉ còn test tay cuối + Render upgrade khi có user thật), S13 (A3 Cờ Úp **DONE end-to-end**: local + backend online + Bot + **client online** — chỉ còn A2 casual), S15 (engine lai — smoke thật xong, chờ quota/VIP bền vững, license, plan production và AI Coach B3), S16 (Shop/Inventory/Explore UI + backend đã có — còn Mail/Event/economy thật).
- **Sprint locked/chưa làm:** S14 (Community — cần S12), S17-18 (giai đoạn sau).
- **Tỷ lệ hoàn thành code (ước lượng theo spec MVP+G2):** ~82% (tăng sau automation gates, engine smoke thật và quota gate).
- **Tỷ lệ tính năng end-to-end dùng được production:** ~60–65% (ranked online thật đã chạy; engine Pikafish đã smoke thật trên Render nhưng chưa harden quota/VIP/license/plan cho traffic thật).
- **Production endpoint**: backend `https://cchess-backend.onrender.com` / `wss://cchess-backend.onrender.com`; engine `https://cchess-engine.onrender.com`. Cả hai đang ở Render free tier cho prototype/smoke; cần Starter/Standard trước khi mở user thật.
- **Repo GitHub**: Mieteo/CChess, branch `main`.

---

## 7. Khuyến nghị bước tiếp theo

### 7.1. Stage tiếp theo — hardening trước khi mở user thật

0. ✅ **Automation gate đã đủ dày cho Sprint 12/Sprint 15 hạ tầng**: backend 69/69, Flutter 226/226, lab/load/fuzz, engine smoke 8/8. Tiếp theo không nên mở rộng test máy móc lan man, chỉ giữ các gate này chạy lại sau deploy/config change.
1. **Quota/VIP bền vững cho engine** — chuyển quota in-memory sang Firestore/Redis, định nghĩa VIP bypass và reset theo ngày để không reset quota khi Render restart/redeploy.
2. **Production hardening Render** — backend lên Starter khi có user thật; engine lên Standard trước traffic AI thật; bật lịch chạy `engine-smoke` sau deploy và `post-deploy-smoke` khi cần kiểm ranked-write.
3. **Vòng test tay cuối** — D4 OS lifecycle thật, M5 Firebase thật, H4 chất lượng nước gợi ý/Pikafish, và nhìn-mắt C2/D/G4 trên thiết bị.
4. **License/commercial check** — chốt NNUE license trước khi dùng engine trong production thương mại.

### 7.2. Sprint 12 phase 2 (2-3 tuần) — hoàn thiện online

3. **OS-level deep link** — Android intent-filter + iOS universal link nếu muốn mở link `/r/<ID>` từ ngoài app, vì deep-link in-app đã có.
4. **Moderation khi mở public** — mute/report chat, giới hạn spectator/chat nếu active-room list thành cộng đồng mở.
5. **Push notification "tới lượt bạn"** — khi user background app + đến lượt, send FCM message tới device. Cần backend wire Cloud Messaging + client `firebase_messaging` setup.
6. **Friends list (C1) — Sprint 14 prep** — Firestore schema `friendships`, sync presence (online/offline qua Realtime Database/Firestore presence).

### 7.3. Sprint 13 (1-2 tuần) — biến thể game

10. **A3 Cờ Úp — DONE end-to-end (2026-06-25)**: local + backend online server-authoritative (shuffle/hidden ẩn với client, validate luật cờ úp, matchmaking theo variant, **ELO `eloCup` riêng**, protocol reveal + snapshot) + bot cup offline không gian lận + **client online** (`CupClientGame` cover-only áp reveal/snapshot, render mặt úp, vào từ "Cờ Úp Online"). Còn lại: chỉ test tay đa thiết bị cho ván cup online thật.
11. **A2 Cờ Casual + invite link** — không tính ELO, share roomId qua link/QR, friends-only matchmaking option.

### 7.4. Định hướng dài hạn (Q3-Q4 2026)

12. **AI Coach Pikafish server-side** (Sprint 15, engine lai — [11](11_KE_HOACH_TICH_HOP_ENGINE.md)) — phân tích sâu sau ván.
13. **Content production** (Sprint 11 follow-up + Sprint 6 puzzle 10.000+) — cần tool import PGN/FEN hoặc CMS web.
14. **Shop + VIP** (Sprint 16-17) — IAP, monetization.
15. **OCR + advanced** (Sprint 18).

---

*Cập nhật 2026-06-07: (1) hoàn thiện nút Đấu lại (rematch) — UI dialog reactive + xử lý lỗi đối thủ rời; (2) tạo [`10_KE_HOACH_TEST.md`](10_KE_HOACH_TEST.md) liệt kê 46 case online chưa xác nhận test; (3) thêm test tự động Nhóm T (backend `match.test.ts` + Flutter `online_match_controller_test.dart`, 16 test mới, tất cả xanh).*

*Cập nhật 2026-06-07 (đợt 2) — **đóng hết test tự động Sprint 12**: refactor `cchess-backend/src/server.ts` thành factory `createCChessServer({authenticate, persist})` (giữ nguyên hành vi production, entry point bọc trong guard `CCHESS_NO_LISTEN`) + thêm `server.test.ts` integration WS thật in-process (T3 rematch handshake / T7 reconnect snapshot / T8 chat). Backend `npm test` 17/17, `tsc` + `npm run build` sạch.*

*Cập nhật 2026-06-11 — **đợt code các phần không bị chặn** (không phải chờ test tay/sprint khác): nút Gợi ý in-game (EngineRouter + fallback, marker xanh ngọc, 6 test), attribution Pikafish GPL-3.0 trong Cài đặt, chip chat nhanh A5, hardening double-disconnect D5 (`disconnectGrace` map theo uid + `peerInGrace` + tự dọn phòng + 2 integration test, grace override qua env `CCHESS_RECONNECT_GRACE_MS`). Sprint 15 chuyển ⬜→🟡. Backend `npm test` 25/25, Flutter `flutter test` 148/148.*

*Cập nhật 2026-06-12 — **test tay Nhóm R đợt 1: 11/12 PASS + sửa bug R9.** Nguyên nhân gốc (3): client xoá `roomId` ngay khi `game-ended` làm `leave()` không gửi `leave-room`; nút back app-bar/hệ thống không đi qua `leave()` (socket "ma" ở lại phòng tới khi heartbeat dọn ~5–10s); client bên kia bỏ qua `peer-left` nên dialog không phản ứng. Sửa: giữ `roomId` sau game-ended, gom mọi đường thoát về `_onBackPressed()` + `PopScope` (đang chơi → xác nhận xử thua), controller xử lý `peer-left` → cờ `opponentLeftRoom` → dialog hiện ngay "Đối thủ đã rời — không thể đấu lại"; server dọn `rematchOfferedBy` của người rời. Test mới (T12): backend integration 1 + Flutter 4. Backend `npm test` 26/26, Flutter `flutter test` 152/152, analyze sạch.*

*Cập nhật 2026-06-13 — **đợt test tay 2 + tuning theo feedback**: R9 retest PASS → **Nhóm R đóng 12/12**; C8 PASS → nâng `CHAT_RATE_LIMIT_MS` 1.5s→2s; H1–H3 PASS (online + offline) với feedback "gợi ý hơi lâu, hơi kém" → `BotEngine` thêm chế độ **best-effort** cho hint/analysis: bỏ delay nhân tạo `minThinkTime` 1.2s, bỏ randomness, iterative deepening ngân sách ~2s (depth 2→6, thế nhẹ đào sâu hơn, giữa ván nặng trả nhanh kết quả depth đã xong) + 2 test mới (T13).*

*Cập nhật 2026-06-13 (đợt 2) — **Nhóm S PASS 12/12 + 3 cải tiến UX theo feedback**: (1) số mắt xem 👁 hiện trên app bar cho **cả người chơi** (trước chỉ người xem thấy); (2) **dialog kết quả người xem** giờ chỉ có 1 nút "Thoát", tự đóng + xem tiếp khi 2 kỳ thủ đấu lại, banner "Một kỳ thủ đã rời — trận đấu khép lại" khi có người thoát — sửa kèm bug tiềm ẩn rematch `game-start{yourColor:null}` biến người xem thành "người chơi Đỏ" trong state client; (3) **phòng chờ tự hủy sau 1 phút** không có đối thủ vào: server gửi `room-expired` + xóa phòng (TTL override env `CCHESS_WAITING_ROOM_TTL_MS`), lobby tự quay về màn chính kèm thông báo. Test mới (T14): backend `server.waitingroom.test.ts` 2 + Flutter 2. Backend `npm test` **28/28**, Flutter `flutter test` **156/156**, analyze sạch. Lưu ý thiết kế: "chờ đối thủ MỚI vào phòng cũ sau khi 1 người rời" KHÔNG nằm trong phạm vi này — phòng khép lại khi 1 kỳ thủ thoát; mời người mới = flow invite/casual của Sprint 13. Các mục này sau đó đã được tự động hóa/smoke tiếp trong đợt 2026-06-19/20; xem phần đầu tài liệu và [`10_KE_HOACH_TEST.md`](10_KE_HOACH_TEST.md).*

*Cập nhật 2026-06-25 (đợt 2) — **A3 Cờ Úp: backend online foundation + Bot Cờ Úp**: (A) Backend server-authoritative cho Cờ Úp online — port engine `cupGame.ts` (shuffle/hidden-assignment do server giữ, **client không bao giờ biết trước**), `match.ts` chọn engine theo `variant` và trả `reveal` mỗi nước, matchmaking **tách cup ↔ standard** (không ghép chéo) bucket theo `eloCup`, protocol kèm reveal + `cup` snapshot khi reconnect, persistence ghi **`eloCup` pool riêng** + record `variant:'cup'`. (B) **Bot Cờ Úp** `cup_bot_engine.dart` — cup-minimax chạy trong isolate, **không gian lận** (chỉ thấy mặt phủ + quân đã lộ, quân úp định giá kỳ vọng ~320cp); `GameMode.cupVsBot` + điểm vào "Cờ Úp với Máy" (chọn cấp độ). Test: backend **142/142** (+`cupGame.test.ts`, `match.cup.test.ts`, matchmaking variant, persistence eloCup) + lab 22/22; Flutter **308/308** (+`cup_bot_engine_test.dart`), analyze sạch. Còn lại của A3: **client online Cờ Úp** (render mặt úp + áp reveal) — backend đã sẵn sàng.*

*Cập nhật 2026-06-25 — **A3 Cờ Úp bản local + polish bàn cờ (Sprint 13 🔒→🟡)**: (1) sửa luật **Sĩ/Tượng đã mở** trong `XiangqiCupGame` cho đúng cờ úp — ngửa rồi thì **thoát giới hạn cung/sông**, Sĩ đi chéo 1 / Tượng đi chéo 2 đi khắp bàn (Tượng vẫn cản mắt), `_cupInCheck` nhận diện chiếu theo tầm mới; quân **còn úp** vẫn đi theo mặt phủ (vai trò ô). (2) UI bàn cờ: bỏ icon mắt+gạch chéo trên quân úp (mặt trơn), sửa **nhấp nháy toàn bàn khi chọn quân** bằng `Key` theo ô cho mọi con của `Stack`. Test nhóm "revealed Sĩ/Tượng roam freely" trong `xiangqi_cup_game_test.dart`. Đồng bộ doc Sprint 16 (Shop/Inventory/Explore UI + backend `src/shop/`) ⬜→🟡. Flutter `flutter test` **305/305** (31 file), backend `npm test` **117/117** (19 file), `flutter analyze` sạch.*

*Cập nhật 2026-06-25 (đợt 3) — **A3 Cờ Úp: client online (A3 DONE end-to-end)**: nối phía Flutter vào backend cup đã có. (1) Engine cup phía client `CupClientGame implements ChessGameSession` ([cup_client_game.dart](cchess/lib/core/chess_engine/cup_client_game.dart)) — view **cover-only** giống đúng người chơi, KHÔNG bao giờ biết danh tính ẩn; áp `reveal` từ `move-ack` (lật quân mình — đi nước úp trượt như đĩa trống rồi mới lật) và `opponent-move` (lật quân đối thủ), dựng lại bàn từ `cup` snapshot khi reconnect/spectate (`fromSnapshot`). Validate + áp lạc quan nước của chính mình hợp lệ vì **tính hợp lệ chỉ phụ thuộc mặt phủ + quân đã lộ** (không phụ thuộc danh tính ẩn). (2) Tách luật sinh nước/chiếu cờ úp ra [cup_rules.dart](cchess/lib/core/chess_engine/cup_rules.dart) dùng chung `XiangqiCupGame` ↔ `CupClientGame` (1 nguồn sự thật, giữ nguyên hành vi engine local). (3) Nối luồng online: `OnlineMatchState.game` → `ChessGameSession?`, `find-match`/`create-room` mang `variant`, render mặt úp (`hiddenPositions`) trong ván online; backend bổ sung `cup` snapshot vào `spectate-started`. Vào từ Đối Đầu → **"Cờ Úp Online"** (`?variant=cup`). Test: Flutter `flutter test` **316/316** (33 file, +`cup_client_game_test.dart` 8), backend `npm test` **142/142**, `flutter analyze` + `tsc` sạch. **A3 còn lại: chỉ test tay đa thiết bị**; còn A2 Cờ Casual invite-by-link.*
