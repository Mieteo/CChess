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
- [x] **Sprint 12 A5** Basic in-game chat — `chat-message`, 120-char limit, 1.5s/user rate limit
- [x] **Sprint 12 A6** Basic spectate — `spectate-room`/`stop-spectating`, read-only viewers receive move/chat/end snapshots
- [x] **Sprint 12 A6 polish** Active room list — `list-active-rooms` for lobby watch discovery
- [x] **Sprint 12 A6 share link** HTTP landing page `GET /r/:id` (`?mode=join` variant) for shareable room links / QR
- [x] **Backend tests** `npm test` covers spectator read-only, spectator leave, and active-room filtering

## Deploy

For local prototype testing:
- Android emulator: `ws://10.0.2.2:8080`
- Máy thật cùng wifi: `ws://<host LAN IP>:8080`
- Ngrok để expose ra Internet: `ngrok http 8080`

### Production — Render.com (Khuyến nghị cho prototype dev)

1. Push repo lên GitHub
2. Đăng nhập https://render.com → **New +** → **Blueprint**
3. Chọn repo, Render detect [`../render.yaml`](../render.yaml) (ở root repo — Render chỉ scan root, không scan sub-folder)
4. Render UI prompt nhập secret `FIREBASE_SERVICE_ACCOUNT_JSON`:
   - Tải `serviceAccount.json` từ Firebase Console
   - Mở file, **paste toàn bộ JSON** (1 dòng hoặc nhiều dòng đều OK)
   - Save
5. Deploy. ~3 phút.
6. URL public dạng `https://cchess-backend.onrender.com`
7. Client Flutter đổi `AppConstants.defaultBackendWsUrl` thành `wss://cchess-backend.onrender.com` (chú ý: **wss** chứ không phải ws — Render serve HTTPS)

**Lưu ý Render free tier**: web service ngủ sau 15 phút idle. Lần WS connect đầu tiên sau ngủ mất ~30s wake-up. Upgrade Starter ($7/tháng) nếu cần always-on.

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
