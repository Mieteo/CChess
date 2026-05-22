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
- [ ] **Step 4** Move transport — client A sends move, server forwards to client B
- [ ] **Step 5** Move validation — server runs Xiangqi rules
- [ ] **Step 6** Server-side clock + timeout
- [ ] **Step 7** Persistence — write ranked results back to Firestore via Admin SDK

## Deploy (later)

For prototype testing:
- Localhost — Android emulator dùng `ws://10.0.2.2:8080`, máy thật cùng wifi dùng `ws://<máy-host-IP>:8080`
- Ngrok để expose ra Internet: `ngrok http 8080`

For production:
- **Render / Railway / Fly.io / Cloud Run** — Node.js, support WebSocket dài hạn
- **KHÔNG** dùng Cloud Functions cho WebSocket — Functions không giữ kết nối lâu hơn vài phút
