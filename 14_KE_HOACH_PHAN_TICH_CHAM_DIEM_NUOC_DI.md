# 14 — Kế hoạch: Phân tích & Chấm điểm nước đi (Game Review v2)

> Trạng thái: **P0 ✅** (2026-07-02, tắt AI đánh giá Cờ Úp + banner). **P4a Pikafish Offline ✅** (2026-07-03, §3.4). **P1 ✅ + P2 ✅** (2026-07-03, §3.5 & §6) — còn P3 (phục bàn Cờ Úp) và phần nghiệm thu trên server/thiết bị thật.
> Phạm vi: Frontend (Flutter) + Backend (Node engine-service / Pikafish).
> Nguồn gốc: 5 yêu cầu của người dùng về mục "Kỳ phổ của tôi → Phục bàn" (bug Cờ Úp, tắt AI eval Cờ Úp, độ chính xác chấm điểm, biểu đồ điểm số, phân loại nước đi).

---

## 1. Tóm tắt 5 yêu cầu & trạng thái

| # | Yêu cầu | Trạng thái | Ghi ở |
|---|---|---|---|
| 1 | Phục bàn Cờ Úp bị lỗi (quân ngửa hết, highlight chạy nhưng quân đứng im) | Đã tìm ra nguyên nhân gốc; sửa triệt để ở **P3** (cần đổi schema lưu trữ). Mitigation P0: banner cảnh báo | §4 |
| 2 | Tắt nút "AI đánh giá" cho ván Cờ Úp | ✅ **XONG (P0)** | §5 |
| 3 | Độ chính xác chấm điểm cờ ngửa thấp — engine gì? online hay local? nên đầu tư server hay local? | Trả lời đầy đủ + khuyến nghị; sửa ở **P1** | §2, §3 |
| 4 | Biểu đồ đường điểm số cả ván (kiểu Thiên Thiên Tượng Kỳ, ±29999 khi sắp thắng) | Kế hoạch **P2** (làm song song được với P1) | §6 |
| 5 | Phân loại nước đi (xuất sắc/tốt/yếu/thua ngay) theo chênh lệch điểm | **Đã có sẵn trong code** — cần cải thiện độ tin cậy (P1) + nâng cấp thuật toán (P4) | §7 |

---

## 2. Hiện trạng kỹ thuật — trả lời câu hỏi 3

### 2.1. Kiến trúc pipeline phân tích hiện tại

```
Màn Phục Bàn / Gia Sư AI
        │  toggleCoachMode() / analyze()
        ▼
EngineRouter.analyze()                    (engine_router.dart)
        │
        ├── ƯU TIÊN: RemotePikafishEngine ──► POST /engine/analyze
        │      timeout HTTP = 3 GIÂY (!)        │  engine-service (Node, Render)
        │                                       │  chạy binary PIKAFISH thật qua UCI
        │                                       │  mỗi nước = 2 lần search × 300ms
        │                                       │  quota free: 3 lần phân tích/ngày, VIP bỏ giới hạn
        │
        └── FALLBACK (mọi lỗi, kể cả timeout): LocalElephantEye.analyze()
               │  ElephantEye KHÔNG có entrypoint analyze
               ▼
            GameAnalyzer minimax thuần Dart, DEPTH = 2   ← rất nông
```

- **Engine chấm điểm "chính danh"**: **Pikafish** (NNUE, sức cờ siêu đại kiện tướng) chạy **online** trên engine-service (`cchess-backend/src/engine-service/`). Mỗi nước đi được chấm bằng 2 lần search: eval vị trí *trước* nước đi (tìm nước tốt nhất) và eval vị trí *sau* nước đi thật → `centipawnLoss` → phân loại.
- **Engine fallback**: minimax **thuần Dart depth 2** chạy **local trên máy** (kể cả Android có ElephantEye native, vì native không có API analyze — xem `local_elephanteye_engine.dart:83`).

### 2.2. Vì sao độ chính xác thấp — chẩn đoán

1. **[Nguyên nhân chính] Client timeout 3 giây** (`engine_providers.dart:30`) trong khi server cần ~0.6s/nước (2 search × 300ms): ván 40 nước ≈ **24 giây** phía server → request **hầu như luôn timeout** → `EngineRouter` **âm thầm** rơi về minimax depth 2. Người dùng tưởng đang được Pikafish chấm nhưng thực tế gần như luôn là minimax nông.
2. **Minimax depth 2 quá nông** — với cờ tướng, depth 2 không thấy được đòn bắt quân 2 nước, chấm điểm gần như nhiễu; ngưỡng phân loại (15/60/150/300cp) trở nên vô nghĩa.
3. **Không hiển thị nguồn phân tích** — UI không phân biệt "phân tích Pikafish" và "phân tích offline", người dùng không biết kết quả đang xem thuộc loại nào.
4. **Nhiễu so sánh phía backend**: eval "best" và eval "actual" đến từ 2 lần search độc lập (mỗi lần 300ms) — độ sâu đạt được có thể lệch nhau, tạo sai số vài chục cp, đủ đổi nhãn `excellent` ↔ `good`.
5. **Analyzer local lệch depth**: search nước tốt nhất ở depth 2 nhưng eval sau nước thật ở depth 1 (`game_analyzer.dart:234-242`) — so sánh không đối xứng.

### 2.3. Trả lời trực tiếp: online hay local, nên đầu tư gì?

**Câu trả lời hiện trạng**: *thiết kế* là online (Pikafish server) có fallback local; *thực tế vận hành* thì do bug timeout, đa số phân tích chạy local (minimax depth 2) trên điện thoại.

**Khuyến nghị: sửa và dùng đường SERVER làm chủ lực, giữ local làm fallback có dán nhãn.** Lý do:

| Tiêu chí | Server (Pikafish) | Local điện thoại |
|---|---|---|
| Chất lượng chấm điểm | ★★★★★ NNUE, chuẩn "sự thật" | ★★☆ ElephantEye depth 8 (chỉ Android, chưa có API analyze); minimax depth 2 gần như nhiễu |
| Chi phí tiền | Instance đã thuê sẵn cho bot ladder — **chi phí biên gần bằng 0** ở quy mô hiện tại | 0 đồng |
| Chi phí pin/nhiệt/thời gian user | Không | Cao nếu muốn chất lượng (phân tích 60 nước ở depth cao = nhiều phút, máy nóng) |
| Kiểm soát tải | Đã có sẵn quota 3 analyze/ngày + VIP + cache theo position | Không cần |
| Offline | Không | Có |
| Công sức triển khai | **Thấp** — hạ tầng đã có, chỉ sửa giao thức timeout | Cao — port Pikafish FFI (iOS+Android), kèm NNUE ~45MB tải về |

- **Bây giờ (P1)**: sửa giao thức client-server (job bất đồng bộ hoặc timeout riêng dài cho analyze) — tận dụng toàn bộ hạ tầng đã trả tiền (engine-service + quota + VIP + cache). Chi phí server kiểm soát được: 1 ván 60 nước ≈ 36s CPU; free tier 3 ván/ngày/user → 1 instance phục vụ hàng trăm user/ngày; quá tải thì thêm queue tuần tự (analyze không cần realtime).
- **Sau này (P4, tùy chọn)**: nghiên cứu Pikafish on-device qua FFI (giống pattern ElephantEye đã có) cho VIP/offline — binary hỗ trợ ARMv8 dotprod chạy tốt trên điện thoại đời 2020+, nhưng phải phân phối file NNUE ~45MB và chấp nhận nóng máy. **Không nên làm trước khi đường server ổn định** vì tốn công lớn mà chất lượng vẫn thua server.

---

## 3. P1 — Sửa độ chính xác chấm điểm cờ ngửa (server path)

### 3.1. Backend (`engine-service`)

1. **API phân tích bất đồng bộ** (chọn phương án A; B là biến thể đơn giản hơn):
   - **A. Job API**: `POST /engine/analyze-jobs` → `{jobId}`; worker phân tích tuần tự; `GET /engine/analyze-jobs/:id` → `{status, progress, perMove[đã xong], summary?}`. Client poll 1–2s/lần, hiển thị % thật và **kết quả từng phần** (nước đã chấm hiện badge ngay).
   - B. Giữ endpoint đồng bộ nhưng client đặt timeout riêng = `moves.length × 0.8s + 10s` (sửa 1 dòng — có thể ship trước như hotfix).
2. **Giảm nửa số search**: vị trí *sau* nước i chính là vị trí *trước* nước i+1 — vòng lặp hiện search 2 lần/nước, viết lại để **1 search/vị trí** (dùng lại kết quả), tổng thời gian giảm ~50% (cache position hiện tại đã đỡ phần nào nhưng không đảm bảo).
3. **Trả thêm dữ liệu cho biểu đồ (phục vụ P2)**: mỗi phần tử `perMove` thêm `evalAfterCp` — eval vị trí sau nước đi, **quy ước góc nhìn Đỏ** (dương = Đỏ ưu, âm = Đen ưu), và `mateIn` (số nước chiếu hết, âm nếu Đen chiếu hết). Encoding mate: `±(30000 − ply_đến_mate)` → khớp trực giác "+29999 là Đỏ sắp thắng không gì cản nổi" của Thiên Thiên Tượng Kỳ.
4. **Tăng chất lượng search**: `ANALYZE_MOVETIME_MS` 300 → 500ms (đo lại tổng thời gian sau khi đã giảm nửa số search); cân nhắc `depth` tối thiểu 12 thay vì movetime thuần để eval ổn định giữa các vị trí.
5. Quota: tính 1 lần trừ quota cho mỗi **job** (không phải mỗi poll).

### 3.2. Flutter

1. `RemotePikafishEngine.analyze` chuyển sang job API (hoặc timeout dài — phương án B).
2. **Dán nhãn nguồn phân tích** trong `GameAnalysis` (`source: remotePikafish | localMinimax`): UI Coach strip hiện "Phân tích Pikafish ⚡" hoặc "Phân tích nhanh offline (kém chính xác)". **Cấm fallback im lặng** — nếu server lỗi, hỏi người dùng: "Thử lại với server / Dùng phân tích nhanh offline".
3. Sửa analyzer local: eval trước/sau cùng depth; nâng depth mặc định 2 → 3 khi chạy isolate riêng (đo thời gian thực tế trên máy tầm trung).
4. **Lưu kết quả phân tích vào record** (xem §9.1) — chấm 1 lần, xem lại không tốn quota.

### 3.3. Tiêu chí nghiệm thu P1
- Ván 60 nước phân tích xong bằng **Pikafish thật** (log server xác nhận), progress hiển thị mượt, không rơi fallback im lặng.
- Cùng một ván phân tích 2 lần → phân loại từng nước giống nhau ≥ 95% (kiểm soát nhiễu).
- Ván mẫu có blunder rõ ràng (mất Xe không đền) → nước đó bị gắn `blunder`, các nước khai cuộc phổ thông không bị gắn `mistake` oan.

### 3.4. ✅ P4a — Pikafish Offline (ĐÃ TRIỂN KHAI 2026-07-03)

Theo quyết định của người dùng, engine Pikafish chạy ngay trên thiết bị được triển khai **trước** P1, phục vụ 2 mục đích: (a) máy khỏe tự gánh phân tích khi server quá tải/mất mạng; (b) nền tảng cho bot offline mạnh sau này.

**Kiến trúc:**

- Pikafish là chương trình UCI độc lập → chạy như **tiến trình con** (`Process.start`), không FFI. Binary Android chính thức (release Pikafish-2026-01-02, sẵn trong `cchess-backend/engine/Android/`) đóng gói thành `jniLibs/arm64-v8a/libpikafish.so` + `libpikafish_dotprod.so` (~3.5MB); runtime đọc `/proc/cpuinfo` chọn bản dotprod nếu CPU hỗ trợ `asimddp`. Gradle bật `jniLibs.useLegacyPackaging = true` để file được extract ra `nativeLibraryDir` (lấy qua MethodChannel `cchess/pikafish` trong MainActivity.kt).
- **NNUE (~51MB) KHÔNG nhét vào APK** — tải một lần từ endpoint mới `GET /engine/nnue` của engine-service (yêu cầu đăng nhập, không tính quota), pin **SHA-256** (`AppConstants.pikafishNnueSha256`) đảm bảo đúng bản khớp binary. UI: Cài Đặt → mục "AI Offline" (tải/tiến độ/gỡ).
- **Router 3 tầng** (`engine_router.dart`): remote Pikafish → **offline Pikafish** (khi đã cài, chỉ cho request cần full-strength: hint/analysis/band ELO cao) → ElephantEye/minimax. Bot band thấp giữ nguyên minimax cho "dễ thua" như thiết kế cũ. `analyze()` giờ fallback qua offline Pikafish trước khi rơi về minimax depth 2 — **độ chính xác phân tích khi mất server tăng vọt với người đã cài NNUE**.
- Lớp code: `pikafish/uci_client.dart` (protocol UCI thuần Dart, test được), `pikafish_local_engine.dart` (`MoveEngine`: bestMove + MultiPV blunder giống server + analyze **1 search/vị trí** — đúng thiết kế §3.1.2), `pikafish_support.dart` (conditional io/stub, web an toàn), gate máy khỏe `isStrongDevice()` (≥6 nhân + ≥5GB RAM qua MethodChannel).
- Giấy phép: dialog attribution cập nhật — binary GPL-3.0 không sửa đổi, chạy tiến trình riêng biệt; NNUE thuộc official-pikafish/Networks (có điều khoản thương mại riêng — **cần rà soát trước khi phát hành thương mại**).

**Test:** 14 unit test (UCI parse, MultiPV blunder, analyze chain, crash-restart) + **2 integration test chạy binary Pikafish THẬT** (`pikafish_real_binary_test.dart`, gate bằng env `PIKAFISH_TEST_BINARY`/`PIKAFISH_TEST_NNUE`) — đã pass trên Windows với binary + NNUE trong repo. Backend: 2 test mới cho `/engine/nnue`, tổng 179/179.

**Còn lại (chưa xong):**
- Chưa build/chạy thử APK trên **thiết bị Android thật** — cần verify: extraction jniLibs, quyền exec, MethodChannel, tốc độ search thực tế, nhiệt/pin.
- iOS không hỗ trợ (không spawn được tiến trình con) — giữ đường remote.
- Deploy engine-service mới (route `/engine/nnue`) lên Render trước khi app dùng được nút tải.
- Cân nhắc chính sách: tự động đề xuất bật AI Offline cho máy khỏe (`isStrongDevice()` đã có, chưa nối vào onboarding/upsell).

### 3.5. ✅ P1 — ĐÃ TRIỂN KHAI (2026-07-03)

Toàn bộ §3.1–3.2 đã code xong, test xanh (backend 186/186, Flutter 403/403):

**Backend:**
- `POST /engine/analyze-jobs` (202 → `jobId`) + `GET /engine/analyze-jobs/:id` (snapshot: `status/progress/perMove` từng phần + `summary`) — store in-memory (`analyze_jobs.ts`), TTL 10 phút, 1 job sống/người dùng (submit trùng → 409 **không mất quota** — job được tạo trước, quota trừ sau), cap 4 job toàn cục (`MAX_ANALYZE_JOBS`). Endpoint cũ `/engine/analyze` giữ nguyên cho tương thích.
- `analysis.ts` viết lại: **1 search/vị trí** (N nước = N+1 search, giảm ~50% chi phí), nước kết thúc ván không cần search (±29999 trực tiếp), progress callback.
- `perMove[].evalAfterCp` mới: eval sau mỗi nước **góc nhìn Đỏ** — series cho biểu đồ P2. **Mate encoding thống nhất ±(30000−n)**: `uci_parser.ts` đổi từ quy ước cũ 100000-based; backend + app + chart giờ cùng một thang điểm kiểu Thiên Thiên Tượng Kỳ.
- `ANALYZE_MOVETIME_MS` mặc định 300 → **500ms**.

**Flutter:**
- `RemotePikafishEngine.analyze` submit job rồi poll ~0.9s/lần (deadline 2s/nước + 60s); server cũ chưa có job API (404) → tự rơi về endpoint cũ với **timeout theo độ dài ván** (0.8s/nước + 10s) thay vì 3s cố định — hết cảnh timeout → minimax im lặng.
- `MoveEngine.analyze` thêm `onProgress` (tiến độ thật, hiển thị %) + `allowWeakFallback`; `GameAnalysis.source` + `MoveAnalysis.evalAfterCp`.
- **Cấm fallback im lặng**: màn phục bàn gọi analyze ở chế độ strict — server & Pikafish offline đều fail thì hiện thẻ lỗi với 2 lựa chọn "Thử lại" / "Phân tích nhanh (offline, kém chính xác)"; hết quota thì gợi ý VIP/AI Offline. Kết quả luôn kèm dòng "Nguồn: Pikafish (máy chủ) / Pikafish Offline / Phân tích nhanh".
- **Cache phân tích** (`AnalysisCacheRepository`, Hive box `cchess_game_analysis`): kết quả nguồn mạnh lưu theo `GameRecord.id` — phân tích 1 lần, mở lại xem miễn phí, không tốn quota; kết quả minimax cố tình không cache.

**Còn lại của P1:** nghiệm thu §3.3 cần server đã deploy (route mới chưa lên Render); analyzer local vẫn depth 2 (nâng 3 + isolate riêng để sau); kết quả từng phần (partial perMove) server đã trả nhưng UI chưa vẽ dần.

---

## 4. Bug phục bàn Cờ Úp — nguyên nhân gốc & kế hoạch sửa (P3)

### 4.1. Chuỗi nguyên nhân (đã xác minh trong code)

1. Cờ Úp trong app dùng **bàn xuất phát chuẩn** (`Board.initial()`) + map `_hiddenAssignments` giữ **danh tính thật bị xáo trộn** của từng quân úp (`xiangqi_cup_game.dart:62-75, 288-302`). Vị trí xuất phát *đúng là* giống cờ thường — cái ngẫu nhiên là danh tính bên dưới mỗi quân úp.
2. Khi lưu kỳ phổ, `game_screen.dart:354` ghi `startingFen: kInitialFen` (FEN cờ ngửa chuẩn) + nước đi UCI dạng from-to. **Map quân úp và danh tính lật ra không được lưu ở bất cứ đâu** (`toFen()` của Cờ Úp cũng chỉ ghi placement nhìn thấy).
3. Màn phục bàn dựng lại ván bằng `XiangqiGame.fromFen` — **luật cờ ngửa** (`replay_controller.dart:205`), nên: mọi quân hiện **ngửa** ở vị trí chuẩn; đến nước đi mà quân đã lật thành danh tính khác (ví dụ ô Pháo lật ra là Mã rồi đi nước Mã), `isValidMove` trả false → `_rebuildBoardAt` **break im lặng** → bàn cờ đóng băng, trong khi con trỏ move-list và ô vàng highlight (`_moveAt` vẫn trả về Move nếu ô xuất phát tình cờ có quân) tiếp tục chạy. **Khớp 100% mô tả lỗi.**

### 4.2. Hệ quả cần chấp nhận
- **Kỳ phổ Cờ Úp đã lưu từ trước KHÔNG THỂ phục dựng chính xác** — dữ liệu lật quân đã mất vĩnh viễn. Chỉ có thể hiển thị banner "phục bàn không đầy đủ" (P0 đã thêm) hoặc ẩn replay chi tiết cho record cũ.

### 4.3. Thiết kế sửa (P3)

1. **Mở rộng `GameRecord`** (tương thích ngược — field mới nullable):
   - `variant: 'standard' | 'cup'` (suy từ `mode` cho record cũ);
   - `cupHiddenFen`: serialize map vị trí→danh tính thật lúc khai cuộc (hoặc `cupSeed` nếu dùng shuffle theo seed — **khuyến nghị lưu map tường minh**, không phụ thuộc thuật toán shuffle giữa các version);
   - `cupReveals: List<String?>` song song với `moves`: danh tính lật ra ở nước thứ i (null nếu nước đó không lật). Thực tế `XiangqiCupGame.history` đã có sẵn `moved`/`captured` là danh tính thật — chỉ việc serialize khi lưu.
2. **`CupReplaySession`**: phát lại bằng `CupRules` + dữ liệu reveal; mỗi ply biết chính xác quân nào còn úp, quân nào đã lật thành gì. Board hiển thị trạng thái úp/ngửa đúng từng ply (tái dùng render quân úp sẵn có của `chess_board.dart`).
3. **`ReplayController`** chọn session theo `variant`; record Cờ Úp cũ (không có `cupReveals`) → giữ banner + chỉ hiện move-list, không phát lại bàn cờ.
4. **Sửa triệu chứng "highlight chạy, quân đứng im" cho MỌI variant**: khi `_rebuildBoardAt` gặp nước không hợp lệ thì dừng `currentPly` tại đó và hiện thông báo "Kỳ phổ lỗi từ nước N" thay vì để slider chạy tiếp.

### 4.4. Test P3
- Round-trip: chơi ván Cờ Úp seed cố định → lưu → load → phát lại từng ply, so sánh board + trạng thái úp với ván gốc (so `debugHiddenPieceAt`).
- Record Cờ Úp legacy (không reveal data) → mở replay không crash, hiện đúng banner, không hiện nút AI.
- Record cờ ngửa bị hỏng dữ liệu (nước không hợp lệ giữa chừng) → dừng đúng nước lỗi kèm thông báo.

---

## 5. Tắt AI đánh giá cho Cờ Úp — ✅ ĐÃ LÀM (P0, 2026-07-02)

Nước đi trong Cờ Úp là quyết định dưới **thông tin không hoàn hảo** (imperfect information) — engine full-information sẽ chấm "sai lầm" cả những nước hợp lý về kỳ vọng. Chấm điểm đúng đắn đòi hỏi mô phỏng phân phối danh tính quân còn úp (rất tốn kém) → **đồng ý loại khỏi scope**, tắt toàn bộ điểm vào:

| Điểm vào | File | Thay đổi |
|---|---|---|
| Nút AI Coach ở màn Phục Bàn | `game_replay_screen.dart` | Ẩn khi `record.isCupMode`; thêm banner cảnh báo phục bàn Cờ Úp |
| `toggleCoachMode`/`runAnalysis` | `replay_controller.dart` | No-op cho record Cờ Úp (chặn tầng logic) |
| Nút "Gia sư AI" trong danh sách kỳ phổ | `game_history_screen.dart` | Ẩn cho record Cờ Úp |
| Màn `/ai-coach/:id` mở trực tiếp | `ai_coach_screen.dart` | Hiện thông báo "Cờ Úp chưa hỗ trợ Gia Sư AI" |
| Provider "ván gần nhất" cho coach | `ai_coach_controller.dart` | Lọc bỏ ván Cờ Úp |
| Gợi ý AI trong ván Cờ Úp đang chơi | `game_screen.dart:240` | (đã chặn từ trước) |

Gate tập trung: `GameRecord.isCupMode` / `supportsAiAnalysis` (`game_record.dart`). Test: `test/replay/replay_controller_test.dart` (2 test mới). **Toàn bộ suite 377/377 pass.**

---

## 6. P2 — Biểu đồ điểm số cả ván (làm song song với P1 được)

> ✅ **ĐÃ TRIỂN KHAI bản đầu (2026-07-03)**: widget `EvalChart` (`lib/widgets/chess/eval_chart.dart`, CustomPaint — không thêm dependency) hiện trong coach mode ở màn Phục Bàn: series `evalAfterCp` góc nhìn Đỏ, nửa trên nhuộm đỏ/nửa dưới đen, clamp hiển thị ±1500cp (mate ép sát mép), đường eval bắt đầu từ vạch giữa, chấm đánh dấu `mistake`/`blunder` theo màu `MoveQuality`, vạch dọc vàng theo `currentPly`, **chạm/kéo trên chart để seek** (2 chiều với slider). Còn lại: win-bar dọc cạnh bàn cờ, nhãn "M-n" cho mate, tooltip giá trị tại điểm chạm.

### 6.1. Dữ liệu
- Series `evalAfterCp[ply]` góc nhìn Đỏ từ backend (§3.1.3). Trong lúc P1 chưa xong, chart vẫn vẽ được từ analyzer local — dán nhãn "phân tích nhanh (offline)" (đúng ý người dùng: mục 4 không cần chờ mục 3 hoàn hảo).
- Quy ước hiển thị: điểm dương = Đỏ ưu (đúng quy luật người dùng nêu: +29999 Đỏ thắng chắc, −29999 Đen thắng chắc). Mate hiển thị "M-n" và vẽ kịch trần đồ thị.

### 6.2. UI (màn Phục Bàn)
- **Line/area chart** (package `fl_chart`): trục x = ply, y = eval clamp ±2000cp (vùng mate vẽ sát mép + nhãn M-n); nửa trên tô đỏ nhạt (Đỏ ưu), nửa dưới tô đen nhạt.
- **Đồng bộ 2 chiều với replay**: vạch dọc theo `currentPly`; chạm/kéo trên chart → `controller.seek(ply)`.
- Chấm tròn màu tại các nước `mistake`/`blunder` (dùng màu `MoveQuality` sẵn có) — nhìn 1 giây thấy ngay khúc quanh trận đấu.
- **Win-bar dọc** cạnh bàn cờ (như Thiên Thiên Tượng Kỳ / chess.com): tỉ lệ đỏ-đen theo eval hiện tại, animate khi seek.

### 6.3. Test P2
- Unit: mapping eval→tọa độ (clamp, mate, ván 0 nước, 1 nước); seek từ chart cập nhật đúng ply và ngược lại.
- Golden/widget test cho chart với series mẫu (ván thắng đảo chiều 2 lần).
- Manual: ván 100+ nước không giật khi kéo slider nhanh.

---

## 7. Mục 5 — Phân loại nước đi: đã có gì, cải thiện gì

**Đã có sẵn** (cả backend `analysis.ts` lẫn local `game_analyzer.dart`, ngưỡng giống nhau):

| Phân loại | Điều kiện (centipawn loss) | Khớp yêu cầu người dùng |
|---|---|---|
| `best` Nước hay nhất | trùng nước engine đề xuất | "giống 100% đề xuất mạnh nhất — không giảm điểm" ✅ |
| `excellent` / `good` | ≤15 / ≤60 | "nước mạnh thông thường — giảm nhẹ" ✅ |
| `inaccuracy` / `mistake` | ≤150 / ≤300 | "nước yếu — giảm mạnh" ✅ |
| `blunder` Sai lầm lớn | >300 (cap 1000) | "rất yếu/thua ngay" — **cần bỏ cap khi dính mate** để rơi thẳng về ±29999 (P1) ✅ |

Quy luật người dùng nêu — *"điểm chỉ cộng về A khi B đi nước yếu"* — là **chính xác về lý thuyết** và code hiện hành đã tôn trọng (cpLoss bị chặn ≥ 0, nghĩa là một nước đi không bao giờ "tự cộng điểm" cho người đi; mọi cú nhảy eval có lợi cho A đều xuất phát từ sai lầm của B). Lưu ý vận hành: nhiễu search có thể tạo "tăng ảo" nhỏ trên đồ thị — xử lý bằng cách dùng **cùng một lần search cho eval-sau-nước-i và eval-trước-nước-i+1** (§3.1.2) thì chuỗi eval tự nhất quán.

**Nâng cấp đề xuất (P4)**:
1. **Win-probability thay cho cp thô** (mô hình Lichess): `WinP = 1/(1+10^(-cp/k))`, phân loại theo ΔWinP — công bằng hơn ở thế đã thắng/thua đậm (mất 200cp khi đang +1500 không phải "mistake" thật sự).
2. **Accuracy % mỗi bên** từ chuỗi ΔWinP (đang dùng trung bình scoreOut100 — thô hơn).
3. **Opening book**: nước nằm trong sách khai cuộc (đã có `opening_seed.dart`) gắn nhãn "Lý thuyết", không trừ điểm.
4. **Brilliant (!!)**: nước duy nhất giữ được thế hoặc thí quân được engine xác nhận — làm sau cùng, cần search sâu.

---

## 8. Roadmap tổng & kế hoạch test

| Phase | Nội dung | Phụ thuộc | Ước lượng |
|---|---|---|---|
| **P0** ✅ | Tắt AI eval Cờ Úp (mọi điểm vào) + banner phục bàn Cờ Úp + test | — | xong 2026-07-02 |
| **P1** ✅ | Analyze server ổn định: job API + 1 search/vị trí + `evalAfterCp` + mate ±(30000−n) + nhãn nguồn + cấm fallback im lặng + cache Hive — xem §3.5 | — | xong 2026-07-03 (còn: deploy server + nghiệm thu §3.3) |
| **P2** ✅ | Biểu đồ eval + đồng bộ seek 2 chiều + chấm blunder — xem §6 | — | xong 2026-07-03 (còn: win-bar, nhãn M-n) |
| **P3** | Schema Cờ Úp (`cupHiddenFen` + `cupReveals`) + `CupReplaySession` + xử lý record legacy + dừng-đúng-nước-lỗi cho mọi variant | — (độc lập P1/P2) | 3-4 ngày |
| **P4a** ✅ | Pikafish Offline on-device (binary jniLibs + NNUE tải 1 lần + router 3 tầng + Settings "AI Offline" + `GET /engine/nnue`) — xem §3.4 | — | xong 2026-07-03 (còn: verify trên máy thật + deploy server) |
| **P4** | Calibration: win-prob classification, opening book, telemetry fallback-rate | P1 | mở |

### Kế hoạch test xuyên suốt
- **Backend unit** (Vitest/Jest như hiện có): mate encoding ±(30000−ply); series `evalAfterCp` liên tục giữa các nước (eval-sau-i == eval-trước-i+1); job API states; quota trừ theo job. Có thể tái dùng pattern "spawn binary Pikafish thật" đã dùng khi phát hiện vụ `UCI_Elo` (doc 13 P5).
- **Flutter unit**: parse response mới; gate Cờ Úp (đã có); chart mapping; analyzer local depth đối xứng.
- **Integration/manual checklist**: ván ngắn 5 nước / dài 100+ nước / mate sớm / thua hết giờ / record Cờ Úp cũ / record Cờ Úp mới (sau P3) / mất mạng giữa chừng phân tích (phải hiện lựa chọn, không âm thầm fallback) / hết quota (hiện upsell VIP như hiện tại).
- **Nghiệm thu chất lượng chấm điểm**: lấy 3 ván mẫu có kết luận rõ (1 ván có blunder mất Xe, 1 ván đều tay, 1 ván bị chiếu hết nhanh) → kết quả phân loại phải khớp trực giác kỳ thủ; chạy 2 lần cho cùng ván → nhãn ổn định ≥95%.

---

## 9. Ý tưởng bổ sung (ngoài 5 yêu cầu)

1. **Lưu kết quả phân tích vào `GameRecord`** (kèm `analysisVersion` + nguồn engine): phân tích 1 lần, xem lại mãi mãi không tốn quota/server — giảm mạnh chi phí vận hành, mở lại màn phục bàn là có chart ngay. *Ưu tiên cao, gộp vào P1.*
2. **"Khoảnh khắc then chốt"**: nút ⏭ nhảy tới sai lầm kế tiếp; tự tóm tắt "3 bước ngoặt của ván" trên đầu màn phân tích.
3. **"Chơi lại từ đây"**: từ một nước blunder, mở bàn đấu với bot đúng vị trí đó để thử nước tốt hơn (hạ tầng bot + custom FEN đã có sẵn) — biến review thành luyện tập, đây là vòng lặp giữ chân mạnh nhất của chess.com.
4. **ELO hiệu năng của ván**: từ accuracy + độ khó đối thủ ước lượng "ván này bạn chơi như ELO ~1750" — con số gây nghiện, khớp hệ ELO ladder sẵn có (doc 13).
5. **Insight tích lũy**: thống kê loại sai lầm theo giai đoạn (khai/trung/tàn cuộc) qua nhiều ván → "bạn thường sai ở tàn cuộc Xe" → gợi ý puzzle tương ứng (nối với `CoachRecommender` sẵn có).
6. **Share card**: ảnh tóm tắt ván (accuracy 2 bên, chart mini, nước hay nhất) để chia sẻ — viral loop miễn phí.
7. **Phân tích lũy tiến**: hiện ngay bản nhanh (local/movetime thấp) rồi server refine ngầm và cập nhật badge — cảm giác tức thời mà vẫn chính xác dần.
8. **Telemetry**: log tỉ lệ fallback local, thời gian phân tích, quota usage → biết chính xác user đang nhận chất lượng nào và khi nào cần scale server.
9. **Monetization rõ ràng**: free = 3 ván phân tích/ngày ở movetime chuẩn (quota có sẵn); VIP = không giới hạn + movetime/depth cao hơn + brilliant detection. Tính năng review chính là "mồi" chuyển đổi VIP tự nhiên nhất.
