# ♟️ KẾ HOẠCH TÍCH HỢP ENGINE — Lai (Minimax offline + Pikafish server-side)

> Tài liệu sống — tạo ngày **2026-06-07**.
> Mục đích: kế hoạch chi tiết triển khai **2 engine** theo mô hình **LAI**:
> - **Offline / bot nhẹ:** engine **minimax Dart** đã có (chạy ngay trên điện thoại, không cần mạng).
> - **Online / phân tích mạnh:** engine **Pikafish** chạy **server-side** (trên backend), app gọi qua API.
> Quyết định này chốt sau khi phân tích bản quyền GPL-3.0 của Pikafish (xem lý do bên dưới) — chạy server-side để **tránh ràng buộc GPL khi phát hành app thương mại** và **tái dùng hạ tầng backend hiện có**.
> Tham chiếu: [`01_FEATURE_SPECIFICATION.md`](01_FEATURE_SPECIFICATION.md) (B3/B5/A5/A7), [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md) (Sprint 5 minimax, Sprint 15 Pikafish), [`06_KIEN_TRUC_BACKEND_THUC_DUNG.md`](06_KIEN_TRUC_BACKEND_THUC_DUNG.md), [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md), [`09_BACKEND_SERVER_HOAT_DONG.md`](09_BACKEND_SERVER_HOAT_DONG.md).

---

## 0. Quy ước trạng thái

| Ký hiệu | Ý nghĩa |
|---|---|
| ✅ | Đã làm |
| 🟡 | Đang làm / một phần |
| ⬜ | Chưa bắt đầu |
| ⚠️ | Điểm rủi ro / phải kiểm trước khi đi tiếp |

---

## 1. Tại sao lai, và mỗi engine làm gì

### 1.1. Nguyên tắc

- **Engine cờ phải tách khỏi UI và khỏi server realtime** qua một lớp trừu tượng → app/giao thức không phụ thuộc engine cụ thể, sau này thay/đổi engine không phải sửa UI.
- **Offline luôn dùng được:** mọi tính năng cốt lõi (chơi bot, gợi ý cơ bản) phải chạy được **không cần mạng** bằng minimax Dart. Pikafish chỉ **nâng cấp chất lượng** khi online.
- **Pikafish KHÔNG ship vào app.** Nó chạy trên server. App chỉ gửi thế cờ (FEN) và nhận kết quả. → app **không phình dung lượng** (không kèm file `.nnue` vài chục MB) và **không dính GPL** vào binary phát hành.

### 1.2. Ma trận định tuyến engine (engine routing)

| Tính năng | Spec | Online? | Engine dùng | Fallback khi offline / server bận |
|---|---|---|---|---|
| Bot dễ → khá (Tập Sự…Cao Thủ) | A7 | Không bắt buộc | **Minimax Dart** (đã có) | — (vốn đã local) |
| Bot rất mạnh / "Đại Sư+" | A7 | Online | **Pikafish** (`go depth/movetime` cao) | Tụt về minimax Dart mức cao nhất + báo "đang offline" |
| Gợi ý nước đi trong ván | A5 | Online ưu tiên | **Pikafish** (1 nước tốt nhất) | Minimax Dart (depth thấp) |
| Phân tích sau ván / đồ thị thế cờ | B5 | Online | **Pikafish** (eval từng nước) | `game_analyzer.dart` minimax hiện tại |
| AI Coach (chỉ lỗi, đề xuất bài tập) | B3 | Online | **Pikafish** + lớp rule-based diễn giải | Tắt coach, chỉ hiện phân tích minimax thô |
| Kiểm định bài tập tàn cục (duy nhất 1 lời giải) | B4 | Tool nội bộ | **Pikafish** (chạy lúc tạo content) | — (offline tool, không phải runtime) |

> **Quy tắc vàng:** mọi lời gọi Pikafish đều phải có đường lui (fallback) về minimax Dart hoặc "degrade gracefully", để mất mạng/treo server **không làm hỏng trải nghiệm**.

---

## 2. Bức tranh kiến trúc

```
┌─────────────────────────┐
│  📱 App Flutter          │
│  ─ UI + game state       │
│  ─ MoveEngine (abstract) │
│     ├─ LocalMinimaxEngine ──► chess_engine/ai (Dart, on-device, offline)
│     └─ RemotePikafishEngine ─┐
└──────────────────────────────┼──────────────────────────────┐
                               │ (HTTPS/WSS, Firebase auth)    │
                               ▼                               │
        ┌──────────────────────────────────────┐              │
        │  ☁️ cchess-backend (REALTIME)         │   KHÔNG chạy │
        │  server.ts: matchmaking, phòng,       │   phân tích  │
        │  clock, validate nước (engine TS port)│   nặng ở đây │
        └───────────────┬──────────────────────┘              │
                        │ gọi nội bộ (queue/HTTP)              │
                        ▼                                      ▼
        ┌──────────────────────────────────────────────────────┐
        │  ☁️ cchess-engine (ANALYSIS SERVICE) ⭐ service RIÊNG  │
        │  ─ UciEngine wrapper (spawn process)                  │
        │  ─ Pool tiến trình Pikafish + hàng đợi + cache FEN    │
        │  ─ Pikafish binary + pikafish.nnue (trong Docker img) │
        └──────────────────────────────────────────────────────┘
```

### ⭐ Quyết định kiến trúc quan trọng: **TÁCH service phân tích ra riêng**

- Server realtime ([server.ts](cchess-backend/src/server.ts)) **nhạy độ trễ** (đồng hồ tick mỗi giây, WebSocket cần phản hồi tức thì). Pikafish **vắt CPU 100% nhiều giây** mỗi lần phân tích → nếu chạy chung instance sẽ làm **giật đồng hồ và treo ván đang chơi**.
- → Triển khai Pikafish ở **một Render service riêng** (`cchess-engine`). Server realtime và app gọi sang nó qua HTTP nội bộ/queue. Hai service scale & trả tiền độc lập.
- Lợi ích phụ: service realtime vẫn ở gói rẻ; chỉ service engine mới cần CPU mạnh, dễ kiểm soát chi phí.

---

## 3. Các điểm PHẢI chốt trước khi code (⚠️)

| # | Vấn đề | Vì sao quan trọng | Việc cần làm |
|---|---|---|---|
| ⚠️ A | **Tương thích FEN & toạ độ UCI** giữa engine Dart/TS của bạn và Pikafish | Engine của bạn quy ước **row 0 = Đen ở đỉnh, row 9 = Đỏ ở đáy** (xem memory `project_xiangqi_engine`). Pikafish có quy ước FEN/toạ độ riêng. Lệch một chỗ là **phân tích sai toàn bộ** | **Spike đầu tiên:** lấy thế khởi đầu của bạn → xuất FEN → nạp vào Pikafish → cho 1 nước đã biết → so khớp toạ độ. Viết hàm `toPikafishFen()` / `fromPikafishMove()` + test đối chiếu |
| ⚠️ B | **Bản quyền GPL-3.0** | Chạy server-side (không "convey" binary cho user) → GPL **không bắt mở mã app**. Nhưng phải giữ Pikafish ở **tiến trình riêng** (không link tĩnh vào app), ghi rõ phiên bản + link nguồn | Để Pikafish trong image/repo riêng; thêm mục "Attribution & nguồn Pikafish (GPL-3.0)" trong app (màn Giới thiệu/Cài đặt) |
| ⚠️ C | **Phiên bản binary cho CPU của Render** | Binary Pikafish tối ưu theo tập lệnh (avx2/vnni…). Chạy nhầm trên CPU không hỗ trợ → crash "illegal instruction" | Trong Docker **tự build** `make ARCH=x86-64` (generic, an toàn) hoặc chọn release khớp CPU instance. Test `./pikafish` lệnh `bench` khi build |
| ⚠️ D | **Giới hạn tài nguyên mỗi yêu cầu** | Không chặn là 1 user spam phân tích làm sập service | Bound bằng `go movetime`/`go depth`, hard-timeout, hàng đợi có giới hạn, từ chối (429) khi quá tải |
| ⚠️ E | **Gating theo VIP/định mức** (B3/B5/A5) | Sprint 17 dự kiến "VIP bỏ giới hạn AI hint/Coach". Phân tích tốn tiền server → free phải có hạn mức | Mỗi user: đếm số lần hint/analyze/ngày; VIP = không giới hạn. Kiểm ở backend, không tin client |

---

## 4. Lộ trình triển khai theo giai đoạn

> Mỗi giai đoạn có **đầu ra cụ thể** + **tiêu chí nghiệm thu**. Có thể dừng sau Phase 2 nếu chỉ cần "bot mạnh online", làm tiếp Phase 4–5 cho AI Coach.

### Phase 0 — Spike & quyết định (1–2 ngày) 🟡 *(smoke thật đã có; còn đối chiếu nhiều thế cố định)*
**Mục tiêu:** gỡ rủi ro lớn nhất trước khi đầu tư.
- [x] **Pikafish thật + network đã chạy qua smoke service**: `engine-smoke` gọi `/health`, `/engine/best-move`, cache, `/engine/hint`, `/engine/analyze`; product smoke Render PASS 8/8 ngày 2026-06-20.
- [ ] ⚠️ **Spike A — FEN/UCI compatibility nâng cao:** dựng bảng đối chiếu thêm vài thế cờ cố định ↔ FEN ↔ nước UCI giữa engine TS ([engine/index.ts](cchess-backend/src/engine/index.ts)) và Pikafish. Smoke hiện đã kiểm UCI hợp lệ ở `INITIAL_FEN`, nhưng chưa đủ để kết luận chất lượng/định hướng mọi thế.
- [x] Chốt **mức tài nguyên mặc định cho smoke/prototype**: `movetime` smoke thấp, `Threads=1`, `Hash=128MB`, `MAX_CONCURRENCY=1`, quota free qua env trong `render.yaml`.
- [ ] Chốt gói Render production cho `cchess-engine` (xem §6): free đủ smoke/prototype, cần Standard trước traffic AI thật.

**Nghiệm thu:** có hàm chuyển đổi FEN/move + 1 test đối chiếu xanh; biết chắc Pikafish chạy đúng trên 1 thế cờ thật của app.

### Phase 1 — UCI wrapper + service engine (backend) 🟡 *(code + test fake-process xong 2026-06-07; còn chạy với binary thật)*
**Mục tiêu:** một service nói chuyện được với Pikafish, có kiểm soát tài nguyên.
- [ ] Thư mục mới `cchess-engine/` (hoặc `cchess-backend/src/engine-service/`) — quyết định mono-repo vs repo riêng.
- [ ] `uci_engine.ts` — spawn tiến trình Pikafish (`child_process.spawn`), gửi lệnh UCI, **parse `info`/`bestmove`** (xem §5.1).
- [ ] `engine_pool.ts` — **pool N tiến trình** (N = số vCPU) + **hàng đợi** + hard-timeout + huỷ tiến trình treo.
- [ ] `analysis_cache.ts` — cache theo **FEN chuẩn hoá** (LRU in-memory; sau có thể đẩy Firestore/Redis). Khai cuộc lặp nhiều → cache cứu rất nhiều CPU.
- [ ] Hàm cấp cao: `bestMove(fen, {movetime|depth})`, `evalPosition(fen)`, `analyzeGame(moves[])`.

**Nghiệm thu:** unit test (fake process) cho parser UCI + test thật gọi `bestMove(startFen)` trả về nước hợp lệ; pool không vượt số tiến trình cấu hình.

### Phase 2 — API surface + auth + rate limit (backend) 🟡 *(endpoint + auth + quota in-memory xong; VIP thật + quota bền vững còn lại)*
**Mục tiêu:** app gọi được, an toàn, có hạn mức.
- [ ] Endpoint (HTTP `POST` hoặc message WS — đề xuất **HTTP cho phân tích**, vì không cần realtime):
  - `POST /engine/best-move` `{ fen, level }` → `{ uci, scoreCp, depth }`
  - `POST /engine/analyze` `{ moves[] }` → `{ perMove: [{uci, scoreCp, classification}], summary }`
  - `POST /engine/hint` `{ fen }` → `{ uci, scoreCp }`
- [ ] **Xác thực Firebase** (tái dùng `verifyIdToken` như [auth.ts](cchess-backend/src/auth.ts)).
- [ ] **Rate limit + VIP gating** (⚠️ E): đếm theo uid/ngày; trả `429 {code:'quota-exceeded'}` khi hết hạn mức free.
- [ ] Phân loại nước cho AI Coach: dựa trên Δeval (blunder/mistake/inaccuracy/good/best) — ngưỡng cấu hình được.

**Nghiệm thu:** gọi 3 endpoint qua `curl` với token hợp lệ trả đúng; không token → 401; vượt hạn mức → 429.

### Phase 3 — Đóng gói & deploy (Docker + Render) 🟡 *(Dockerfile.engine + Render smoke xong; chờ production hardening)*
**Mục tiêu:** service engine chạy thật trên Render, tách khỏi realtime.
- [x] **Dockerfile** multi-stage: stage build/release Pikafish (⚠️ C) + tải `pikafish.nnue`; stage runtime `node:20-slim` copy binary + nnue + service (xem §5.3). Các fix gần đây: cài `curl`, giới hạn parallelism build, dùng release binary, cài `libatomic`.
- [x] Thêm service `cchess-engine` vào `render.yaml` (Blueprint) — hiện để **free** cho smoke/prototype; **plan ≥ Standard** trước traffic thật (xem §6).
- [x] Env smoke/prototype: `ENGINE_THREADS`, `ENGINE_HASH_MB`, `MAX_CONCURRENCY`, `DEFAULT_MOVETIME_MS`, timeout search/init/task, `MAX_MOVETIME_MS`, quota free best-move/hint/analyze.
- [ ] Server realtime gọi sang qua URL nội bộ (Render private service networking) — **không phơi public** nếu chỉ backend gọi; nếu app gọi trực tiếp thì để public + auth.
- [x] Health check `/health` + `engine-smoke` workflow thủ công cho staging/prod.

**Nghiệm thu:** product smoke `https://cchess-engine.onrender.com` PASS 8/8 ngày 2026-06-20, gồm quota `429 quota-exceeded`. Trước khi mở traffic thật vẫn cần plan Standard, quan sát latency/cold-start và chạy lại smoke sau deploy.

### Phase 4 — Tích hợp app Flutter 🟡 *(abstraction/router/bot Đại Sư+/replay + nút Gợi ý + attribution xong 2026-06-11; còn màn AI Coach B3)*
**Mục tiêu:** UI dùng engine qua lớp trừu tượng + fallback.
- [ ] `MoveEngine` (abstract) trong `lib/core/chess_engine/` — interface chung: `Future<EngineMove> bestMove(...)`, `Future<GameAnalysis> analyze(...)`.
- [ ] `LocalMinimaxEngine` — bọc [bot_engine.dart](cchess/lib/core/chess_engine/ai/bot_engine.dart) hiện có (không sửa logic minimax).
- [ ] `RemotePikafishEngine` — gọi API Phase 2; **try remote → catch → fallback local** + cờ "đang dùng bản offline".
- [ ] `EngineRouter` — chọn engine theo ma trận §1.2 (online? VIP? tính năng nào?).
- [ ] Nối UI: nút **Gợi ý** (A5), màn **Phân tích sau ván** (nâng cấp [game_analyzer.dart](cchess/lib/core/chess_engine/ai/game_analyzer.dart) → gọi remote), màn **AI Coach** (B3).
- [ ] Attribution Pikafish (⚠️ B) trong Cài đặt/Giới thiệu.

**Nghiệm thu:** online → phân tích dùng Pikafish; tắt mạng → tự fallback minimax, không crash, có báo trạng thái.

### Phase 5 — Test & hardening 🟡 *(unit/integration fake-engine + router fallback test xong; load test + giám sát chi phí còn lại)*
- [ ] Backend: unit test parser UCI (fake process), test pool/queue/timeout, test rate-limit/VIP.
- [ ] Tải thử (load test): N request đồng thời → đo độ trễ, CPU, hàng đợi; chỉnh `MAX_CONCURRENCY`.
- [ ] App: test `EngineRouter` (fake remote) — đường remote-ok và đường fallback.
- [ ] Giám sát chi phí Render + cảnh báo khi CPU/đợi vượt ngưỡng.

### Phase 6 — Tối ưu (tuỳ chọn) ⬜
- [ ] Cache phân tích khai cuộc xuống Firestore (chia sẻ giữa user).
- [ ] Warm-up tiến trình (giữ Pikafish "ấm" để bỏ chi phí khởi động mỗi request).
- [ ] Điều chỉnh `movetime` theo tải (giảm khi đông).
- [ ] Tận dụng sổ tay khai cuộc ([opening_seed.dart](cchess/lib/data/datasources/local/opening_seed.dart)) để khỏi gọi engine ở các nước đầu.

---

## 5. Chi tiết kỹ thuật (bản phác — sẽ chốt khi code)

### 5.1. Giao thức UCI với Pikafish (sketch)

```
→ uci
← id name Pikafish ... \n uciok
→ setoption name EvalFile value pikafish.nnue
→ setoption name Threads value 1
→ setoption name Hash value 128
→ isready
← readyok
→ position fen <FEN_CHUAN>            # hoặc: position startpos moves h2e2 ...
→ go movetime 600                      # hoặc: go depth 14
← info depth 12 score cp 35 ... pv h2e2 ...
← bestmove h2e2
```

- **Điểm/`score cp`** tính theo bên-tới-lượt → chuẩn hoá về **một góc nhìn cố định (vd Đỏ)** trước khi vẽ đồ thị.
- `score mate N` → quy về điểm rất lớn có dấu.
- Mỗi tiến trình **chỉ phân tích 1 thế tại 1 thời điểm** → pool + queue là bắt buộc.

```ts
// uci_engine.ts (phác)
class UciEngine {
  async bestMove(fen: string, opts: {movetimeMs?: number; depth?: number}): Promise<{uci: string; scoreCp: number; depth: number}> {
    await this.send(`position fen ${fen}`);
    const limit = opts.depth ? `depth ${opts.depth}` : `movetime ${opts.movetimeMs ?? 600}`;
    return this.go(limit); // resolve khi gặp dòng 'bestmove', kèm hard-timeout huỷ tiến trình nếu quá hạn
  }
}
```

### 5.2. App-side abstraction (sketch)

```dart
// lib/core/chess_engine/move_engine.dart
abstract class MoveEngine {
  Future<EngineMove> bestMove(String fen, {required EngineLevel level});
  Future<GameAnalysis> analyze(List<String> movesUci);
}

// RemotePikafishEngine: gọi API; nếu lỗi/timeout → ném để Router fallback
// LocalMinimaxEngine: bọc bot_engine.dart hiện có
// EngineRouter.bestMove(): online & đủ quyền → remote (try) → catch → local
```

### 5.3. Dockerfile (sketch — ⚠️ C build generic cho an toàn)

```dockerfile
# stage build
FROM debian:stable-slim AS build
RUN apt-get update && apt-get install -y git build-essential ca-certificates
RUN git clone --depth 1 https://github.com/official-pikafish/Pikafish /pf
WORKDIR /pf/src
RUN make -j build ARCH=x86-64 && make net    # 'net' tải pikafish.nnue
RUN ./pikafish bench                          # smoke test, fail sớm nếu sai CPU

# stage runtime
FROM node:20-slim
COPY --from=build /pf/src/pikafish /app/engine/pikafish
COPY --from=build /pf/src/*.nnue   /app/engine/pikafish.nnue
# ... copy service node, npm ci --omit=dev, CMD node dist/engine-service.js
```

---

## 6. Chi phí ước lượng

| Hạng mục | Ước lượng | Ghi chú |
|---|---|---|
| Bản quyền Pikafish | **$0** | GPL-3.0, miễn phí (xem ràng buộc ⚠️ B) |
| Render `cchess-engine` | **Free cho smoke/prototype; ~Standard $25/tháng trở lên cho traffic thật** | Free đã đủ để product smoke PASS, nhưng cold-start/CPU không phù hợp khi user thật dùng bot mạnh/hint/analyze thường xuyên. Bắt đầu Standard trước launch AI, scale theo tải |
| Render `cchess-backend` realtime | giữ **Free→Starter $7** | Không chạy engine nặng nên không cần mạnh |
| Firestore (cache/quota) | không đáng kể | Đếm hạn mức + cache khai cuộc |
| Dung lượng app | **+0 MB** | NNUE ở server, KHÔNG ship vào app — lợi thế của phương án lai |

> CPU/lần phân tích (tham khảo): `movetime 600ms × 1 thread` ≈ 0.6 CPU-giây/nước. Phân tích cả ván ~60 nước × 300ms ≈ ~18 CPU-giây (chạy nền). Live bot 600ms/nước là mượt.

---

## 7. Rủi ro & giảm thiểu

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| ⚠️ Lệch FEN/toạ độ → phân tích sai | Cao | Spike A trước tiên + test đối chiếu cố định |
| GPL khi phát hành thương mại | Cao | Server-side, tiến trình riêng, không link vào app, ghi attribution |
| Chi phí server tăng theo user | Trung bình | Cache FEN, bound movetime, hạn mức free + gating VIP, scale có kiểm soát |
| Engine treo / quá tải | Trung bình | Pool + queue giới hạn + hard-timeout + 429 + health check |
| Mất mạng làm hỏng UX | Trung bình | Fallback minimax Dart ở mọi điểm gọi remote |
| Crash "illegal instruction" trên Render | Trung bình | Build `ARCH=x86-64` generic + `bench` lúc build |

---

## 8. Thứ tự ưu tiên đề xuất

1. **Quota/VIP bền vững** — chuyển quota in-memory sang Firestore/Redis, reset theo ngày và bypass theo VIP trước khi mở tính năng AI cho user thật.
2. **FEN/UCI + H4 chất lượng** — thêm bộ thế cố định để đối chiếu nước UCI/Pikafish với board app; dùng làm benchmark chất lượng gợi ý sau tuning.
3. **Production hardening Render** — upgrade `cchess-engine` lên Standard khi có traffic, chạy `engine-smoke` sau mỗi deploy/config change, theo dõi latency/cold-start.
4. **AI Coach B3** — xây lớp diễn giải rule-based trên kết quả `analyze`, UI sau ván và fallback minimax khi remote lỗi.
5. **Phase 6 tối ưu** — cache bền vững, warm-up, điều chỉnh movetime theo tải.

> Có thể dừng sau Phase 4 cho bản dùng được; Phase 6 làm dần khi có user thật.

---

## 9. Liên hệ tới kế hoạch tổng

- Thay thế/định hình lại mục **Sprint 15** trong [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md): bỏ hướng "Pikafish FFI on-device" (rủi ro GPL/iOS) → dùng kế hoạch lai này.
- Sửa mô tả sai *"Fairy-Stockfish fork"* ở [`01_FEATURE_SPECIFICATION.md`](01_FEATURE_SPECIFICATION.md) và [`03_PROMPT_FEATURES_ROADMAP.md`](03_PROMPT_FEATURES_ROADMAP.md) → Pikafish là engine cờ tướng riêng (dòng dõi Stockfish), **không phải** Fairy-Stockfish.
- Engine TS port hiện có ([engine/](cchess-backend/src/engine/)) **vẫn giữ** để validate nước đi realtime — Pikafish KHÔNG thay nó, mà bổ sung mảng phân tích/bot mạnh.

---

## 10. Trạng thái triển khai sau task 2026-06-07

### 10.1. Đã triển khai trong repo

- ✅ **Backend engine service riêng** trong [`cchess-backend/src/engine-service/`](cchess-backend/src/engine-service/):
  - `server.ts`: HTTP service riêng cho `/engine/best-move`, `/engine/hint`, `/engine/analyze`, `/health`.
  - `uci_engine.ts`: wrapper UCI spawn process Pikafish, parse `info` + `bestmove`.
  - `engine_pool.ts`: pool nhiều process + queue + hard-timeout + 429 khi quá tải.
  - `analysis_cache.ts`: LRU cache theo FEN + giới hạn search.
  - `quota.ts`: hạn mức ngày theo uid cho free user; VIP hook đã có qua `isVip`.
  - `analysis.ts`: phân tích danh sách nước UCI, phân loại `best/excellent/good/inaccuracy/mistake/blunder`.
- ✅ **Entrypoint/runtime backend**:
  - [`cchess-backend/package.json`](cchess-backend/package.json): thêm `engine:start`, `engine:dev`, test engine service.
  - [`cchess-backend/Dockerfile.engine`](cchess-backend/Dockerfile.engine): build Pikafish server-side, copy binary + NNUE vào image runtime, chạy `dist/engine-service/server.js`.
  - [`render.yaml`](render.yaml): thêm service Render `cchess-engine`, tách khỏi `cchess-backend` realtime.
- ✅ **Hỗ trợ FEN cho TypeScript engine port**:
  - [`cchess-backend/src/engine/game.ts`](cchess-backend/src/engine/game.ts): thêm `XiangqiGame.fromFen()` và `toFen()` để service engine replay/analyze ván.
- ✅ **App-side abstraction Flutter**:
  - [`cchess/lib/core/chess_engine/move_engine.dart`](cchess/lib/core/chess_engine/move_engine.dart): interface `MoveEngine`, `EngineMove`, `EngineLevel`, `EngineUseCase`.
  - [`local_minimax_engine.dart`](cchess/lib/core/chess_engine/local_minimax_engine.dart): adapter minimax Dart hiện có.
  - [`remote_pikafish_engine.dart`](cchess/lib/core/chess_engine/remote_pikafish_engine.dart): HTTP client gọi service Pikafish.
  - [`engine_router.dart`](cchess/lib/core/chess_engine/engine_router.dart): route remote cho hint/analyze/grandmaster, fallback local minimax khi remote lỗi/offline.
  - [`engine_providers.dart`](cchess/lib/core/chess_engine/engine_providers.dart): Riverpod providers cho local minimax, remote Pikafish và router lai.
  - [`AppConstants.defaultEngineHttpUrl`](cchess/lib/core/constants/app_constants.dart): cấu hình URL engine qua `--dart-define=CCHESS_ENGINE_URL=...`.
- ✅ **UI/controller đã nối vào `EngineRouter`**:
  - [`game_screen.dart`](cchess/lib/presentation/game/game_screen.dart): bot move gọi `EngineRouter.bestMove(...)`; các bot cũ vẫn dùng minimax, lựa chọn **Đại Sư+** dùng Pikafish server-side và fallback minimax.
  - [`bot_select_screen.dart`](cchess/lib/presentation/bot_game/bot_select_screen.dart): thêm card **Đại Sư+ / Pikafish**.
  - [`app_router.dart`](cchess/lib/router/app_router.dart): parse `level=grandmaster` thành `EngineLevel.grandmaster`.
  - [`replay_controller.dart`](cchess/lib/presentation/replay/replay_controller.dart): AI Coach/phân tích replay gọi `EngineRouter.analyze(...)`, remote lỗi thì fallback local.
- ✅ **Test/verification đã chạy**:
  - Backend: `npm run build`, `npm test`.
  - Flutter: `flutter analyze`, `flutter test`.

### 10.2. Chưa xong / cần làm tiếp

- ✅ **Nút gợi ý in-game — DONE 2026-06-11**: nút 💡 trong `GameActionBar` (ván bot/local), `_onHint` ở [game_screen.dart](cchess/lib/presentation/game/game_screen.dart) gọi `EngineRouter.bestMove(useCase: hint)` → remote Pikafish khi online, fallback minimax + snackbar khi offline; nước gợi ý vẽ marker **xanh ngọc** trên [chess_board.dart](cchess/lib/widgets/chess/chess_board.dart) (phân biệt với marker vàng của nước cuối); hint tự xoá khi đi nước/undo/ván mới. 6 unit test trong `game_controller_test.dart`. Test tay UI: Nhóm H trong [`10_KE_HOACH_TEST.md`](10_KE_HOACH_TEST.md).
- ✅ **Attribution trong app — DONE 2026-06-11**: Cài đặt → Giới thiệu → "Engine cờ & giấy phép" (dialog nêu Pikafish GPL-3.0 chạy server-side không bundle vào app, NNUE thuộc official-pikafish/Networks có điều khoản riêng, link nguồn).
- 🟡 **Spike FEN/UCI với Pikafish thật**: smoke thật đã PASS ở `INITIAL_FEN` + analyze 1 nước hợp lệ; còn cần vài thế cờ cố định để đối chiếu nước UCI trả về với board của app và đánh giá chất lượng H4.
- ✅ **Deploy/smoke `cchess-engine` lên Render — DONE ở mức prototype 2026-06-20**: `https://cchess-engine.onrender.com` PASS 8/8 với `engine:smoke:quota`, gồm `/health`, auth probe, invalid FEN, best-move/cache, hint, analyze và quota `429 quota-exceeded`.
- ⬜ **Production readiness cho `cchess-engine`**: upgrade Standard trước traffic thật, theo dõi cold-start/latency, chạy lại `engine-smoke` sau deploy/config change.
- ⬜ **VIP thật + quota bền vững**: hiện quota là in-memory theo process; production nên dùng Firestore/Redis để không reset khi redeploy/restart.
- ⚠️ **NNUE license cho thương mại**: mã nguồn Pikafish GPL-3.0, nhưng repo chính thức `official-pikafish/Networks` ghi `pikafish.nnue` **không dùng thương mại nếu chưa được phép**. Nếu app/backend có mục tiêu thương mại, phải xin phép hoặc chọn network/engine khác có giấy phép phù hợp trước khi dùng production.

---

## 11. Lấy Pikafish thật và chạy service local

### 11.1. Nguồn chính thức

- Source/release engine: https://github.com/official-pikafish/Pikafish
- Latest release đang thấy ngày 2026-06-07: **Pikafish 2026-01-02**  
  `https://github.com/official-pikafish/Pikafish/releases/tag/Pikafish-2026-01-02`
- Asset binary release:  
  `https://github.com/official-pikafish/Pikafish/releases/download/Pikafish-2026-01-02/Pikafish.2026-01-02.7z`
- NNUE network chính thức:  
  `https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue`

### 11.2. Cách khuyến nghị cho deploy/server: Docker build từ source

Không cần tải tay binary. Image [`cchess-backend/Dockerfile.engine`](cchess-backend/Dockerfile.engine) sẽ:

1. Clone source Pikafish.
2. Build generic CPU `ARCH=x86-64`.
3. Tải NNUE bằng `make net`.
4. Chạy `./pikafish bench` để fail sớm nếu binary không chạy được.
5. Copy binary + `pikafish.nnue` sang Node runtime.

Lệnh chạy local bằng Docker:

```powershell
cd cchess-backend
docker build -f Dockerfile.engine -t cchess-engine .
docker run --rm -p 8090:8090 -e ENGINE_AUTH_DISABLED=1 cchess-engine
```

Smoke test:

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri 'http://localhost:8090/engine/best-move' `
  -ContentType 'application/json' `
  -Body '{"fen":"rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1","level":"grandmaster"}'
```

Kỳ vọng response dạng:

```json
{"uci":"...","scoreCp":...,"depth":...,"pv":[...],"cached":false}
```

### 11.3. Cách chạy local bằng binary tải tay trên Windows

1. Tải `Pikafish.2026-01-02.7z` từ release chính thức.
2. Giải nén vào ví dụ `cchess-backend\engine\pikafish-release\`.
3. Tải `pikafish.nnue` vào `cchess-backend\engine\pikafish.nnue`.
4. Chọn file `.exe` phù hợp CPU trong archive. Nếu không chắc CPU hỗ trợ AVX2/VNNI, ưu tiên binary generic/x86-64 nếu release có.
5. Set env và chạy service:

```powershell
cd cchess-backend
npm install
npm run build

$env:PIKAFISH_PATH = "F:\Flutter\Copilot\CChess\CChess\cchess-backend\engine\pikafish-release\<ten-file-pikafish>.exe"
$env:EVAL_FILE = "F:\Flutter\Copilot\CChess\CChess\cchess-backend\engine\pikafish.nnue"
$env:ENGINE_AUTH_DISABLED = "1"
$env:PORT = "8090"
npm run engine:start
```

Sau đó gọi smoke test ở mục 11.2.

### 11.4. Nối Flutter app vào service local

- Android emulator:

```powershell
flutter run --dart-define=CCHESS_ENGINE_URL=http://10.0.2.2:8090
```

- Máy thật cùng Wi-Fi:

```powershell
flutter run --dart-define=CCHESS_ENGINE_URL=http://<LAN-IP-cua-may-dev>:8090
```

Khi bật auth thật, `RemotePikafishEngine` cần `tokenProvider` lấy Firebase ID token:

```dart
RemotePikafishEngine(
  baseUri: Uri.parse(AppConstants.defaultEngineHttpUrl),
  tokenProvider: () => FirebaseAuth.instance.currentUser?.getIdToken(),
)
```

Sau đó inject vào:

```dart
EngineRouter(
  local: LocalMinimaxEngine(),
  remote: remotePikafishEngine,
  canUseRemote: () => true, // sau này thay bằng online/VIP/quota state
)
```

---

*Tạo 2026-06-07 sau khi chốt phương án lai (offline minimax Dart + online Pikafish server-side). Cập nhật 2026-06-07: đã triển khai service engine/API/pool/cache/quota cơ bản, Dockerfile engine, Flutter abstraction/router/fallback và đã nối bot/replay controller vào `EngineRouter`. Cập nhật 2026-06-11: **nút Gợi ý in-game + attribution GPL trong Cài đặt đã xong** (Phase 4 chỉ còn màn AI Coach B3 chuyên biệt); test engine-service 6/6 nằm trong `npm test` 25/25 (xem Nhóm T9 của [`10_KE_HOACH_TEST.md`](10_KE_HOACH_TEST.md)). Cập nhật 2026-06-19/20: đã thêm `npm run engine:smoke` + workflow `engine-smoke` để smoke black-box `/health`, auth, best-move/cache, hint, analyze; quota có gate riêng `npm run engine:smoke:quota` / `--quota --quota-limit=N` và regression HTTP 429 `quota-exceeded`. Product smoke quota trên Render `cchess-engine` đã PASS 8/8 ngày 2026-06-20. Bước tiếp theo là quota/VIP bền vững bằng Firestore/Redis, đối chiếu FEN/UCI nhiều thế cố định, chốt NNUE license và nâng Render plan trước traffic thật.*
