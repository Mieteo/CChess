# Kế Hoạch Simulation Layer Cho CChess

> Tạo ngày: 2026-06-22
> Trạng thái: đã triển khai thông suốt Phase 1 đến Phase 6.
> Mục tiêu: xây một hệ thống "người dùng ảo" có khả năng mô phỏng hành vi người chơi thật, chạy được nhiều user đồng thời, tự động phát hiện lỗi trong backend realtime, engine, Firebase/persistence, reconnect, spectator, ELO và các workflow online dài hạn.

---

## 1. Vì Sao Cần Simulation Layer?

CChess đang hướng tới một app online lâu dài: có người chơi thật, engine, ELO, hồ sơ, spectator, reconnect, phòng chờ, chat, gợi ý và server thật. Các unit test/integration test hiện tại rất cần thiết, nhưng chưa mô phỏng được áp lực và hành vi lộn xộn của một hệ sinh thái online có nhiều người dùng cùng lúc.

Simulation Layer giúp:

- Tạo N người dùng ảo trên một máy tính để test server trước khi mở cho người dùng thật.
- Phát hiện bug realtime khó thấy bằng test tay: race condition, socket chết trong queue, room leak, timer mồ côi, double finish, reconnect sai snapshot, spectator bị biến thành player.
- Test sự tương tác giữa backend WebSocket, engine service, Firebase/persistence và client protocol.
- Chạy lặp lại được bằng `seed`, có log và replay command để tái hiện bug.
- Làm nền tảng sau này cho bot mode, engine evaluation, load/stress test, staging smoke và long-running soak.

Kết luận: Simulation Layer nên nằm trong `cchess-backend/lab`, không đưa vào app Flutter chính.

---

## 2. Nguyên Tắc Thiết Kế

1. **Nằm ngoài app Flutter chính**
   - App Flutter là sản phẩm cho người dùng.
   - Simulator là công cụ test/hệ thống.
   - Không đưa simulator vào mobile app vì khó scale, khó chạy 50-200 user và dễ lẫn với runtime sản phẩm.

2. **Dùng TypeScript + Node.js**
   - Backend hiện tại đã là TypeScript/Node.
   - `cchess-backend/lab/bot.ts` là WebSocket client giả lập có thể tái sử dụng.
   - Dễ chạy trên Windows local, GitHub Actions, VPS Linux hoặc staging runner.
   - Dễ kiểm tra Firebase bằng `firebase-admin`, gọi engine HTTP và xuất JSONL report.

3. **Simulator không chỉ là bot gửi lệnh**
   - Cần có "trí nhớ" về trạng thái kỳ vọng.
   - Cần có monitor/oracle để biết điều gì là sai.
   - Cần có log/replay để biến một lỗi ngẫu nhiên thành bug tái hiện được.

4. **Tách hành vi người dùng khỏi bộ não chọn nước**
   - `PlayerAgent` mô phỏng người dùng.
   - `MovePolicy`/`Brain` chọn nước cờ.
   - Cùng một người chơi ảo có thể dùng random, heuristic, scripted hoặc engine thật.

5. **Không để tất cả simulator dùng engine mạnh**
   - Engine mạnh tốn CPU/quota và có thể che mờ bug realtime.
   - Chỉ một tỷ lệ nhỏ simulator nên gọi Pikafish/engine thật.

---

## 3. Vị Trí Trong Repo

Thư mục chính:

```text
cchess-backend/lab/sim/
  agent.ts
  brain.ts
  brains/
    random_legal.ts
    heuristic.ts
    scripted.ts
    remote_engine.ts
  personas.ts
  world.ts
  monitor.ts
  reporter.ts
  runner.ts
  profiles.ts
  firebase_auth.ts
  firebase_probe.ts
  engine_metrics.ts
  random.ts
```

Các script trong `cchess-backend/package.json`:

```json
{
  "lab:sim": "tsx lab/sim/runner.ts",
  "lab:sim:ci": "tsx lab/sim/runner.ts --target=in-process --profile=mixed-local --users=8 --duration=20s --seed=61001",
  "lab:sim:soak": "tsx lab/sim/runner.ts --target=in-process --profile=mixed-local --users=20 --duration=2m --seed=62001",
  "lab:sim:local": "tsx lab/sim/runner.ts --target=local",
  "lab:sim:staging": "tsx lab/sim/runner.ts --target=staging",
  "lab:sim:staging-system": "tsx lab/sim/runner.ts --target=staging --profile=staging-system --verify-persistence",
  "lab:sim:test": "tsx --test lab/sim/monitor.test.ts lab/sim/brains/phase4.test.ts lab/sim/firebase_probe.test.ts"
}
```

Lệnh mục tiêu thường dùng:

```bash
npm run lab:sim -- --target=in-process --profile=mixed-local --users=20 --duration=3m --seed=123
npm run lab:sim -- --target=local --ws=ws://127.0.0.1:8080 --auth-mode=stub --users=20 --duration=60s
npm run lab:sim:ci
npm run lab:sim:soak
npm run lab:sim:staging-system -- --ws=wss://staging.example --engine-url=https://engine.example --cleanup-after
```

---

## 4. Cách Sử Dụng Sau Khi Triển Khai

Phần này là cookbook để dùng lại hằng ngày khi cần test lặp, test liên tục hoặc thêm simulator/test mới.

### 4.1. Chạy Simulator Có Sẵn

Từ thư mục backend:

```powershell
cd D:\Workspace_Flutter\Copilot\CChess\cchess-backend
npm run lab:sim:ci
npm run lab:sim:soak
```

Chạy custom trên server in-process:

```powershell
npm run lab:sim -- --target=in-process --profile=mixed-local --users=12 --duration=60s --seed=123
```

Chạy vào backend local đang mở WebSocket:

```powershell
npm run lab:sim -- --target=local --ws=ws://127.0.0.1:8080 --auth-mode=stub --users=12 --duration=60s
```

Chạy vào staging với Firebase/persistence và engine:

```powershell
npm run lab:sim:staging-system -- --ws=wss://your-staging --engine-url=https://your-engine --cleanup-after
```

Sau mỗi run, xem report tại:

```text
cchess-backend/lab/reports/<runId>/
  summary.json
  events.jsonl
  failure.md
```

Quan trọng nhất:

- `summary.json`: tổng hợp kết quả, metrics, seed, profile, số game, số lỗi.
- `events.jsonl`: log sự kiện theo dòng, dùng để lần lại flow khi fail.
- `failure.md`: chỉ xuất hiện khi fail, gom rule, roomId, agents và recent events.
- Dòng `replay:` trong output là lệnh tái hiện bằng cùng `seed` và cùng cấu hình.

### 4.2. Vòng Lặp Test Hằng Ngày

Trước khi commit thay đổi backend nhỏ:

```powershell
npm run lab:check
npm run lab:sim:test
npm run lab:sim:ci
```

Khi sửa logic realtime, reconnect, room, queue, spectator hoặc chat:

```powershell
npm test
npm run lab:sim:test
npm run lab:sim:ci
npm run lab:sim:soak
```

Khi sửa persistence, ELO, game_records hoặc Firebase auth:

```powershell
npm run lab:sim:test
npm run lab:sim:staging-system -- --ws=wss://staging.example --engine-url=https://engine.example --cleanup-after
```

Khi sửa engine integration/quota:

```powershell
npm run lab:sim -- --target=staging --profile=engine-quota --ws=wss://staging.example --engine-url=https://engine.example --engine-strict --verify-persistence --cleanup-after
```

Khi một run fail:

1. Mở `lab/reports/<runId>/failure.md`.
2. Xem rule fail, `roomId`, `agents` và recent events.
3. Copy dòng `replay:` từ output hoặc từ `summary.json`.
4. Chạy lại đúng lệnh replay đó để tái hiện.
5. Sau khi sửa bug, chạy lại `lab:sim:test`, `lab:sim:ci` và profile đã fail.

### 4.3. Chạy Liên Tục Trên GitHub Actions

`backend-ci` hiện chạy thêm:

```bash
npm run lab:sim:test
npm run lab:sim:ci
```

Workflow `.github/workflows/simulation-layer.yml` hỗ trợ:

- Nightly `realtime-soak`.
- Manual `smoke-local`.
- Manual `realtime-soak`.
- Manual `staging-system`.
- Manual `engine-quota`.
- Upload artifact `cchess-backend/lab/reports/**`.

Secrets cần cho staging/manual workflow:

```text
CCHESS_FIREBASE_SERVICE_ACCOUNT_JSON
CCHESS_FIREBASE_API_KEY
CCHESS_ENGINE_FIREBASE_ID_TOKEN
```

### 4.4. Tạo Profile Simulator Mới

Profile là cách đổi tỷ lệ người dùng ảo và brain.

File chính:

```text
cchess-backend/lab/sim/profiles.ts
```

Để thêm profile mới:

1. Thêm tên vào `SimProfileName`.
2. Tạo object `SimProfile` mới với:
   - `personaWeights`
   - `brainWeights`
   - `reconnectChance`
   - `spectatorChance`
   - `abuseChance`
   - `rematchChance`
   - `failOnEngineError`
   - `engineRequired`
   - `verifyPersistence`
3. Thêm profile vào `PROFILES`.
4. Chạy bằng:

```powershell
npm run lab:sim -- --profile=ten-profile-moi --target=in-process --users=20 --duration=2m --seed=456
```

Ví dụ nên tạo profile riêng khi cần:

- Test reconnect nặng hơn bình thường.
- Test spectator/rematch nhiều hơn.
- Test abuse/rate-limit nhiều hơn.
- Test engine quota với tỷ lệ `remote-engine` cao.
- Test staging persistence với `verifyPersistence=true`.

### 4.5. Tạo Brain Mới Cho Cách Đi Cờ

Brain là phần quyết định nước đi. Interface nằm trong:

```text
cchess-backend/lab/sim/brain.ts
```

Interface chính:

```ts
export interface MovePolicy {
  readonly name: string;
  chooseMove(ctx: MoveContext): Promise<string | null>;
}
```

Các brain hiện có:

```text
cchess-backend/lab/sim/brains/random_legal.ts
cchess-backend/lab/sim/brains/scripted.ts
cchess-backend/lab/sim/brains/heuristic.ts
cchess-backend/lab/sim/brains/remote_engine.ts
```

Để thêm brain mới:

1. Tạo file mới trong `cchess-backend/lab/sim/brains/`.
2. Implement `MovePolicy`.
3. Thêm kind mới vào `BrainKind` trong `profiles.ts`.
4. Thêm weight vào profile muốn dùng.
5. Wire kind mới trong `makeBrain()` của `world.ts`.
6. Thêm test trong `lab/sim/brains/phase4.test.ts` hoặc file test riêng.
7. Chạy:

```powershell
npm run lab:sim:test
npm run lab:sim -- --target=in-process --profile=mixed-local --users=12 --duration=60s --seed=789
```

Quy tắc tốt cho brain:

- Luôn trả về nước hợp lệ theo UCI hoặc `null`.
- Có fallback nếu không chọn được nước.
- Không để engine/HTTP call làm treo simulator.
- Nếu dùng engine thật, phải có timeout, concurrency limit và metrics.

### 4.6. Tạo Persona/Hành Vi Người Dùng Mới

Persona hiện có:

```text
casual
private-room
reconnect
spectator
abuse
```

File liên quan:

```text
cchess-backend/lab/sim/personas.ts
cchess-backend/lab/sim/profiles.ts
cchess-backend/lab/sim/world.ts
```

Lưu ý thiết kế hiện tại: persona class chủ yếu giữ identity/brain/bot. `SimWorld` là nơi điều phối flow chơi phòng, reconnect, spectator, abuse và rematch.

Để thêm persona mới:

1. Thêm kind vào `PersonaKind` trong `profiles.ts`.
2. Thêm class trong `personas.ts`.
3. Thêm weight vào profile.
4. Wire trong `makeAgent()` của `world.ts`.
5. Nếu persona là người chơi thật, cập nhật `isPlayerPersona()`.
6. Thêm flow hành vi trong `world.ts`, thường theo dạng `maybeRunX(...)`.
7. Thêm metrics vào summary nếu hành vi đó cần được đếm riêng.
8. Thêm test oracle nếu hành vi mới có rule protocol riêng.

Ví dụ persona nên thêm sau này:

- `SlowPlayer`: cố tình delay nước đi để test clock.
- `RematchHeavyPlayer`: luôn đề nghị rematch.
- `ChattySpectator`: spectator chat nhiều để test rate-limit.
- `TimeoutPlayer`: bỏ lượt hoặc disconnect dài để test timeout/grace.

### 4.7. Tạo Test Mới

Có 3 nhóm test chính:

```text
cchess-backend/lab/sim/monitor.test.ts
cchess-backend/lab/sim/brains/phase4.test.ts
cchess-backend/lab/sim/firebase_probe.test.ts
```

Chọn nơi thêm test:

- Test protocol/oracle: thêm vào `monitor.test.ts`.
- Test brain/engine behavior: thêm vào `brains/phase4.test.ts` hoặc file test brain mới.
- Test Firestore persistence/cleanup: thêm vào `firebase_probe.test.ts`.
- Test race/realtime dài: tạo profile/persona rồi chạy simulator với seed cố định.

Nguyên tắc:

- Bug cụ thể thì viết test deterministic trước.
- Bug do timing/race thì giữ seed và replay command trong issue/commit.
- Không thay simulation thành nơi duy nhất kiểm tra mọi thứ; simulation bổ sung cho unit/integration/lab/fuzz/load.

Lệnh kiểm tra chuẩn trước khi commit:

```powershell
npm run lab:check
npm run lab:sim:test
npm run lab:sim:ci
npm run lab:sim:soak
```

---

## 5. Kiến Trúc Tổng Quát

```text
Simulation Runner
  |
  +-- World
  |     +-- Bot pool
  |     +-- Room/game memory
  |     +-- Seeded random
  |     +-- Timing/scheduler
  |
  +-- PlayerAgent[]
  |     +-- CasualPlayer
  |     +-- PrivateRoomPlayer
  |     +-- ReconnectPlayer
  |     +-- SpectatorAgent
  |     +-- AbuseAgent
  |
  +-- MovePolicy / Brain
  |     +-- RandomLegalPolicy
  |     +-- HeuristicPolicy
  |     +-- ScriptedPolicy
  |     +-- RemoteEnginePolicy
  |
  +-- Monitor / Oracle
  |     +-- Protocol assertions
  |     +-- Room/socket invariants
  |     +-- Engine/quota checks
  |     +-- Firebase/persistence checks
  |     +-- Latency/error thresholds
  |
  +-- Reporter
        +-- PASS/FAIL summary
        +-- JSONL event log
        +-- Replay command
        +-- Failure bundle
```

---

## 6. Các Thành Phần Chính

### 6.1. Bot

Tái sử dụng `cchess-backend/lab/bot.ts`.

Vai trò:

- Kết nối WebSocket.
- Auth.
- Gửi command protocol: `find-match`, `create-room`, `join-room`, `move`, `chat-message`, `reconnect-room`, `spectate-room`, `resign`, `leave-room`.
- Ghi lại message server gửi về.

Không nhồi logic phức tạp vào `Bot`. `Bot` chỉ là client cấp thấp.

### 6.2. PlayerAgent

`PlayerAgent` là tầng mô phỏng người dùng.

```ts
export interface PlayerAgent {
  readonly id: string;
  readonly uid: string;
  readonly persona: string;
  start(world: SimWorld): Promise<void>;
  tick(world: SimWorld): Promise<void>;
  stop(world: SimWorld): Promise<void>;
}
```

Persona hiện có:

- `CasualPlayer`: chơi game bình thường.
- `PrivateRoomPlayer`: tạo/join phòng riêng.
- `ReconnectPlayer`: đang chơi thì drop, reconnect trong grace.
- `SpectatorAgent`: vào xem trận, chat, thoát, xem tiếp sau rematch.
- `AbuseAgent`: gửi move sai lượt, spam chat, payload lỗi, cancel/find liên tục.

### 6.3. MovePolicy / Brain

Tách riêng "người dùng" và "cách chọn nước cờ".

```ts
export interface MoveContext {
  uid: string;
  roomId: string;
  color: 'red' | 'black';
  movesUci: string[];
  fen?: string;
  nowMs: number;
}

export interface MovePolicy {
  readonly name: string;
  chooseMove(ctx: MoveContext): Promise<string | null>;
}
```

Các brain chính:

1. `RandomLegalPolicy`
   - Chọn một nước hợp lệ bất kỳ.
   - Nhanh, rẻ, phù hợp load lớn.

2. `HeuristicPolicy`
   - Ưu tiên ăn quân, chiếu, tránh mất quân quan trọng.
   - Thông minh hơn random nhưng vẫn nhẹ.

3. `ScriptedPolicy`
   - Đi theo fixture/công thức để test case đặc biệt.
   - Phù hợp checkmate fixture, rematch, ván ngắn, ván dài, hết giờ.

4. `RemoteEnginePolicy`
   - Gọi `cchess-engine` qua HTTP.
   - Chỉ dùng cho một phần nhỏ simulator để test engine/quota/latency.

Phân bổ mặc định của `mixed-local`:

```text
random-legal: 45
scripted: 18
heuristic: 32
remote-engine: 5 nếu có engine URL, 0 nếu không cấu hình engine
```

### 6.4. SimWorld

`SimWorld` điều phối toàn bộ run:

- Seeded random.
- Danh sách agents.
- Danh sách bot/socket.
- Bộ nhớ về room/game.
- Scheduler/timing.
- Target mode: `in-process`, `local`, `staging`, `prod-smoke`.
- Event bus cho monitor/reporter.
- Persistence verification và cleanup nếu bật.

Thông tin run:

```ts
interface SimRun {
  runId: string;
  seed: number;
  target: 'in-process' | 'local' | 'staging' | 'prod-smoke';
  startedAt: string;
  users: number;
  durationMs: number;
}
```

### 6.5. Monitor / Oracle

Đây là phần quan trọng nhất. Tạo N bot mà không có oracle thì chỉ là noise generator.

Monitor phát hiện:

- Bot gửi command sai phase.
- Hai người chơi trong một room phải có màu khác nhau.
- Spectator không bao giờ được thành player.
- `game-ended` không được emit hai lần cho cùng game/agent.
- `moveCount` phải khớp số moves.
- Reconnect phải trả đúng room/moves/clock snapshot.
- Sau drain không còn room/socket/queue rác.
- Không có socket chết trong queue.
- Không có room `playing` không có người mà ngoài grace.
- Engine call không lỗi quá ngưỡng của profile.
- Firebase writes không bị thiếu, trùng hoặc double-counter.

In-process mode tái sử dụng `lab/invariants.ts` để kiểm room/socket/timer.

### 6.6. Reporter

Khi PASS:

```text
PASS sim-20260622T073445
seed: 61001
profile: mixed-local
users: 8
duration: 20000ms
games started: 78
games ended: 78
rooms after drain: 0
invariant violations: 0
protocol violations: 0
events: ...\lab\reports\sim-...\events.jsonl
replay: npm run lab:sim -- ...
```

Khi FAIL:

```text
FAIL sim-...
seed: 123
rule: game-ended-duplicate
roomId: ROOM01
agents: sim_004, sim_017
events: lab/reports/sim-.../events.jsonl
failure: lab/reports/sim-.../failure.md
```

Report files:

```text
cchess-backend/lab/reports/
  sim-.../
    summary.json
    events.jsonl
    failure.md
```

`lab/reports/` là output cục bộ và không nên commit.

---

## 7. Các Chế Độ Chạy

### 7.1. In-process Mode

Dùng server in-process như `lab/harness.ts`.

Mục tiêu:

- Nhanh.
- Lặp lại tốt.
- Không cần Firebase.
- Bắt bug realtime, room, socket, timer, queue, reconnect.

Lệnh:

```bash
npm run lab:sim -- --target=in-process --profile=mixed-local --users=20 --duration=3m --seed=123
```

Đây là mode phù hợp cho CI nhẹ.

### 7.2. Local Mode

Chạy backend local thật:

```bash
npm run dev
npm run lab:sim -- --target=local --ws=ws://127.0.0.1:8080 --auth-mode=stub --users=20 --duration=60s
```

Mục tiêu:

- Kiểm tra server local theo black-box.
- Có thể kết hợp engine local.
- Có thể dùng Firebase test project nếu cần.

### 7.3. Staging Mode

Chạy trên backend staging + Firebase staging/test project.

Mục tiêu:

- Test gần production nhưng không phá data production.
- Kiểm tra auth, persistence, ELO, game_records, quota, engine deploy.

Quy tắc:

- User ảo nên có prefix `sim_`.
- Mỗi run có `runId`.
- Có cleanup theo `runId`.
- Không dùng production Firebase cho stress/load.

Lệnh:

```bash
npm run lab:sim:staging-system -- --ws=wss://staging.example --engine-url=https://engine.example --cleanup-after
```

### 7.4. Production Smoke Nhẹ

Chỉ chạy vài user và flow an toàn.

Mục tiêu:

- Xác nhận deploy sống.
- Không stress.
- Không tạo nhiều ranked write.

Production không phải nơi load test chính.

---

## 8. Firebase Và Dữ Liệu Test

Cần có Firebase project riêng cho simulation/staging.

Quy tắc dữ liệu:

- UID simulator nên có prefix: `sim_<runId>_<index>`.
- Nếu schema production không có `runId`, reporter vẫn phải ghi `gameId`, `roomId`, `uid`.
- Có cleanup user/records theo `runId` trong staging.
- Không chạy stress trên production Firebase.

Auth mode:

- `--auth-mode=stub`: dùng cho in-process/local stub.
- `--auth-mode=custom-token`: tạo Firebase users có UID prefix, cần service account và API key.
- `--auth-mode=anonymous`: mint anonymous users qua Identity Toolkit.
- `--auth-mode=id-token-list --firebase-id-tokens=a,b,c`: dùng token có sẵn.

Biến môi trường/secrets:

```text
FIREBASE_SERVICE_ACCOUNT_JSON
GOOGLE_APPLICATION_CREDENTIALS
FIREBASE_API_KEY
CCHESS_ENGINE_TOKEN
```

Kiểm tra cần có:

- Mỗi ván ranked kết thúc chỉ tạo record một lần.
- ELO cập nhật đúng hai chiều.
- Counters `wins/losses/draws/totalGames` không double.
- Rematch tạo record riêng từng ván.
- Disconnect/timeout/resign ghi reason đúng.
- Quota engine free user bị giới hạn đúng.

Cleanup:

```bash
npm run lab:sim -- --cleanup-run-id=<runId> --cleanup-dry-run
npm run lab:sim -- --cleanup-run-id=<runId>
npm run lab:sim -- --cleanup-run-id=<runId> --cleanup-delete-user-docs --cleanup-delete-auth-users
```

Luôn chạy `--cleanup-dry-run` trước khi xóa thật nếu đang làm việc với staging shared.

---

## 9. Engine Trong Simulator

Engine được lắp vào simulator dưới dạng `MovePolicy`.

Mục tiêu ngắn hạn:

- Simulator chơi được nước hợp lệ.
- Tạo ván cờ dài/ngắn tự nhiên hơn.
- Test game lifecycle tốt hơn random move cứng.

Mục tiêu dài hạn:

- Test bot mode.
- Test engine online/offline.
- So sánh chất lượng engine.
- Test hint/analyze quota/latency.
- Hỗ trợ sau này cho tính năng huấn luyện với người chơi.

Thứ tự triển khai đã hoàn tất:

1. `RandomLegalPolicy`
   - Dùng TS engine hiện có trong `cchess-backend/src/engine`.
   - Sinh nước hợp lệ từ `XiangqiGame`.

2. `HeuristicPolicy`
   - Điểm cơ bản: ăn quân, chiếu, ưu tiên quân mạnh.
   - Không cần quá mạnh.

3. `ScriptedPolicy`
   - Fixture cho resign, rematch, reconnect và các pattern kiểm thử.

4. `RemoteEnginePolicy`
   - Gọi `cchess-engine`.
   - Giới hạn concurrency và tỷ lệ user.
   - Có timeout/fallback sang legal move.

Nguyên tắc:

- Engine failure không làm simulation fail nếu mục tiêu run là test server realtime; reporter ghi lỗi và fallback.
- Engine failure phải làm run fail nếu profile là `engine-staging` hoặc `engine-quota`.

---

## 10. Profiles Để Chạy

### 10.1. CLI Profiles

Các profile hiện có trong `lab/sim/profiles.ts`:

```text
mixed-local
engine-staging
engine-quota
staging-system
```

`mixed-local`:

- Dùng cho local/in-process.
- Tập trung realtime, room, reconnect, spectator, abuse nhẹ.
- Không bắt buộc engine.
- Không verify persistence mặc định.

`engine-staging`:

- Dùng cho staging có engine.
- Engine failure làm run fail.
- Không verify persistence mặc định.

`engine-quota`:

- Dùng cho staging có engine.
- Tỷ lệ `remote-engine` cao.
- Engine failure làm run fail.
- Phù hợp kiểm quota/latency/fallback.

`staging-system`:

- Dùng cho staging gần thật.
- Có engine.
- Verify persistence mặc định.
- Phù hợp kiểm Firebase `game_records`, ELO và counters.

### 10.2. GitHub Workflow Profiles

Workflow `.github/workflows/simulation-layer.yml` có input:

```text
smoke-local
realtime-soak
staging-system
engine-quota
```

Lưu ý: `smoke-local` và `realtime-soak` là tên profile ở workflow, được map về CLI `mixed-local`. Nếu chạy CLI trực tiếp thì dùng `--profile=mixed-local`.

---

## 11. Lộ Trình Triển Khai

### Phase 1 - Nền Móng CLI Local

Mục tiêu: chạy được N user ảo trên server in-process.

Đã làm:

- Tạo `lab/sim/runner.ts`.
- Tạo `SimWorld`.
- Tạo `PlayerAgent` interface.
- Tạo `RandomLegalPolicy`.
- Tạo player flow cơ bản.
- Ghi event JSONL.
- Summary PASS/FAIL.
- Drain cuối run và assert room sạch.

Acceptance:

```bash
npm run lab:sim -- --target=in-process --users=10 --duration=60s --seed=1
```

Kết quả cần có:

- Không invariant violation.
- Có game started/ended.
- Sau drain còn 0 room.
- Replay cùng seed cho hành vi tương đương.

### Phase 2 - Monitor/Oracle Nghiêm Túc

Mục tiêu: bot không chỉ chạy, mà biết phát hiện sai.

Đã làm:

- Protocol phase assertions.
- Room/game memory.
- Detect duplicate `game-ended`.
- Detect spectator thành player.
- Detect move count mismatch.
- Detect reconnect snapshot sai.
- Failure bundle.

Acceptance:

- Khi chèn lỗi có chủ ý vào server/test stub, simulation fail rõ rule.
- Failure có `seed`, `runId`, `roomId`, `agents`, recent events.

### Phase 3 - Personas Mở Rộng

Mục tiêu: mô phỏng nhiều hành vi người dùng hơn.

Đã làm:

- `ReconnectPlayer`.
- `SpectatorAgent`.
- `PrivateRoomPlayer`.
- `AbuseAgent`.
- `ScriptedPolicy`.
- Profile action weights.

Acceptance:

- Run 20-30 users trong 3-5 phút ổn định.
- Có reconnect, spectator, chat, resign, rematch trong summary.

### Phase 4 - Engine Brain

Mục tiêu: có nhóm simulator chơi thông minh hơn và test engine.

Đã làm:

- `HeuristicPolicy`.
- `RemoteEnginePolicy`.
- Engine timeout/fallback.
- Engine metrics: latency, error rate, cache hit.
- Profile `engine-quota`.

Acceptance:

- Một tỷ lệ nhỏ user có thể gọi engine mà không làm simulation chậm bất thường.
- Engine fail được report đúng profile.

### Phase 5 - Staging/Firebase

Mục tiêu: test ecosystem gần thật.

Đã làm:

- Staging target config.
- Firebase test credentials/auth modes.
- UID prefix `sim_`.
- Persistence verifier.
- Cleanup by `runId`.
- Report game_records/ELO/counters.

Acceptance:

- Staging run có thể tạo/kết thúc game thật.
- Verify ELO/game_records không double.
- Cleanup được dữ liệu test.

### Phase 6 - CI/Nightly

Mục tiêu: đưa simulation vào quy trình phát triển.

Đã làm:

- CI nhẹ: `lab:sim:ci`.
- Manual workflow: `realtime-soak`.
- Manual/staging workflow: `staging-system`.
- Manual engine workflow: `engine-quota`.
- Artifact upload cho report.

Acceptance:

- PR/commit không bị chậm quá mức.
- Long run có thể chạy thủ công hoặc nightly.

Trạng thái triển khai:

- `backend-ci` chạy thêm `npm run lab:sim:test` và `npm run lab:sim:ci` trên push/PR backend.
- Workflow `.github/workflows/simulation-layer.yml` chạy nightly `realtime-soak` và cho phép manual run các profile `smoke-local`, `realtime-soak`, `staging-system`, `engine-quota`.
- Tất cả workflow simulation upload `cchess-backend/lab/reports/**` làm artifact để lấy `summary.json`, `events.jsonl` và `failure.md` khi fail.
- Staging manual workflow dùng secrets `CCHESS_FIREBASE_SERVICE_ACCOUNT_JSON`, `CCHESS_FIREBASE_API_KEY` và nếu cần engine auth thì `CCHESS_ENGINE_FIREBASE_ID_TOKEN`.

Lệnh acceptance hiện tại:

```bash
npm run lab:check
npm run lab:sim:test
npm run lab:sim:ci
npm run lab:sim:soak
npm run lab:sim:staging-system -- --ws=wss://staging.example --engine-url=https://engine.example --cleanup-after
```

---

## 12. Rủi Ro Và Cách Kiểm Soát

| Rủi ro | Cách kiểm soát |
|---|---|
| Simulation quá nặng, chạy chậm | Mặc định dùng random/legal/heuristic, engine chỉ chiếm tỷ lệ nhỏ |
| Lỗi engine làm nhiều test false fail | Tách profile realtime và profile engine |
| Data staging bị rác | Gắn `runId`, UID prefix `sim_`, có cleanup |
| Bug ngẫu nhiên khó tái hiện | Bắt buộc seed + JSONL event log + replay command |
| Production bị ảnh hưởng | Không stress production, ranked-write opt-in |
| Bot quá máy móc, không giống người | Thêm persona + delay ngẫu nhiên + scripted behavior |
| Reporter quá ít thông tin | Failure bundle gồm roomId, agents, recent events, messages |

---

## 13. Định Nghĩa Thành Công

Simulation Layer được xem là có giá trị khi:

- Chạy được 20-50 người dùng ảo trên máy local.
- Có thể phát hiện lỗi tự động, không cần đọc log bằng mắt mới biết.
- Mỗi lỗi có seed/replay để tái hiện.
- Có ít nhất 3 persona: casual, reconnect, spectator.
- Có ít nhất 2 brain: random/legal và heuristic/scripted.
- Có summary metrics rõ ràng.
- Có thể chạy staging với Firebase test project.
- Sau mỗi run, hệ thống biết xác nhận "clean slate" hoặc chỉ ra rõ thứ còn sót.

Trạng thái hiện tại: các tiêu chí cốt lõi đã đạt sau Phase 1-6.

---

## 14. Việc Không Làm Ngay

Chưa nên làm trong MVP:

- Không viết simulator app Flutter riêng.
- Không chạy 100% user bằng Pikafish.
- Không load test production.
- Không thay unit/integration test hiện có bằng simulation.
- Không xây dashboard đẹp trước khi CLI/reporter ổn định.
- Không đưa Android/iOS vào việc tạo N user ảo; mobile chỉ dùng cho một số test native/UI thật.

---

## 15. Ghi Chú Liên Kết Với Hệ Thống Hiện Có

Thành phần hiện có được tái sử dụng:

- `cchess-backend/lab/bot.ts`: client WebSocket giả lập.
- `cchess-backend/lab/harness.ts`: server in-process với timing ngắn.
- `cchess-backend/lab/invariants.ts`: bất biến room/socket/timer.
- `cchess-backend/lab/fuzz.ts`: ý tưởng seeded random + history replay.
- `cchess-backend/lab/load.ts`: ý tưởng bring up/drain nhiều game.
- `cchess-backend/lab/smoke.ts`: black-box target staging/prod.
- `cchess-backend/src/engine`: Xiangqi rules, FEN, UCI, legal move generation.
- `cchess-backend/src/engine-service`: engine HTTP target cho `RemoteEnginePolicy`.

Simulation Layer là tầng tổng hợp các điểm mạnh này, không thay thế chúng.
