# 13 — Kế hoạch Refactor: Hệ Bot theo ELO liên tục (ELO Ladder)

> Trạng thái: **ĐÃ TRIỂN KHAI Phase 0–6 (code)** — còn lại: calibrate thực nghiệm bằng đấu thử (thủ công).
> Phạm vi: Frontend (Flutter) + Backend (Node engine-service)
> Quyết định đã chốt: (1) ẩn ELO bot trong ván, **lộ khi kết thúc**; (2) làm **cả FE + BE**; (3) **bỏ hẳn danh xưng**, chỉ dùng số ELO.

> ### Trạng thái triển khai (cập nhật)
> - **P0–P2** ✅ `engine_config.dart` (`configForElo`), engine nhận `EngineConfig`, `matchmaking/{bot_matchmaker,elo_scoring}.dart` + test.
> - **P3** ✅ `game_screen` lưu bracket → `eloDelta` → `applyGameResult` + `GameRecord.eloDelta`; màn kết quả **lộ ELO bot + bracket**.
> - **P4** ✅ `bot_select_screen` (standard) → ELO + **"Tìm trận"** (`pickBot`); `app_router` parse `botElo`/`bracket`; trong ván đối thủ chỉ hiện **"Bot"** (ẩn ELO). Cờ Úp giữ luồng tier riêng.
> - **P5** ✅ backend: `EngineLimit.skillLevel/uciElo`, request `elo/skill`, clamp trong `limitForRequest`, **cache key kèm skill/elo** (`fen.ts`), `uci_engine` set `UCI_Elo`/`Skill Level` trước search + **reset** sau (env `PIKAFISH_STRENGTH_MODE`). Test: ELO/skill tới pool + cache tách + go-command set/reset.
> - **P6** ✅ bỏ `RankTier`/`RankInfo`/`rankForElo` → `EloConstants.colorForElo`; badge hiện **số ELO**. **Quyết định:** giữ `BotDifficulty`/`EngineLevel` (vẫn dùng cho Cờ Úp + hint/analysis + tương thích cũ) thay vì xoá. **Còn lại:** calibrate bảng số `configForElo` + env backend bằng đấu thử thực tế (thủ công, không tự động hoá được).

---

## 1. Mục tiêu & lý do

Hệ hiện tại chia **5–6 tier danh xưng** (Tập Sự → Đại Sư+), map cứng vào minimax depth 1–5. Vấn đề:

- Quá thô, chạm trần nhanh, không tạo động lực luyện tập dài hạn.
- Logic "chọn độ khó" kiểu game offline, không phải matchmaking thật.

Mục tiêu mới:

1. **ELO là thước đo duy nhất** (dải 1000–2900, mỗi ~100 ELO ≈ một bậc thực tế).
2. **Bot ẩn danh** — người chơi chỉ thấy "Bot", không biết engine; **ELO bot ẩn trong ván, lộ ở màn kết quả**.
3. **Ghép cặp ngẫu nhiên** quanh ELO người chơi: bằng / +100 / −100.
4. **Tính điểm bất đối xứng** (sơ đồ người dùng đề xuất).
5. **Bỏ RankTier danh xưng**, hiển thị thẳng con số ELO ở mọi nơi.

### Nguyên tắc kiến trúc cốt lõi
> **KHÔNG tạo 100 con bot.** Tạo **một hàm** `configForElo(int targetElo) → EngineConfig`. "Level/bậc" chỉ là lớp hiển thị. Số engine độc lập hoàn toàn với độ mịn của thang ELO.

---

## 2. Hiện trạng code — **ảnh chụp TRƯỚC refactor** (baseline lịch sử)

> ⚠️ Bảng dưới mô tả code **trước khi** triển khai Phase 0–6 (giữ lại làm mốc đối chiếu). **Đã lỗi thời** so với code hiện tại: `RankTier`/`rankForElo` đã **xoá** (→ `EloConstants.colorForElo`, badge hiện số ELO); ELO ván-vs-bot đã nối thật (`eloDelta` ≠ 0); ElephantEye **đã wire** vào dải 1500–1900; `bot_select_screen` (standard) đã **bỏ 5 thẻ + Đại Sư+**, dùng "Tìm trận" theo ELO; backend đã nhận `elo`/`skill`. Trạng thái hiện hành xem hộp "Trạng thái triển khai" ở đầu doc + §9.

| Thành phần | File | Ghi chú |
|---|---|---|
| 5 tier độ khó | `cchess/lib/core/chess_engine/ai/bot_difficulty.dart` | enum + settings(depth/random/suboptimal/think) + estimatedElo + nameVi |
| 6 engine level | `cchess/lib/core/chess_engine/move_engine.dart` | `EngineLevel` (5 + grandmaster); engine nhận **enum**, không nhận số |
| Router engine | `cchess/lib/core/chess_engine/engine_router.dart` | dùng remote **chỉ khi** `level == grandmaster`; **ElephantEye chưa wire** vào `local` |
| Minimax | `local_minimax_engine.dart`, `ai/bot_engine.dart`, `ai/minimax.dart` | depth + randomChance + suboptimalChance |
| ElephantEye | `local_elephanteye_engine.dart` | FFI Android; map level→depth nội bộ; chưa được EngineRouter dùng |
| Pikafish remote | `remote_pikafish_engine.dart` | gửi `{fen, level: apiName}` |
| ELO + hạng | `cchess/lib/core/constants/elo_constants.dart` | initialElo 1000, kFactor 32/24/16, **7 RankTier** |
| ELO **chưa cập nhật** | `game_screen.dart:328`, `profile_controller.dart:98` | bot games lưu `eloDelta: 0` |
| Chọn bot | `bot_game/bot_select_screen.dart` | 5 thẻ + thẻ Đại Sư+ |
| Routing | `router/app_router.dart:182` | parse `level` → `engineLevel` + `botDifficulty` |
| **Backend engine** | `cchess-backend/src/engine-service/server.ts` | `EngineLimit = {depth|movetimeMs}`; key theo chuỗi `level` |
| UCI driver | `cchess-backend/src/engine-service/uci_engine.ts` | chỉ set Threads/Hash/EvalFile lúc init; `go depth|movetime` |
| Types | `cchess-backend/src/engine-service/types.ts` | `EngineLimit`, `EngineBestMoveRequest` |

---

## 3. Phủ ELO bằng 3 engine (đã kết luận: đủ)

| Dải ELO | Engine | Núm vặn |
|---|---|---|
| 1000–1400 | **minimax** | depth 1–3 + `blunderRate` giảm dần (Pikafish ghì xuống dải này rất "máy móc") |
| 1400–2000 | **minimax depth cao / ElephantEye** | depth 4–6 |
| 2000–2600 | **Pikafish (giới hạn)** | `UCI_LimitStrength=true` + `UCI_Elo`, hoặc `Skill Level` 5–15 + movetime |
| 2600–2900+ | **Pikafish (gần/full)** | `Skill Level` 18–20 / movetime cao |

> ⚠️ ELO engine tự báo **rất sai** trong cờ tướng. Bảng số chỉ là điểm xuất phát; **phải calibrate bằng đấu thử** (Phase 6).

---

## 4. Sơ đồ tính điểm (xác nhận toán học)

`p` = xác suất thắng (công thức ELO chuẩn):

| Tình huống | bracket | p (≈) | Thắng/Thua | E[Δ] |
|---|---|---|---|---|
| Bot bằng ELO | `equal` | 0.50 | +10 / −10 | **0** ✅ cân ở 50% |
| Bot mạnh hơn 100 (đánh lên) | `higher` | 0.36 | +15 / −5 | **+2.2** → khuyến khích đánh lên |
| Bot yếu hơn 100 (cày bot dưới) | `lower` | 0.64 | +5 / −10 | **−0.4** → phạt nhẹ farming |

Hệ điểm cố định này **thay** công thức K-factor cho ván vs bot (giữ K-factor cho online PvP nếu cần). Hòa: đề xuất Δ=0 mọi bracket (chốt ở Phase 2). Có thiên hướng lạm phát nhẹ — chấp nhận cho MVP, để hằng số dễ chỉnh.

---

## 5. Kế hoạch theo Phase

### Phase 0 — Mô hình sức cờ + calibrate stub
**File mới:** `cchess/lib/core/chess_engine/ai/engine_config.dart`
```dart
class EngineConfig {
  final EngineSource engine;     // localMinimax | localElephantEye | remotePikafish
  final int depth;
  final int? movetimeMs;
  final int? skillLevel;         // Pikafish Skill Level 0–20
  final int? uciElo;             // Pikafish UCI_Elo (khi LimitStrength)
  final double blunderRate;      // tỉ lệ đi sai cố ý (dải thấp)
}
EngineConfig configForElo(int targetElo); // const table, dễ chỉnh
```
- Hằng số dải ELO + bảng map tách riêng (Phase 6 tinh chỉnh).
- Unit test: biên dải, đơn điệu (ELO cao → cấu hình mạnh hơn).

### Phase 1 — Engine nhận tham số sức dạng số
- `move_engine.dart`: thêm `EngineConfig? config` vào `MoveEngine.bestMove` (giữ `EngineLevel` cho hint/analysis để không phá luồng cũ).
- `bot_engine.dart` / `local_minimax_engine.dart`: lấy `depth` + `blunderRate` từ config thay vì `difficulty.settings`.
- `local_elephanteye_engine.dart`: lấy `depth`/`movetime` từ config; **wire vào `EngineRouter.local`**.
- `remote_pikafish_engine.dart`: gửi `{fen, elo, skill, movetimeMs}` thay vì `level`.
- `engine_router.dart`: `_shouldTryRemote` đổi điều kiện từ `level == grandmaster` → `config.engine == remotePikafish`.

### Phase 2 — Matchmaking + Scoring (logic thuần, test trước)
**File mới:** `cchess/lib/core/matchmaking/bot_matchmaker.dart`
```dart
enum EloBracket { lower, equal, higher } // bot −100 / = / +100
class BotMatch { final int botElo; final EloBracket bracket; }
BotMatch pickBot(int playerElo, {Random? rng}); // random + clamp sàn/trần (1000–2900)
```
**File mới:** `cchess/lib/core/matchmaking/elo_scoring.dart`
```dart
int eloDelta({required EloBracket bracket, required bool won, required bool drew});
// equal:+10/-10 · higher:+15/-5 · lower:+5/-10 · draw:0
```
- Hằng số scoring tách riêng. Test: E[Δ], biên (người chơi 1000 không ghép bot 900), hòa.

### Phase 3 — Nối ELO vào kết quả ván
- `game_screen.dart`: lưu `bracket` lúc bắt đầu ván; khi kết thúc gọi `eloDelta(...)`, truyền vào `applyGameResult(eloDelta: delta)` và `GameRecord.eloDelta`.
- `profile_controller.dart`: `applyGameResult` đã cộng `eloChess + eloDelta` — chỉ cần số thật.
- Màn kết quả: **lộ ELO bot + giải thích +/- điểm theo bracket** (theo quyết định đã chốt).

### Phase 4 — UI "Luyện tập" (ẩn danh)
- Viết lại `bot_select_screen.dart` → màn gọn: hiện **ELO hiện tại + nút "Tìm trận"** (bỏ 5 thẻ + thẻ Đại Sư+).
- "Tìm trận" → `pickBot(playerElo)` → route `/game?mode=bot&botElo=<n>&bracket=<x>`.
- Trong ván đối thủ luôn hiển thị **"Bot"** (ẩn ELO); màn kết quả mới lộ.
- `app_router.dart`: parse `botElo`/`bracket` thay `level`.
- `game_controller.dart` + `GameControllerArgs` + `game_screen.dart`: mang `int botElo` + `EloBracket` thay cho `BotDifficulty`.
- **Cờ Úp**: giữ luồng riêng (CupBotEngine không đọc quân úp được — Pikafish không phù hợp); map ELO→depth nội bộ, **không** random matchmaking.

### Phase 5 — Backend Pikafish nhận ELO/skill
- `types.ts`: mở rộng `EngineLimit` thêm `skillLevel?`, `uciElo?`; `EngineBestMoveRequest` thêm `elo?`, `skill?`.
- `server.ts` `limitForRequest`: parse + clamp `elo`/`skill`.
- **`bestMoveCacheKey` PHẢI kèm `skillLevel`/`uciElo`** (nếu không 2 bot khác ELO cùng FEN trả cùng nước). Sửa `fen.ts`.
- `uci_engine.ts` `bestMove`: trước mỗi search, set
  `setoption name Skill Level value <n>` hoặc
  `setoption name UCI_LimitStrength value true` + `setoption name UCI_Elo value <n>`,
  và **reset** về full strength sau (vì `EnginePool` tái dùng tiến trình → trạng thái dùng chung).
- `server.test.ts`: thêm test ELO/skill ảnh hưởng go-command + cache key tách biệt.
- Kiểm tra Pikafish build có hỗ trợ `UCI_LimitStrength`/`UCI_Elo` (range thực tế ~1300+); nếu không, dùng `Skill Level` làm chính.

### Phase 6 — Calibrate + dọn dẹp
- Đấu thử `configForElo` với mốc đã biết, chỉnh bảng số (`engine_config.dart` + env backend).
- **Bỏ RankTier** trong `elo_constants.dart` + mọi widget hiển thị hạng (`cchess_rank_badge.dart`, `profile_screen.dart`, `leaderboard_screen.dart`, …) → hiển thị số ELO.
- Xoá/thu gọn `BotDifficulty` (có thể giữ mỏng cho Cờ Úp); gọn `EngineLevel`.
- Cập nhật test: `bot_difficulty_test`, `engine_router_test`, `minimax_test`, `cup_bot_engine_test` + thêm test matchmaking/scoring.
- Cập nhật memory dự án + doc roadmap.

---

## 6. Rủi ro & phụ thuộc
- **Backend Pikafish strength**: bắt buộc cho dải 2000–2900. Nếu `UCI_Elo` không hỗ trợ → fallback `Skill Level` (thô hơn, cần calibrate kỹ).
- **Cache poisoning**: quên thêm strength vào cache key → bot mọi cấp đánh giống nhau. (Đã đưa vào Phase 5.)
- **Trạng thái UCI dùng chung**: quên reset → rò sức cờ giữa các request. (Đã đưa vào Phase 5.)
- **Di trú dữ liệu**: ~~thang mới dùng chung `eloChess`~~ → **đã đổi (2026-06-26):** đấu bot dùng **pool riêng `eloBot`** (+ `botGames`/`botWins`/`botLosses`/`botDraws`), client-owned + persist cloud, tách khỏi `eloChess` ranked (server-authoritative). Lý do: ván bot chạy on-device không có server xác minh → không được ghi vào `eloChess` (chống gian lận + tránh bị splash sync ghi đè). Doc cũ mới có `eloChess` sẵn vẫn không cần migrate (field mới mặc định 1000); vẫn cần clamp sàn ELO < 1000. Chi tiết bug + fix: [09](09_BACKEND_SERVER_HOAT_DONG.md) §8.
- **Bỏ RankTier** đụng nhiều widget hiển thị — Phase 6 cần quét kỹ (`grep RankTier|rankForElo`).

---

## 7. Thứ tự đề xuất triển khai
Phase 0 → 1 → 2 → 3 (lõi FE, có thể test ngay với engine hiện có) → 5 (backend, mở khoá dải cao) → 4 (UI) → 6 (calibrate + dọn). Mỗi phase là một commit/PR độc lập, chạy test xanh trước khi sang phase sau.


## 8. Công cụ Calibration (đã dựng — Phase 6)

> **Trạng thái:** UI calibration **đã code 2026-06-26** (commit `f281e87`); **đợt 2026-06-26 (sau)** chuyển từ 1 nút "Bắt đầu/Dừng" (chạy tuần tự cả 7 cặp ~45–70 phút) sang **7 nút — mỗi cặp ELO một nút, chạy từng cặp một**. Việc còn lại là **chạy đấu thử thực tế** rồi chỉnh bảng số `configForElo` ([engine_config.dart](cchess/lib/core/chess_engine/ai/engine_config.dart)) + env backend Pikafish. Đây là bước **thủ công**, không tự động hoá được vì cần đánh giá chất lượng nước cờ.

**Cách chạy:**
1. `flutter run --release --dart-define=CALIBRATION=true` (cờ `CALIBRATION` mở entry trong Settings).
2. Vào **Settings → cuộn xuống → Bot Calibration → ELO Calibration (Zone A)**.
3. Màn ([calibration_screen.dart](cchess/lib/presentation/calibration/calibration_screen.dart)) hiện **lưới 7 nút**, mỗi nút một cặp band liền kề trong Zone A (1000→1100, …, 1700→1900 — xem `kCalibrationPairs` trong [calibration_runner.dart](cchess/lib/presentation/calibration/calibration_runner.dart)). Bấm **từng nút** để chạy cặp đó 6 ván (3 đỏ + 3 đen, ~7–10 phút/cặp).
   - **Chạy từng cặp một**: trong lúc một cặp đang chạy, mọi nút khác bị **vô hiệu hoá** (chống chạy song song — CPU điện thoại không gánh nổi). Nút đang chạy chuyển thành nút **đỏ "dừng"** + spinner; bấm lại để huỷ cặp đó.
   - Cặp đã xong hiện **✔ + win%** (màu theo bảng dưới); kết quả **tích luỹ** qua nhiều lần bấm nên có thể chạy rời rạc rồi copy gộp.

**Đọc kết quả** (win% của band trên so với band dưới):

| Màu | Ý nghĩa |
|---|---|
| 🟢 Xanh (win% < 35%) | Gap ổn — bot yếu hơn đang thua đúng mức |
| 🟠 Cam (35–50%) | Gap quá nhỏ — tăng depth / giảm blunder cho band trên |
| 🔴 Đỏ (> 50%) | Đảo ngược — band trên thực ra yếu hơn band dưới, phải sửa bảng |

Nhấn icon **Copy** ở AppBar để lấy bảng số liệu dán vào tài liệu/PR calibrate.

---

## 9. Việc lớn còn lại (sau Phase 0–6 code)

- ⬜ **Calibrate bảng `configForElo` bằng đấu thử thực tế** (mục 8) — quan trọng nhất; bảng số hiện tại chỉ là điểm xuất phát.
- ⬜ **Calibrate env backend Pikafish** (`UCI_Elo`/`Skill Level`/movetime cho dải 2000–2900) cùng lúc với trên; kiểm tra build Pikafish có hỗ trợ `UCI_LimitStrength` thật.
- ⬜ **Build ElephantEye `.so` thật cho mọi ABI Android** + xác nhận FFI chạy trên thiết bị thật (hiện có fallback an toàn về minimax khi lib vắng).
- ⬜ **Test tay**: chơi vài ván mỗi dải để cảm nhận "đúng tầm", đặc biệt biên 1400/2000 (đổi engine minimax↔ElephantEye↔Pikafish).