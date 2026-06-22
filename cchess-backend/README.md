# CChess Backend (WebSocket)

Real-time backend for online matches, presence, and ranked ELO writes.
Spec: [`../08_HUONG_DAN_BACKEND_WEBSOCKET.md`](../08_HUONG_DAN_BACKEND_WEBSOCKET.md).

## Stack

- Node.js 20+
- `ws` (raw WebSocket — easier to reason than Socket.IO)
- `firebase-admin` (verify ID tokens from Flutter client)
- TypeScript

## Setup

### 1. Install deps

```bash
cd cchess-backend
npm install
```

### 2. Tải Firebase service account (cho Step 2 auth)

1. Mở https://console.firebase.google.com/project/cchess-dev/settings/serviceaccounts/adminsdk
2. Click **Generate new private key** → **Generate key**
3. Lưu file vào `cchess-backend/serviceAccount.json`
   (file này đã được gitignored — không commit lên repo)

Hoặc set env var trỏ đến file ở chỗ khác:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\serviceAccount.json"
```

### 3. Run server

```bash
npm run dev
```

Output:
```
[admin] initialized from .../cchess-backend/serviceAccount.json
[server] HTTP+WS listening on http://localhost:8080
```

Health check: open `http://localhost:8080/health` → `ok`.

## Engine service: chạy Pikafish thật

Repo có thêm service HTTP riêng cho Pikafish tại `src/engine-service/`. Service này tách khỏi WebSocket realtime server để tránh engine ăn CPU làm giật đồng hồ ván online.

Endpoints:

| Method | Path | Body | Ghi chú |
|---|---|---|---|
| `GET` | `/health` | - | Health + pool/cache stats |
| `POST` | `/engine/best-move` | `{ "fen": "...", "level": "grandmaster" }` | Trả `{uci, scoreCp, depth, pv}` |
| `POST` | `/engine/hint` | `{ "fen": "..." }` | Giống best-move nhưng quota riêng |
| `POST` | `/engine/analyze` | `{ "startingFen": "...", "movesUci": [...] }` | Trả phân tích từng nước |

### Nguồn tải chính thức

- Pikafish source/release: https://github.com/official-pikafish/Pikafish
- Latest release đang dùng trong tài liệu ngày 2026-06-07: `Pikafish-2026-01-02`
- Binary release asset: `https://github.com/official-pikafish/Pikafish/releases/download/Pikafish-2026-01-02/Pikafish.2026-01-02.7z`
- NNUE network: `https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue`

Lưu ý license: Pikafish source/binary là GPL-3.0. File `pikafish.nnue` nằm ở repo Networks và có điều khoản riêng, trong đó có hạn chế dùng thương mại nếu chưa được phép. Với production thương mại, cần xử lý license trước khi dùng NNUE chính thức.

### Cách khuyến nghị: Docker build từ source

`Dockerfile.engine` tự clone Pikafish, build generic `ARCH=x86-64`, tải NNUE bằng `make net`, chạy `bench`, rồi start Node engine API.

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

Black-box smoke tự động:

```powershell
npm run engine:smoke
npm run engine:smoke:quota
npm run engine:smoke -- --quota --quota-limit=3
```

Mặc định `engine:smoke` trỏ tới `https://cchess-engine.onrender.com`. Có thể override:

```powershell
$env:CCHESS_ENGINE_URL = "http://localhost:8090"
$env:ENGINE_SMOKE_AUTH = "disabled" # local ENGINE_AUTH_DISABLED=1
npm run engine:smoke
```

`engine:smoke:quota` mint một Firebase anonymous user mới, gọi `/engine/hint`
đúng số quota free rồi xác nhận request kế tiếp trả `429 quota-exceeded`.
Workflow thủ công `.github/workflows/engine-smoke.yml` có input `engine_url`,
`auth_mode`, `check_quota`, `hint_quota_limit`; product smoke trên Render
`cchess-engine` đã PASS 8/8 ngày 2026-06-20 gồm quota.

### Chạy local bằng binary tải tay trên Windows

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

Khi tắt `ENGINE_AUTH_DISABLED`, client phải gửi `Authorization: Bearer <Firebase ID token>`.

### Flutter trỏ vào engine local

Android emulator:

```powershell
flutter run --dart-define=CCHESS_ENGINE_URL=http://10.0.2.2:8090
```

Máy thật cùng Wi-Fi:

```powershell
flutter run --dart-define=CCHESS_ENGINE_URL=http://<LAN-IP-cua-may-dev>:8090
```

Trong app, dùng `RemotePikafishEngine` + `EngineRouter` để remote-ok thì dùng Pikafish, remote lỗi/offline thì fallback `LocalMinimaxEngine`.

## Test from browser console

```js
// 1. Connect
const ws = new WebSocket('ws://localhost:8080');
ws.onmessage = (e) => console.log('<-', JSON.parse(e.data));

// 2. Server sends {type:"welcome"}. You have 10s to authenticate.

// 3. Get a Firebase ID token. The easiest way for a quick test:
//    - Open the Flutter app, sign in.
//    - In a debug Dart REPL or via cloud_test_screen, print
//      `await FirebaseAuth.instance.currentUser!.getIdToken()`.
//    - Copy that JWT.

const token = '<paste id token here>';
ws.send(JSON.stringify({ type: 'auth', token }));

// 4. Server responds {type:"authed", uid, email, anonymous}.

// 5. Send any message — server echoes with your uid attached.
ws.send(JSON.stringify({ type: 'ping' }));
// -> {type:"echo", uid:"...", original:{type:"ping"}, ts:...}
```

## Auth protocol

| Direction | Message | Notes |
|---|---|---|
| ← Server | `{type:"welcome", message, ts}` | On connect |
| → Client | `{type:"auth", token}` | Within 10s, else socket closes |
| ← Server | `{type:"authed", uid, email, anonymous}` | Success |
| ← Server | `{type:"error", code:"invalid-token"\|"missing-token"\|"auth-timeout"}` | Socket closes |

Close codes:
- `4001` — auth timeout
- `4002` — invalid token

## Roadmap (per doc 8 mục 13)

- [x] **Step 1** Echo server
- [x] **Step 2** Auth handshake — server verifies Firebase ID token, gắn socket với `uid`
- [x] **Step 3** Room (manual create/join, broadcast events) — verified E2E 2026-05-21
- [x] **Step 4** Move transport — UCI regex check + moveNumber + opponent-move — verified E2E 2026-05-21
- [x] **Step 5** Move validation — server runs Xiangqi rules via TypeScript engine port
- [x] **Step 6** Server-side clock + timeout + resign + disconnect-loss — verified E2E 2026-05-23
- [x] **Step 7** Persistence — Admin SDK writes `users/{uid}/game_records/` on game-ended — verified E2E 2026-05-23
- [x] **Step 8** Reconnect grace — 60s room resume with move/chat snapshot
- [x] **Sprint 12 A5** Basic in-game chat — `chat-message`, 120-char limit, 2s/user rate limit
- [x] **Sprint 12 A6** Basic spectate — `spectate-room`/`stop-spectating`, read-only viewers receive move/chat/end snapshots
- [x] **Sprint 12 A6 polish** Active room list — `list-active-rooms` for lobby watch discovery
- [x] **Sprint 12 A6 share link** HTTP landing page `GET /r/:id` (`?mode=join` variant) for shareable room links / QR
- [x] **Backend tests/gates** `npm test` covers unit/integration server + engine-service; `backend-ci` also runs `lab`, `lab:sim:test`, `lab:sim:ci`, `lab:load`, and seeded `lab:fuzz`
- [x] **Simulation Layer Phase 1-6** `lab/sim` covers multi-user personas, protocol oracle, heuristic/remote-engine brains, staging Firebase persistence verification/cleanup, CI-light smoke, nightly/manual `simulation-layer` workflow, and report artifacts
- [x] **Engine service smoke** `npm run engine:smoke` / `npm run engine:smoke:quota` covers deployed `cchess-engine` (`/health`, auth, invalid FEN, best-move/cache, hint, analyze, quota)

## Deploy

For local prototype testing:
- Android emulator: `ws://10.0.2.2:8080`
- Máy thật cùng wifi: `ws://<host LAN IP>:8080`
- Ngrok để expose ra Internet: `ngrok http 8080`

### Production — Render.com (Khuyến nghị cho prototype dev)

1. Push repo lên GitHub
2. Đăng nhập https://render.com → **New +** → **Blueprint**
3. Chọn repo, Render detect [`../render.yaml`](../render.yaml) (ở root repo — Render chỉ scan root, không scan sub-folder)
4. Blueprint tạo 2 service: `cchess-backend` (WebSocket realtime) và `cchess-engine` (HTTP Pikafish).
5. Render UI prompt nhập secret `FIREBASE_SERVICE_ACCOUNT_JSON` cho các service:
   - Tải `serviceAccount.json` từ Firebase Console
   - Mở file, **paste toàn bộ JSON** (1 dòng hoặc nhiều dòng đều OK)
   - Save
6. Deploy. Backend thường ~3 phút; engine lâu hơn vì Docker image có Pikafish/NNUE.
7. URL public dạng `https://cchess-backend.onrender.com` và `https://cchess-engine.onrender.com`.
8. Client Flutter đổi `AppConstants.defaultBackendWsUrl` thành `wss://cchess-backend.onrender.com` (chú ý: **wss** chứ không phải ws — Render serve HTTPS). Engine URL dùng `CCHESS_ENGINE_URL=https://cchess-engine.onrender.com`.

**Lưu ý Render free tier**: web service ngủ sau 15 phút idle. Lần WS connect đầu tiên sau ngủ mất ~30s wake-up. Upgrade Starter ($7/tháng) nếu cần always-on.
`cchess-engine` free tier chỉ phù hợp smoke/prototype; nâng Standard trước khi mở bot mạnh/hint/analyze cho user thật. Quota free hiện cấu hình trong `render.yaml` (`FREE_BEST_MOVE_DAILY_LIMIT`, `FREE_HINT_DAILY_LIMIT`, `FREE_ANALYZE_DAILY_LIMIT`) nhưng vẫn là in-memory theo process, cần Firestore/Redis để production không reset khi restart/redeploy.

### Production — Railway / Fly.io / Cloud Run

Tương tự, đều support Dockerfile. Setup secrets qua dashboard mỗi platform:
- Railway: Variables tab
- Fly.io: `fly secrets set FIREBASE_SERVICE_ACCOUNT_JSON='...'`
- Cloud Run: Secret Manager hoặc env var

KHÔNG dùng Cloud Functions cho WebSocket — Functions không giữ kết nối lâu hơn vài phút.

### Service account credential — 4 cách load

[`src/auth.ts`](src/auth.ts) thử theo thứ tự:
1. `FIREBASE_SERVICE_ACCOUNT_JSON` env var — full JSON inline (pattern Render/Railway/Fly)
2. `GOOGLE_APPLICATION_CREDENTIALS` env var — đường dẫn file (gcloud)
3. `./serviceAccount.json` cwd (local dev)
4. Application Default Credentials (Cloud Run / GCE / Cloud Functions)
