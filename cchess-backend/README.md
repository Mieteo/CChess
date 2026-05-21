# CChess Backend (WebSocket)

Real-time backend for online matches, presence, and ranked ELO writes.
Spec: [`../08_HUONG_DAN_BACKEND_WEBSOCKET.md`](../08_HUONG_DAN_BACKEND_WEBSOCKET.md).

## Stack

- Node.js 20+
- `ws` (raw WebSocket — easier to reason than Socket.IO)
- `firebase-admin` (verify ID tokens from Flutter client)
- TypeScript

## Quick start

```bash
cd cchess-backend
npm install
npm run dev
```

Open `http://localhost:8080/health` → should return `ok`.

Test the echo from any browser console:

```js
const ws = new WebSocket('ws://localhost:8080');
ws.onopen = () => ws.send('hello');
ws.onmessage = (e) => console.log('echo:', e.data);
```

You should see `{"type":"welcome",...}` first, then `{"type":"echo","original":"hello",...}`.

## Roadmap (per doc 8 mục 13)

- [x] **Step 1** Echo server (this file)
- [ ] **Step 2** Auth handshake — client sends Firebase ID token, server verifies via Admin SDK
- [ ] **Step 3** Room (manual create/join, broadcast events)
- [ ] **Step 4** Move transport — client A sends move, server forwards to client B
- [ ] **Step 5** Move validation — server runs Xiangqi rules
- [ ] **Step 6** Server-side clock + timeout
- [ ] **Step 7** Persistence — write ranked results back to Firestore via Admin SDK

## Auth handshake (Step 2 — next)

When ready:

1. Download service account JSON from
   https://console.firebase.google.com/project/cchess-dev/settings/serviceaccounts/adminsdk
2. Save as `cchess-backend/serviceAccount.json` (already gitignored)
3. Implement `src/auth.ts` that uses `admin.auth().verifyIdToken(token)`
4. Client sends token in first WS message; server attaches `uid` to socket

## Deploy

For prototype:
- Localhost only (cấu hình client trỏ tới `ws://10.0.2.2:8080` nếu test Android emulator)
- Hoặc ngrok để expose ra Internet

For production:
- Render / Railway / Fly.io / Cloud Run — Node.js with WebSocket support
- Tránh Cloud Functions cho WS (Cloud Functions không giữ kết nối lâu)
