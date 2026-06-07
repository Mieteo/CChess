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

### Phase 0 — Spike & quyết định (1–2 ngày) ⬜
**Mục tiêu:** gỡ rủi ro lớn nhất trước khi đầu tư.
- [ ] **Tải Pikafish + network** về máy dev, chạy thử bằng tay: `position startpos` → `go movetime 1000` → xem `bestmove`.
- [ ] ⚠️ **Spike A — FEN/UCI compatibility:** dựng bảng đối chiếu thế cờ ↔ FEN ↔ nước UCI giữa engine TS ([engine/index.ts](cchess-backend/src/engine/index.ts)) và Pikafish. Chốt định dạng FEN dùng chung.
- [ ] Chốt **mức tài nguyên mặc định**: ví dụ live bot `movetime 600ms`, analyze `movetime 300ms/nước`, hint `movetime 500ms`, `Threads=1`, `Hash=64–128MB`.
- [ ] Chốt gói Render cho `cchess-engine` (xem §6).

**Nghiệm thu:** có hàm chuyển đổi FEN/move + 1 test đối chiếu xanh; biết chắc Pikafish chạy đúng trên 1 thế cờ thật của app.

### Phase 1 — UCI wrapper + service engine (backend) ⬜
**Mục tiêu:** một service nói chuyện được với Pikafish, có kiểm soát tài nguyên.
- [ ] Thư mục mới `cchess-engine/` (hoặc `cchess-backend/src/engine-service/`) — quyết định mono-repo vs repo riêng.
- [ ] `uci_engine.ts` — spawn tiến trình Pikafish (`child_process.spawn`), gửi lệnh UCI, **parse `info`/`bestmove`** (xem §5.1).
- [ ] `engine_pool.ts` — **pool N tiến trình** (N = số vCPU) + **hàng đợi** + hard-timeout + huỷ tiến trình treo.
- [ ] `analysis_cache.ts` — cache theo **FEN chuẩn hoá** (LRU in-memory; sau có thể đẩy Firestore/Redis). Khai cuộc lặp nhiều → cache cứu rất nhiều CPU.
- [ ] Hàm cấp cao: `bestMove(fen, {movetime|depth})`, `evalPosition(fen)`, `analyzeGame(moves[])`.

**Nghiệm thu:** unit test (fake process) cho parser UCI + test thật gọi `bestMove(startFen)` trả về nước hợp lệ; pool không vượt số tiến trình cấu hình.

### Phase 2 — API surface + auth + rate limit (backend) ⬜
**Mục tiêu:** app gọi được, an toàn, có hạn mức.
- [ ] Endpoint (HTTP `POST` hoặc message WS — đề xuất **HTTP cho phân tích**, vì không cần realtime):
  - `POST /engine/best-move` `{ fen, level }` → `{ uci, scoreCp, depth }`
  - `POST /engine/analyze` `{ moves[] }` → `{ perMove: [{uci, scoreCp, classification}], summary }`
  - `POST /engine/hint` `{ fen }` → `{ uci, scoreCp }`
- [ ] **Xác thực Firebase** (tái dùng `verifyIdToken` như [auth.ts](cchess-backend/src/auth.ts)).
- [ ] **Rate limit + VIP gating** (⚠️ E): đếm theo uid/ngày; trả `429 {code:'quota-exceeded'}` khi hết hạn mức free.
- [ ] Phân loại nước cho AI Coach: dựa trên Δeval (blunder/mistake/inaccuracy/good/best) — ngưỡng cấu hình được.

**Nghiệm thu:** gọi 3 endpoint qua `curl` với token hợp lệ trả đúng; không token → 401; vượt hạn mức → 429.

### Phase 3 — Đóng gói & deploy (Docker + Render) ⬜
**Mục tiêu:** service engine chạy thật trên Render, tách khỏi realtime.
- [ ] **Dockerfile** multi-stage: stage build compile Pikafish (⚠️ C) + tải `pikafish.nnue`; stage runtime `node:20-slim` copy binary + nnue + service (xem §5.3).
- [ ] Thêm service `cchess-engine` vào `render.yaml` (Blueprint) — **plan ≥ Standard** (xem §6).
- [ ] Env: `PIKAFISH_PATH`, `EVAL_FILE`, `ENGINE_THREADS`, `ENGINE_HASH_MB`, `MAX_CONCURRENCY`, `DEFAULT_MOVETIME_MS`.
- [ ] Server realtime gọi sang qua URL nội bộ (Render private service networking) — **không phơi public** nếu chỉ backend gọi; nếu app gọi trực tiếp thì để public + auth.
- [ ] Health check `/health` + log `[engine]`.

**Nghiệm thu:** `bestMove` qua endpoint production trả < ~1s; service realtime KHÔNG bị ảnh hưởng khi engine đang phân tích (đo đồng hồ ván không giật).

### Phase 4 — Tích hợp app Flutter ⬜
**Mục tiêu:** UI dùng engine qua lớp trừu tượng + fallback.
- [ ] `MoveEngine` (abstract) trong `lib/core/chess_engine/` — interface chung: `Future<EngineMove> bestMove(...)`, `Future<GameAnalysis> analyze(...)`.
- [ ] `LocalMinimaxEngine` — bọc [bot_engine.dart](cchess/lib/core/chess_engine/ai/bot_engine.dart) hiện có (không sửa logic minimax).
- [ ] `RemotePikafishEngine` — gọi API Phase 2; **try remote → catch → fallback local** + cờ "đang dùng bản offline".
- [ ] `EngineRouter` — chọn engine theo ma trận §1.2 (online? VIP? tính năng nào?).
- [ ] Nối UI: nút **Gợi ý** (A5), màn **Phân tích sau ván** (nâng cấp [game_analyzer.dart](cchess/lib/core/chess_engine/ai/game_analyzer.dart) → gọi remote), màn **AI Coach** (B3).
- [ ] Attribution Pikafish (⚠️ B) trong Cài đặt/Giới thiệu.

**Nghiệm thu:** online → phân tích dùng Pikafish; tắt mạng → tự fallback minimax, không crash, có báo trạng thái.

### Phase 5 — Test & hardening ⬜
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
| Render `cchess-engine` | **~$25/tháng (Standard ~1 vCPU/2GB)** trở lên | Free/Starter (0.1–0.5 vCPU) **không đủ** cho phân tích sâu. Bắt đầu Standard, scale theo tải |
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

1. **Phase 0 (spike FEN/UCI)** — gỡ rủi ro #1, rẻ và nhanh, quyết định có nên đi tiếp.
2. **Phase 1–2** — có "bot mạnh online" + hint dùng được (giá trị thấy ngay).
3. **Phase 3** — deploy thật, đo ảnh hưởng tới service realtime.
4. **Phase 4** — nối app + fallback + AI Coach/Phân tích sau ván.
5. **Phase 5–6** — test, hardening, tối ưu chi phí.

> Có thể dừng sau Phase 4 cho bản dùng được; Phase 6 làm dần khi có user thật.

---

## 9. Liên hệ tới kế hoạch tổng

- Thay thế/định hình lại mục **Sprint 15** trong [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md): bỏ hướng "Pikafish FFI on-device" (rủi ro GPL/iOS) → dùng kế hoạch lai này.
- Sửa mô tả sai *"Fairy-Stockfish fork"* ở [`01_FEATURE_SPECIFICATION.md`](01_FEATURE_SPECIFICATION.md) và [`03_PROMPT_FEATURES_ROADMAP.md`](03_PROMPT_FEATURES_ROADMAP.md) → Pikafish là engine cờ tướng riêng (dòng dõi Stockfish), **không phải** Fairy-Stockfish.
- Engine TS port hiện có ([engine/](cchess-backend/src/engine/)) **vẫn giữ** để validate nước đi realtime — Pikafish KHÔNG thay nó, mà bổ sung mảng phân tích/bot mạnh.

---

*Tạo 2026-06-07 sau khi chốt phương án lai (offline minimax Dart + online Pikafish server-side). Bước kế tiếp đề xuất: làm Phase 0 (spike FEN/UCI) để xác nhận tính khả thi trước khi đầu tư hạ tầng.*
