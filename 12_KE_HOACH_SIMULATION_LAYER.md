# Ke hoach Simulation Layer cho CChess

> Tao ngay: 2026-06-22  
> Muc tieu: xay mot he thong "nguoi dung ao" co kha nang mo phong hanh vi nguoi choi that, chay duoc nhieu user dong thoi, tu dong phat hien loi trong backend realtime, engine, Firebase/persistence, reconnect, spectator, ELO va cac workflow online dai han.

---

## 1. Vi sao can Simulation Layer?

CChess dang huong toi mot app online lau dai: co nguoi choi that, engine, ELO, ho so, spectator, reconnect, phong cho, chat, goi y, va server that. Cac unit test/integration test hien tai rat can thiet, nhung chua mo phong duoc ap luc va hanh vi lon xon cua mot he sinh thai online co nhieu nguoi dung cung luc.

Simulation Layer giup:

- Tao N nguoi dung ao tren mot may tinh de test server truoc khi mo cho nguoi dung that.
- Phat hien bug realtime kho thay bang test tay: race condition, socket chet trong queue, room leak, timer mo coi, double finish, reconnect sai snapshot, spectator bi bien thanh player.
- Test su tuong tac giua backend WebSocket, engine service, Firebase/persistence va client protocol.
- Chay lap lai duoc bang `seed`, co log va replay lenh dung de tai hien bug.
- Lam nen tang sau nay cho bot mode, engine evaluation, load/stress test, staging smoke va long-running soak.

Ket luan: nen xay, nhung xay theo kieu mo rong `cchess-backend/lab`, khong dua vao app Flutter chinh.

---

## 2. Nguyen tac thiet ke

1. **Nam ngoai app Flutter chinh**
   - App Flutter la san pham cho nguoi dung.
   - Simulator la cong cu test/he thong.
   - Khong nen dua simulator vao mobile app vi kho scale, kho chay 50-200 user, va de lan voi runtime san pham.

2. **Dung TypeScript + Node.js**
   - Backend hien tai da la TypeScript/Node.
   - `cchess-backend/lab/bot.ts` da la WebSocket client gia lap co the tai su dung.
   - De chay tren Windows local, GitHub Actions, VPS Linux hoac staging runner.
   - De kiem tra Firebase bang `firebase-admin`, goi engine HTTP, xuat JSONL report.

3. **Simulator khong chi la bot gui lenh**
   - Can co "tri nho" ve trang thai ky vong.
   - Can co monitor/oracle de biet dieu gi la sai.
   - Can co log/replay de bien mot loi ngau nhien thanh bug tai hien duoc.

4. **Tach hanh vi nguoi dung khoi bo nao chon nuoc**
   - `PlayerAgent` mo phong nguoi dung.
   - `MovePolicy`/`Brain` chon nuoc co.
   - Cung mot nguoi choi ao co the dung random, heuristic, scripted, hoac engine that.

5. **Khong de tat ca simulator dung engine manh**
   - Engine manh ton CPU/quota va co the lam che mo bug realtime.
   - Chi mot ty le nho simulator nen goi Pikafish/engine that.

---

## 3. Vi tri trong repo

Khuyen nghi tao them thu muc:

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
  firebase_probe.ts
  engine_probe.ts
```

Script trong `cchess-backend/package.json`:

```json
{
  "lab:sim": "tsx lab/sim/runner.ts",
  "lab:sim:ci": "tsx lab/sim/runner.ts --target=in-process --profile=mixed-local --users=8 --duration=20s --seed=61001",
  "lab:sim:soak": "tsx lab/sim/runner.ts --target=in-process --profile=mixed-local --users=20 --duration=2m --seed=62001",
  "lab:sim:local": "tsx lab/sim/runner.ts --target=local",
  "lab:sim:staging": "tsx lab/sim/runner.ts --target=staging",
  "lab:sim:staging-system": "tsx lab/sim/runner.ts --target=staging --profile=staging-system --verify-persistence",
  "lab:sim:replay": "tsx lab/sim/runner.ts --replay"
}
```

Lenh muc tieu:

```bash
npm run lab:sim -- --users=20 --duration=3m --seed=123 --target=local
npm run lab:sim -- --users=50 --duration=10m --target=staging
npm run lab:sim:ci
npm run lab:sim:soak
npm run lab:sim:staging-system -- --ws=wss://staging.example --engine-url=https://engine.example --cleanup-after
npm run lab:sim -- --run-id=sim-20260622-001 --replay
```

---

## 4. Kien truc tong quat

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
  |     +-- MatchmakingPlayer
  |     +-- PrivateRoomPlayer
  |     +-- SpectatorAgent
  |     +-- ReconnectAgent
  |     +-- AbuseAgent
  |     +-- EngineUserAgent
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

## 5. Cac thanh phan chinh

### 5.1. Bot

Tai su dung `cchess-backend/lab/bot.ts`.

Vai tro:

- Ket noi WebSocket.
- Auth.
- Gui command protocol: `find-match`, `create-room`, `join-room`, `move`, `chat-message`, `reconnect-room`, `spectate-room`, `resign`, `leave-room`.
- Ghi lai message server gui ve.

Khong nen nhoi logic phuc tap vao `Bot`. `Bot` chi la client cap thap.

### 5.2. PlayerAgent

`PlayerAgent` la tang mo phong nguoi dung.

Vi du interface:

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

Persona ban dau:

- `CasualPlayer`: tim tran, di nuoc hop le, chat thinh thoang, resign sau mot so nuoc.
- `PrivateRoomPlayer`: tao/join phong rieng.
- `ReconnectPlayer`: dang choi thi drop, reconnect trong grace, hoac reconnect muon.
- `SpectatorAgent`: vao xem tran, chat, thoat, xem tiep sau rematch.
- `AbuseAgent`: gui move sai luot, spam chat, payload loi, cancel/find lien tuc.
- `EngineUserAgent`: thinh thoang goi hint/analyze/best-move.

### 5.3. MovePolicy / Brain

Tach rieng "nguoi dung" va "cach chon nuoc co".

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

Cac brain nen co theo thu tu:

1. `RandomLegalPolicy`
   - Chon mot nuoc hop le bat ky.
   - Nhanh, re, dung cho load lon.

2. `HeuristicPolicy`
   - Uu tien an quan, tranh mat tuong, uu tien chieu, phat trien quan.
   - Khon hon random nhung van nhe.

3. `ScriptedPolicy`
   - Di theo cong thuc de test case dac biet.
   - Vi du: checkmate fixture, vong rematch, van dai, van ngan, het gio.

4. `RemoteEnginePolicy`
   - Goi `cchess-engine` qua HTTP: `/engine/best-move`, `/engine/hint`, `/engine/analyze`.
   - Chi dung cho mot phan nho simulator de test engine/quota/latency.

Khuyen nghi phan bo mac dinh:

```text
70% RandomLegal/Heuristic
15% Scripted
10% Reconnect/Spectator behavior
5% Remote engine/Pikafish
```

### 5.4. SimWorld

`SimWorld` dieu phoi toan bo run:

- Seeded random.
- Danh sach agents.
- Danh sach bot/socket.
- Bo nho ve room/game dang biet.
- Scheduler/timing.
- Target mode: `in-process`, `local`, `staging`.
- Event bus cho monitor/reporter.

Thong tin can luu:

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

### 5.5. Monitor / Oracle

Day la phan quan trong nhat. Tao N bot ma khong co oracle thi chi la "noise generator".

Monitor can phat hien:

- Bot khong nhan message sai phase.
- Hai nguoi choi trong mot room phai co mau khac nhau.
- Spectator khong bao gio duoc thanh player.
- `game-ended` khong duoc emit hai lan cho cung game.
- `moveCount` phai khop so moves.
- Reconnect phai tra dung room/moves/chat/clock snapshot.
- Sau drain khong con room/socket/queue rac.
- Khong co socket chet trong queue.
- Khong co room `playing` khong co nguoi ma ngoai grace.
- Latency p95/p99 khong vuot nguong.
- Engine call khong loi qua nguong.
- Firebase writes khong bi thieu, trung, hoac double-counter.

Co the tai su dung `lab/invariants.ts` cho in-process mode.

### 5.6. Reporter

Khi PASS:

```text
PASS sim-20260622-001
seed: 123
users: 20
duration: 3m
games started: 31
games ended: 31
reconnects: 8
spectator sessions: 12
chat messages: 120
engine calls: 14
p95 ws latency: 42ms
rooms after drain: 0
invariant violations: 0
```

Khi FAIL:

```text
FAIL sim-20260622-001
seed: 123
rule: game-ended emitted twice
roomId: ABCD12
agents: sim_004, sim_017
recent events: reports/sim-20260622-001/events.jsonl
replay:
npm run lab:sim -- --run-id=sim-20260622-001 --replay
```

Report files nen luu o:

```text
cchess-backend/lab/reports/
  sim-20260622-001/
    summary.json
    events.jsonl
    failure.md
```

Thu muc `lab/reports/` nen duoc ignore trong git neu report lon.

---

## 6. Cac che do chay

### 6.1. In-process mode

Dung server in-process nhu `lab/harness.ts`.

Muc tieu:

- Nhanh.
- Lap lai tot.
- Khong can Firebase.
- Bat bug realtime, room, socket, timer, queue, reconnect.

Lenh:

```bash
npm run lab:sim -- --target=in-process --users=20 --duration=3m --seed=123
```

Nen dua vao CI nhe sau khi on dinh.

### 6.2. Local mode

Chay backend local that:

```bash
npm run dev
npm run lab:sim -- --target=local --ws=ws://127.0.0.1:8080 --users=20
```

Muc tieu:

- Kiem tra server local theo black-box.
- Co the ket hop engine local.
- Co the dung Firebase test project neu can.

### 6.3. Staging mode

Chay tren backend staging + Firebase staging/test project.

Muc tieu:

- Test gan production nhung khong pha data production.
- Kiem tra auth, persistence, ELO, game_records, quota, engine deploy.

Quy tac:

- Moi user ao co prefix `sim_`.
- Moi game/record co `runId`.
- Co lenh cleanup theo `runId`.
- Khong dung production Firebase cho stress/load.

Lenh:

```bash
npm run lab:sim -- --target=staging --users=50 --duration=10m --seed=456
```

### 6.4. Production smoke nhe

Chi chay vai user va flow an toan.

Muc tieu:

- Xac nhan deploy song.
- Khong stress.
- Khong tao nhieu ranked write.

Production khong phai noi load test chinh.

---

## 7. Firebase va du lieu test

Can co Firebase project rieng cho simulation/staging.

Quy tac du lieu:

- UID simulator nen co prefix: `sim_<runId>_<index>`.
- Game metadata nen co `runId` neu adapter persistence cho phep.
- Neu khong them duoc `runId` vao schema production, reporter van phai ghi lai `gameId`, `roomId`, `uid`.
- Co script cleanup user/records theo `runId` trong staging.
- Khong chay stress tren production Firebase.

Kiem tra can co:

- Moi van ranked ket thuc chi tao record mot lan.
- ELO cap nhat dung hai chieu.
- Counters `wins/losses/draws/totalGames` khong double.
- Rematch tao record rieng tung van.
- Disconnect/timeout/resign ghi reason dung.
- Quota engine free user bi gioi han dung.

---

## 8. Engine trong simulator

Nen lap engine vao simulator, nhung theo dang plugin `MovePolicy`.

Muc tieu ngan han:

- Simulator choi duoc nuoc hop le.
- Tao van co dai/ngan tu nhien hon.
- Test game lifecycle tot hon random move cung.

Muc tieu dai han:

- Test bot mode.
- Test engine online/offline.
- So sanh chat luong engine.
- Test hint/analyze quota/latency.
- Ho tro sau nay cho tinh nang huan luyen voi nguoi choi.

Thu tu trien khai:

1. `RandomLegalPolicy`
   - Dung TS engine hien co trong `cchess-backend/src/engine`.
   - Sinh tat ca nuoc hop le tu `XiangqiGame`.

2. `HeuristicPolicy`
   - Diem co ban: an quan, chieu, tranh bi an tuong, uu tien quan manh.
   - Khong can qua manh.

3. `ScriptedPolicy`
   - Fixture cho checkmate, timeout, resign, rematch, reconnect.

4. `RemoteEnginePolicy`
   - Goi `cchess-engine`.
   - Gioi han concurrency va ti le user.
   - Co timeout/fallback sang legal move.

Nguyen tac:

- Engine failure khong lam simulation dung ngay neu muc tieu run la test server realtime; reporter ghi loi va fallback.
- Engine failure phai lam run fail neu profile la `engine-staging` hoac `engine-quota`.

---

## 9. Profiles de chay

### 9.1. `smoke-local`

Nhe, nhanh, chay truoc khi commit lon.

```text
users: 8
duration: 60s
engine: off
firebase: off
target: in-process
```

### 9.2. `realtime-soak`

Tap trung room/socket/reconnect.

```text
users: 30
duration: 10m
engine: light
firebase: fake
target: in-process/local
```

### 9.3. `staging-system`

Gan that, co Firebase staging va engine staging.

```text
users: 50
duration: 15m
engine: 5%
firebase: staging
target: staging
```

### 9.4. `engine-quota`

Tap trung engine service.

```text
users: 10
duration: 5m
engine: high
firebase: staging
target: staging
```

### 9.5. `prod-smoke`

Rat nhe.

```text
users: 2-4
duration: 60s
engine: minimal
firebase: production
target: production
ranked-write: opt-in only
```

---

## 10. Lo trinh trien khai

### Phase 1 - Nen mong CLI local

Muc tieu: chay duoc N user ao tren server in-process.

Viec can lam:

- Tao `lab/sim/runner.ts`.
- Tao `SimWorld`.
- Tao `PlayerAgent` interface.
- Tao `RandomLegalPolicy`.
- Tao `CasualPlayer`.
- Ghi event JSONL.
- Summary PASS/FAIL.
- Drain cuoi run va assert room sach.

Acceptance:

```bash
npm run lab:sim -- --target=in-process --users=10 --duration=60s --seed=1
```

Phai tra:

- Khong invariant violation.
- Co game started/ended.
- Sau drain con 0 room.
- Replay cung seed cho hanh vi tuong duong.

### Phase 2 - Monitor/oracle nghiem tuc

Muc tieu: bot khong chi chay, ma biet phat hien sai.

Viec can lam:

- Protocol phase assertions.
- Room/game memory.
- Detect double `game-ended`.
- Detect spectator thanh player.
- Detect move count mismatch.
- Detect reconnect snapshot sai.
- Failure bundle.

Acceptance:

- Khi chen loi co chu y vao server/test stub, simulation fail ro rule.
- Failure co `seed`, `runId`, `roomId`, `agents`, recent events.

### Phase 3 - Personas mo rong

Muc tieu: mo phong nhieu hanh vi nguoi dung hon.

Viec can lam:

- `ReconnectPlayer`.
- `SpectatorAgent`.
- `PrivateRoomPlayer`.
- `AbuseAgent`.
- `ScriptedPolicy`.
- Profile action weights.

Acceptance:

- Run 20-30 users trong 3-5 phut on dinh.
- Co reconnect, spectator, chat, resign, rematch trong summary.

### Phase 4 - Engine brain

Muc tieu: co nhom simulator choi thong minh hon va test engine.

Viec can lam:

- `HeuristicPolicy`.
- `RemoteEnginePolicy`.
- Engine timeout/fallback.
- Engine metrics: latency, error rate, cache hit neu co.
- Profile `engine-quota`.

Acceptance:

- 5% user co the goi engine ma khong lam simulation cham bat thuong.
- Engine fail duoc report dung profile.

### Phase 5 - Staging/Firebase

Muc tieu: test ecosystem gan that.

Viec can lam:

- Staging target config.
- Firebase test credentials.
- UID prefix `sim_`.
- Persistence verifier.
- Cleanup by `runId`.
- Report game_records/ELO/counters.

Acceptance:

- Staging run co the tao/ket thuc game that.
- Verify ELO/game_records khong double.
- Cleanup duoc du lieu test.

### Phase 6 - CI/nightly

Muc tieu: dua simulation vao quy trinh phat trien.

Viec can lam:

- CI nhe: `smoke-local`.
- Manual workflow: `realtime-soak`.
- Manual/staging workflow: `staging-system`.
- Artifact upload cho report.

Acceptance:

- PR/commit khong bi cham qua muc.
- Long run co the chay thu cong hoac nightly.

Trang thai trien khai:

- `backend-ci` chay them `npm run lab:sim:test` va `npm run lab:sim:ci` tren push/PR backend.
- Workflow `.github/workflows/simulation-layer.yml` chay nightly `realtime-soak` va cho phep manual run cac profile `smoke-local`, `realtime-soak`, `staging-system`, `engine-quota`.
- Tat ca workflow simulation upload `cchess-backend/lab/reports/**` lam artifact de lay `summary.json`, `events.jsonl`, va `failure.md` khi fail.
- Staging manual workflow dung secrets `CCHESS_FIREBASE_SERVICE_ACCOUNT_JSON`, `CCHESS_FIREBASE_API_KEY`, va neu can engine auth thi `CCHESS_ENGINE_FIREBASE_ID_TOKEN`.
- Cleanup co 2 cach:
  - Trong cung run: them `--cleanup-after` va tuy chon `--cleanup-delete-user-docs`, `--cleanup-delete-auth-users`.
  - Sau run: `npm run lab:sim -- --cleanup-run-id=<runId> --cleanup-dry-run` de xem se xoa gi, bo `--cleanup-dry-run` de xoa that.

Lenh acceptance hien tai:

```bash
npm run lab:check
npm run lab:sim:test
npm run lab:sim:ci
npm run lab:sim:soak
npm run lab:sim:staging-system -- --ws=wss://staging.example --engine-url=https://engine.example --cleanup-after
```

---

## 11. Rui ro va cach kiem soat

| Rui ro | Cach kiem soat |
|---|---|
| Simulation qua nang, chay cham | Mac dinh dung random/legal, engine chi 5% |
| Loi engine lam nhieu test false fail | Tach profile realtime va profile engine |
| Data staging bi rac | Gan `runId`, UID prefix `sim_`, co cleanup |
| Bug ngau nhien kho tai hien | Bat buoc seed + JSONL event log + replay command |
| Production bi anh huong | Khong stress production, ranked-write opt-in |
| Bot qua "may moc", khong giong nguoi | Them persona + delay ngau nhien + scripted behavior |
| Reporter qua it thong tin | Failure bundle gom roomId, agents, recent events, messages |

---

## 12. Dinh nghia thanh cong

Simulation Layer duoc xem la co gia tri khi:

- Chay duoc 20-50 nguoi dung ao tren may local.
- Co the phat hien loi tu dong, khong can doc log bang mat moi biet.
- Moi loi co seed/replay de tai hien.
- Co it nhat 3 persona: casual, reconnect, spectator.
- Co it nhat 2 brain: random/legal va heuristic/scripted.
- Co summary metrics ro rang.
- Co the chay staging voi Firebase test project.
- Sau moi run, he thong biet xac nhan "clean slate" hoac chi ra ro thu con sot.

---

## 13. Viec khong lam ngay

Chua nen lam trong MVP:

- Khong viet simulator app Flutter rieng.
- Khong chay 100% user bang Pikafish.
- Khong load test production.
- Khong thay unit/integration test hien co bang simulation.
- Khong xay dashboard dep truoc khi CLI/reporter on dinh.
- Khong dua Android/iOS vao viec tao N user ao; mobile chi dung cho mot so test native/UI that.

---

## 14. Buoc tiep theo de bat dau

1. Tao `cchess-backend/lab/sim/runner.ts`.
2. Tao `brain.ts` voi `MovePolicy`.
3. Viet `RandomLegalPolicy` dua tren `XiangqiGame`.
4. Viet `CasualPlayer`.
5. Chay 10 user trong 60 giay tren in-process server.
6. Them reporter summary.
7. Them monitor basic: clean slate, no invariant violations, no double end.

Lenh muc tieu dau tien:

```bash
cd cchess-backend
npm run lab:sim -- --target=in-process --users=10 --duration=60s --seed=1
```

Ket qua mong muon:

```text
PASS sim-...
users: 10
games started: ...
games ended: ...
rooms after drain: 0
invariant violations: 0
replay: npm run lab:sim -- --seed=1 ...
```

---

## 15. Ghi chu lien ket voi he thong hien co

Thanh phan hien co co the tai su dung:

- `cchess-backend/lab/bot.ts`: client WebSocket gia lap.
- `cchess-backend/lab/harness.ts`: server in-process voi timing ngan.
- `cchess-backend/lab/invariants.ts`: bat bien room/socket/timer.
- `cchess-backend/lab/fuzz.ts`: y tuong seeded random + history replay.
- `cchess-backend/lab/load.ts`: y tuong bring up/drain nhieu game.
- `cchess-backend/lab/smoke.ts`: black-box target staging/prod.
- `cchess-backend/src/engine`: Xiangqi rules, FEN, UCI, legal move generation.
- `cchess-backend/src/engine-service`: engine HTTP target cho RemoteEnginePolicy.

Simulation Layer nen la tang tong hop cac diem manh nay, khong thay the chung.
