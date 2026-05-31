# 📊 KẾ HOẠCH & TIẾN ĐỘ DỰ ÁN — CChess

> Tài liệu sống — cập nhật ngày **2026-05-31** sau Sprint 12 group 1 polish + A5 chat cơ bản + A6 Spectate cơ bản.
> Mục đích: tổng kết **đã làm**, **chưa làm**, **đang chờ phụ thuộc** theo từng Sprint.
> Tham chiếu chéo: [`01_FEATURE_SPECIFICATION.md`](01_FEATURE_SPECIFICATION.md), [`02_PROMPT_UI_UX.md`](02_PROMPT_UI_UX.md), [`03_PROMPT_FEATURES_ROADMAP.md`](03_PROMPT_FEATURES_ROADMAP.md), [`07_HUONG_DAN_THIET_LAP_FIREBASE.md`](07_HUONG_DAN_THIET_LAP_FIREBASE.md), [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md), [`09_BACKEND_SERVER_HOAT_DONG.md`](09_BACKEND_SERVER_HOAT_DONG.md).

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
| 12 | Online Matchmaking + Spectate (A1, A5, A6) | 🟡 | **A1 Ranked done**; **A5 chat cơ bản done**; **A6 Spectate cơ bản + active room list done**; còn share link/test tự động |
| 13 | Cờ Úp + Cờ Casual (A3, A2) | 🔒 | Chờ engine variant + invite-by-link flow |
| 14 | Community (Bạn bè, Leaderboard, CLB) | 🔒 | Chờ S12 |
| 15 | AI Coach (B3) + AI Replay nâng cao (B5) | ⬜ | Cần Pikafish FFI |
| 16 | Khám Phá (Shop, Inventory, Mail, Event) | ⬜ | Cần backend kinh tế |
| 17 | VIP Center + IAP | ⬜ | Phụ thuộc store account |
| 18 | OCR thế cờ (B7), học thuộc kỳ phổ (B8) | ⬜ | Giai đoạn 3 |

> **Trục thời gian cập nhật (cuối 5/2026):**
> - Sprint 8 hoàn thành 3 lát: 8a (Firebase Auth + Firestore + rules deployed), 8b (sync local↔cloud + Cloud Functions deployed Blaze), 8c (backend Node.js WebSocket production-deployed Render).
> - **Sprint 12 phase 1 A1 hoàn thành 2026-05-24**: matchmaking tự động + per-room clock (3/5/10/15/30 phút) + Xiangqi rule validation server-side + ELO Elo K=32 + reconnect grace 60s + Firestore persistence mirror records. Verified ván 10 phút giữa 2 thiết bị Android thật qua Internet (Render free tier endpoint). Group 1 polish 2026-05-31 đã nâng matchmaking lên ELO bucket/tolerance.
> - Sprint 9–11 đã unblock (cloud sync chạy). Sprint 12 group 1 polish đã xong 2026-05-31: ELO bucket matchmaking, rollback khi server reject move, profile auto-refresh sau game-ended. Sprint 12 phase 2 đã có A5 chat text, A6 Spectate theo room ID và danh sách ván đang diễn ra.

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

**Chưa làm:** transposition table, opening book riêng cho bot, Pikafish FFI (đẩy sang Sprint 15).

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

**Chưa làm:** server restart graceful / room persistence backend, double-disconnect refinement, test tự động online flow.

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
- A6 polish còn lại — share link / spectator UX nâng cao / moderation nếu mở cộng đồng
- A5 Chat polish — đã có `chat-message` protocol + UI bottom sheet + rate limit; còn emoji whitelist/preset nhanh nếu cần
- Render free tier ngủ sau 15 phút → upgrade Starter $7/tháng khi launch thật
- Online hardening: double-disconnect, graceful server restart, test tự động cho reconnect/chat

### 🔒 Sprint 13 — Biến thể: Cờ Úp (A3), Cờ Casual (A2) (cần S12)
- Engine biến thể Cờ Úp (random úp quân, mở khi đi nước đầu của quân đó).
- ELO Cờ Úp tính riêng.
- Mời bạn qua link/ID.

### 🔒 Sprint 14 — Community (Module C) (cần S12 + Cloud Functions cho leaderboard aggregation)
- Bạn bè (C1): tìm theo ID, danh sách online/offline.
- Leaderboard server-side (C2): toàn quốc + khu vực.
- Câu lạc bộ Kỳ Xã (C3).
- Giải đấu định kỳ (C4).
- Tin tức + Tàn Cục Thách Đấu hàng ngày (C6).

### ⬜ Sprint 15 — AI Coach (B3) + Pikafish FFI
- Tích hợp Pikafish binary qua dart:ffi (Android ARM64 + iOS).
- AI Coach: phân tích nước dở, đề xuất bài tập cá nhân hóa.
- Nâng cấp `game_analyzer.dart` từ minimax đơn giản → đánh giá theo Pikafish.

### ⬜ Sprint 16 — Khám Phá (Module D)
- Shop (D1), Inventory (D2), Khung Avatar (D3), Mail (D4), Event (D5), Welfare/điểm danh (D6), Crafting (D7).
- Cần **tab thứ 6 hoặc gộp vào tab hiện có** — hiện kiến trúc mới có 5 tab. Phải quyết định lại sau Sprint 14.

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
| A3 | Cờ Úp | 🔒 | 13 |
| A5 | Chat + emoji + AI hint trong ván | 🟡 | Chat text cơ bản done — `chat-message` WS + bottom sheet; emoji/AI hint còn lại |
| A6 | Spectate | 🟡 | Phase 2 — cơ bản done với `spectate-room`/`stop-spectating`, read-only board, active room list, backend read-only tests; còn share link |
| A7 | Đấu Bot AI | ✅ | 5 |
| B1 | Khóa học vỡ lòng | 🟡 | UI placeholder, content chưa có |
| B2 | Khóa học video | ⬜ | sau S15 |
| B3 | AI Coach | ⬜ | 15 |
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

## 6. Số liệu tổng (sau khi A1 Ranked MVP deploy, 2026-05-24)

- **Tổng file Dart `lib/`:** ~85 file (+presentation/online/, +data/services/reconnect_store/, +data/services/game_socket_service/, +data/services/cloud_sync_service/, +data/services/google_auth_service/).
- **Backend TypeScript:** ~1000 dòng (server.ts + auth.ts + rooms.ts + match.ts + persistence.ts + elo.ts + matchmaking.ts + engine/ port).
- **Tổng dòng test:** Flutter 1.306 dòng / 12 file test; backend đã bắt đầu có `rooms.test.ts` cho A6 spectate/read-only.
- **Sprint hoàn thành (1 chiều):** 10/18 (1–7 + 8a + 8b + 8c).
- **Sprint code xong, sync một phần:** 3/18 (S9, S10, S11).
- **Sprint MVP done phase 1:** 1/18 (S12 — A1 Ranked production).
- **Sprint locked:** S13 (Cờ Úp + Casual), S14 (Community), S15-18 (giai đoạn sau).
- **Tỷ lệ hoàn thành code (ước lượng theo spec MVP+G2):** ~75% (tăng từ 65% sau A1 done).
- **Tỷ lệ tính năng end-to-end dùng được production:** ~55% (đã có ranked online thật, deploy public; còn lại là content + features mới).
- **Production endpoint**: https://cchess-backend.onrender.com (Render free tier — ngủ sau 15 phút idle).
- **Repo GitHub**: Mieteo/CChess, branch `main`.

---

## 7. Khuyến nghị bước tiếp theo

### 7.1. Polish ngắn (1-3 giờ mỗi item) — củng cố A1 trước khi mở rộng

1. **Tests cho online flow** — unit test `OnlineMatchController` (mock socket events), integration test backend `match.ts` apply move + clock + reconnect + chat.
2. **Render upgrade Starter** ($7/tháng) — bỏ sleep 15 phút, lúc nào có user thật phải bỏ.

### 7.2. Sprint 12 phase 2 (2-3 tuần) — hoàn thiện online

3. **A6 Spectate polish tiếp** — share link, spectator count UX rõ hơn trong lobby/game, mở rộng test tự động cho WS protocol end-to-end.
4. **A5 Chat polish** — emoji preset/whitelist, mute/report sau này nếu mở public.
5. **Push notification "tới lượt bạn"** — khi user background app + đến lượt, send FCM message tới device. Cần backend wire Cloud Messaging + client `firebase_messaging` setup.
6. **Friends list (C1) — Sprint 14 prep** — Firestore schema `friendships`, sync presence (online/offline via Realtime Database).

### 7.3. Sprint 13 (1-2 tuần) — biến thể game

10. **A3 Cờ Úp** — engine variant (random ẩn quân, mở khi đi nước đầu), ELO Cờ Úp riêng, UI mới
11. **A2 Cờ Casual + invite link** — không tính ELO, share roomId qua link/QR, friends-only matchmaking option.

### 7.4. Định hướng dài hạn (Q3-Q4 2026)

12. **AI Coach Pikafish FFI** (Sprint 15) — phân tích sâu sau ván.
13. **Content production** (Sprint 11 follow-up + Sprint 6 puzzle 10.000+) — cần tool import PGN/FEN hoặc CMS web.
14. **Shop + VIP** (Sprint 16-17) — IAP, monetization.
15. **OCR + advanced** (Sprint 18).

---

*Cập nhật 2026-05-31 sau khi A1 Ranked đã test thật, group 1 polish đã merge, A5 chat text, A6 Spectate cơ bản, active room list và backend read-only tests được triển khai. Lần cập nhật kế tiếp đề xuất: sau A6 share link hoặc khi chốt Sprint 13 Cờ Úp/Casual.*
