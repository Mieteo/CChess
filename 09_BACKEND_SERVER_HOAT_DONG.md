# Backend WebSocket — Hoạt động hệ thống

> Tài liệu sống — cập nhật 2026-05-31 sau khi Step 1-8 đã code + Step 5 (Xiangqi rule validation) + ELO calculation + A5 chat cơ bản + A6 Spectate cơ bản tích hợp.
> Bổ sung cho [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md): doc 08 là **thiết kế + lộ trình**, doc này là **mô tả thực tế** code đang chạy trong [`cchess-backend/`](cchess-backend/).

## 1. Mục tiêu

Sau nhiều vòng iteration + fix bug vụn vặt, hệ thống backend WebSocket đã ổn định cho prototype Sprint 12 phase 1. Tài liệu này:

- Hệ thống lại **luồng** chính: connection → auth → room → match → disconnect/reconnect → persistence
- Liệt kê **bảng protocol** đầy đủ (client ↔ server messages, error codes)
- Ghi lại **invariants** + **edge case** đã phát hiện qua test
- Cung cấp **operations guide** (run local, configure, deploy)
- Tổng hợp **lessons learned** từ các bug đã fix — tránh quên trong tương lai

---

## 2. Stack + cấu trúc file

| Thành phần | Lựa chọn | Lý do |
|---|---|---|
| Runtime | Node.js 20+ | LTS, support WebSocket native |
| Language | TypeScript 5.x | Type safety, dễ refactor |
| WebSocket | `ws` 8.x | Minimal, không opinions như socket.io |
| Auth | `firebase-admin` 12.x | Verify ID token issued by Flutter client |
| Persistence | `firebase-admin` Firestore | Admin SDK bypass rules, ghi result trực tiếp |
| Dev runner | `tsx` (auto-restart) | Không cần build mỗi lần |

Cấu trúc `cchess-backend/src/`:

```
src/
├── server.ts         ← entry point, WebSocket server, message router, close handler
├── auth.ts           ← Firebase Admin init + verifyIdToken
├── rooms.ts          ← Room storage + state machine helpers
├── match.ts          ← Game lifecycle (startMatch, applyMove, clock, end)
├── persistence.ts    ← Admin SDK Firestore writes + ELO transaction
├── elo.ts            ← Standard Elo formula (K=32)
└── engine/           ← Xiangqi rule validation (port từ Dart)
    ├── piece.ts
    ├── position.ts
    ├── board.ts
    ├── moveRules.ts
    ├── game.ts
    └── index.ts
```

Mỗi file < 250 dòng, single-responsibility. `server.ts` orchestrate, các file kia là pure helpers.

---

## 3. Vòng đời kết nối

### 3.1. Bắt tay WebSocket

1. Client mở `ws://<host>:8080`
2. Server `wss.on('connection', ...)` fire
3. Server gắn cờ `socket.isAlive = true` (cho heartbeat — xem 3.2)
4. Server gửi `{type:'welcome', message, ts}` ngay lập tức
5. **Đếm ngược 10 giây** (`AUTH_TIMEOUT_MS`): nếu chưa gửi `auth`, server `close(4001)`

### 3.2. Heartbeat

Cứ **5 giây** (`HEARTBEAT_INTERVAL_MS`), server làm 1 vòng:

```typescript
wss.clients.forEach((s) => {
  if (s.isAlive === false) {
    s.terminate();  // không pong → giết
    return;
  }
  s.isAlive = false;
  s.ping();         // gửi WS ping frame
});

s.on('pong', () => { s.isAlive = true; });
```

`ws` lib tự handle ping/pong frames. Client (browser hoặc Dart WS) **tự** gửi pong khi nhận ping — không cần code thêm.

**Tại sao cần**: mobile app khi bị kill (swipe-up close) đôi khi không kịp gửi TCP FIN → server không biết đối phương đã chết. Heartbeat đảm bảo phát hiện trong vòng 5-10s (1-2 chu kỳ).

**Trade-off**: chu kỳ ngắn → detect nhanh nhưng tốn bandwidth pings. 5s cân bằng tốt cho prototype; production có thể tăng lên 10-15s nếu user thật.

### 3.3. Đóng kết nối

`socket.on('close', ...)` chạy khi:
- Client gracefully đóng (gửi WS close frame hoặc TCP FIN)
- Heartbeat phát hiện zombie + `terminate()`
- Server tự `close()` (vd lỗi xác thực)

Logic xử lý trong handler (theo thứ tự):

```typescript
const wasPlaying = beforeRoom?.status === 'playing';

if (wasPlaying && uid) {
  // Step 8: bắt đầu grace period thay vì kết thúc game ngay
  beforeRoom.disconnectedUid = uid;
  beforeRoom.disconnectTimer = setTimeout(finishWithDisconnect, 60_000);
  broadcastToRoom(beforeRoom, socket, { type: 'peer-disconnected', uid, graceMs: 60_000 });
}

// Luôn dọn dẹp socket khỏi maps
const room = leaveRoom(socket, { preserveStatus: wasPlaying });

if (!wasPlaying && room && uid) {
  // Trường hợp rời lobby (chưa playing) → notify peer rời bình thường
  broadcastToRoom(room, socket, { type: 'peer-left', uid });
}

sessions.delete(socket);
```

**Quan trọng**: `preserveStatus: wasPlaying` giữ `room.status='playing'` để grace timer và reconnect handler vẫn nhận biết phòng đang trong ván — chứ không reset thành `'waiting'` (bug đã fix, xem mục 13).

---

## 4. Xác thực

### Flow

1. Client (Flutter) lấy ID token: `FirebaseAuth.instance.currentUser!.getIdToken()`
2. Client gửi `{type:'auth', token: '<JWT>'}`
3. Server `verifyIdToken(token)` qua Firebase Admin SDK
4. Thành công: `sessions.set(socket, decoded.uid)` + reply `{type:'authed', uid, email, anonymous}`
5. Thất bại: reply `{type:'error', code:'invalid-token'}` + `close(4002)`

### Cấu hình Admin SDK

`auth.ts` tự động chọn credential theo thứ tự:

1. `GOOGLE_APPLICATION_CREDENTIALS` env var (gcloud convention) → đường dẫn JSON
2. `./serviceAccount.json` ở cwd (gitignored)
3. Application Default Credentials (khi deploy lên Cloud Run / GCE)

### Token expire

ID token Firebase chỉ valid 1 giờ. Server không track expire — chỉ verify 1 lần khi nhận `auth`. Nếu ván dài hơn 1 giờ, token cũ vẫn được dùng (vì socket vẫn open). Không vấn đề trong thực tế.

Khi reconnect (Step 8), client phải gửi token MỚI (fresh) để pass verify lần 2.

---

## 5. Phòng (Room)

### 5.1. State machine

```
       create-room                 join-room (2nd)
[ ] ──────────────→ [waiting] ─────────────────→ [playing]
                       │                            │
                       │ leave-room/disconnect      │ game-ended (timeout/resign/disconnect)
                       │                            │
                       ↓                            ↓
                  (room deleted                 [finished]
                  if empty)
```

Trạng thái lưu trên `Room.status: 'waiting' | 'playing' | 'finished'`.

### 5.2. Tạo / Tham gia

`create-room`:
- Tạo `roomId` 6 ký tự alphabet (loại bỏ `0/O/1/I` gây nhầm)
- `room.members = Set([creator])`
- `room.status = 'waiting'`
- Reply `room-created {roomId}`

`join-room`:
- Verify roomId tồn tại, `members.size < 2`, socket chưa ở room khác
- Add socket vào `room.members`, `socketToRoom`
- Nếu `members.size === 2` → trigger **startMatch** (xem mục 6.1)
- Reply `room-joined {roomId, members, status}` cho joiner
- Broadcast `peer-joined {uid}` cho member cũ

### 5.3. Rời phòng (client-initiated)

`leave-room`:
- Nếu room đang `playing` → coi như disconnect: gọi `finishGame(other-wins, 'disconnect')`
- Nếu room đang `waiting`/`finished` → chỉ remove khỏi maps, broadcast `peer-left`

Lý do: client gửi `leave-room` khi user chủ động "Về Đối Đầu" hoặc đóng game UI. Trong khi đang chơi, hành động này tương đương "tôi không quay lại" → kết thúc game ngay.

### 5.4. Disconnect (socket close)

Khác với leave-room: socket close xảy ra mà không có thông báo trước → vào **grace period** 60s cho phép reconnect (xem mục 7).

---

## 6. Vòng đời ván

### 6.1. Bắt đầu (`startMatch` + `game-start`)

Khi player thứ 2 join → `startMatch(room)`:

```typescript
const members = [...room.members];           // theo thứ tự insert
room.redSocket = members[0];                 // creator = red
room.blackSocket = members[1];               // joiner = black
room.redUid = uidOf(members[0]);
room.blackUid = uidOf(members[1]);
room.clockMsByColor = { red: 600_000, black: 600_000 };  // 10 phút mỗi bên
room.currentTurn = 'red';
room.turnStartedAt = Date.now();
room.startedAt = Date.now();
room.movesUci = [];
room.status = 'playing';
```

Đồng thời, server bật `setInterval(checkTimeout, 1000)` per-room (`clockTimer`).

Server gửi `game-start` **per-socket** (không phải broadcast đồng nhất):

```typescript
for (const s of room.members) {
  const yourColor = s === room.redSocket ? 'red' : 'black';
  send(s, { type:'game-start', roomId, redUid, blackUid, yourColor, clock, startedAt });
}
```

Trường `yourColor` riêng cho từng socket — đây là **key fix** cho solo testing khi 2 socket cùng uid (xem mục 13).

### 6.2. Đi nước

Client gửi `{type:'move', uci:'e2e4'}`. Server:

1. **Format check**: regex `^[a-i][0-9][a-i][0-9]$` (Xiangqi 9 cột × 10 hàng)
2. **In-room check**: `room.members.size === 2`
3. **`applyMove(room, socket, uci)`** trong [match.ts](cchess-backend/src/match.ts):
   - Verify `room.status === 'playing'`
   - `colorOfSocket(room, socket)` — so sánh **socket reference** (không phải uid) để lấy màu
   - Verify `color === room.currentTurn`
   - Tính `elapsed = Date.now() - room.turnStartedAt`
   - Trừ vào `clockMsByColor[color]`
   - Nếu clock ≤ 0 → return `{ok:false, code:'time-out'}` → caller gọi `finishGame(other-wins, 'timeout')`
   - Push UCI vào `movesUci`, switch turn, reset `turnStartedAt`
4. Nếu OK → broadcast tới peer:
   ```json
   {type:'opponent-move', uci, from:<sender uid>, color, moveNumber, clock, ts}
   ```
5. Trả ack về sender:
   ```json
   {type:'move-ack', uci, moveNumber, clock}
   ```

**Step 5 đã làm**: `applyMove` parse UCI rồi gọi `engine.isValidMove(from, to)` + `engine.makeMove(from, to)`. Engine TypeScript trong [`engine/`](cchess-backend/src/engine/) là port 1:1 từ Dart `chess_engine` (Mã chân chẹt, Tượng mắt, Xe/Pháo bắn, Tướng đối mặt, isInCheck filter, ...). Nước trái luật → reject với `code:'illegal-move'`.

Khi engine.status đổi sang `RedWin`/`BlackWin`/`Draw` (checkmate hoặc stalemate), `applyMove` trả thêm `autoFinish` → caller gọi `finishGame` với reason `'checkmate'` hoặc `'stalemate'`.

### 6.3. Clock + timeout

`setInterval(1000)` per-room kiểm tra:

```typescript
function isTimedOut(room): boolean {
  const elapsed = Date.now() - room.turnStartedAt;
  return elapsed >= room.clockMsByColor[room.currentTurn];
}
```

Khi true → `finishGame(otherSide-win, 'timeout')`.

### 6.4. Resign

Client gửi `{type:'resign'}`. Server:
- Verify đang playing, socket là 1 trong 2 player
- `finishGame(opponentColor-win, 'resign')`

### 6.5. Kết thúc (`finishGame` + `game-ended`)

`finishGame(room, result, reason)`:

1. `endMatch(room, result, reason)`: set `status='finished'`, `room.endedAt = Date.now()`, clear `clockTimer`
2. Build payload + `broadcastAll(room, payload)`:
   ```json
   {type:'game-ended', roomId, result, reason, moves, startedAt, endedAt, durationMs, clock, redUid, blackUid}
   ```
3. **Fire-and-forget** `persistGame(room)` ghi Firestore (xem mục 8)

Sau game-ended, room ở `status='finished'`. Khi cả 2 socket disconnect, leaveRoom dọn khỏi `rooms` map.

---

## 7. Reconnect (Sprint 12 Step 8)

### 7.1. Tại sao cần

Mobile app dễ bị OS giết khi user backgroundv hoặc swipe-up. Mạng wifi/4G chập chờn. Nếu mỗi disconnect = thua, UX kém.

Giải pháp: **grace period 60s** sau khi socket close (trong khi đang chơi). Cho phép cùng uid quay lại.

### 7.2. Detection

Server biết player disconnect qua 1 trong 3 đường:
- `socket.on('close')` từ TCP FIN (client graceful close)
- `socket.on('close')` từ `terminate()` (heartbeat phát hiện zombie, 5-10s)
- Client gửi `leave-room` (rare — Flutter app lifecycle `detached`)

Cả 3 đều dẫn về `close` handler. Khi đang playing:

```typescript
beforeRoom.disconnectedUid = uid;
beforeRoom.disconnectTimer = setTimeout(checkAndFinish, 60_000);
broadcastToRoom(beforeRoom, socket, { type:'peer-disconnected', uid, graceMs:60_000 });
leaveRoom(socket, { preserveStatus: true });  // KHÔNG reset status về 'waiting'
```

Peer (remaining player) nhận `peer-disconnected` → UI hiển thị banner countdown.

### 7.3. Reconnect handler

Client mở app lại → đọc `ReconnectStore` (shared_preferences) → nếu fresh roomId tồn tại → auto connect + gửi `{type:'reconnect-room', roomId}`.

Server `reconnect-room`:

1. Verify roomId tồn tại
2. Verify `room.status === 'playing'`
3. Verify `room.disconnectedUid === uid` (chỉ chính player vừa rớt mới được vào lại)
4. `attachReconnectingSocket(newSocket, room, uid)`:
   - `room.members.add(newSocket)`
   - `socketToRoom.set(newSocket, room.id)`
   - Cập nhật `redSocket` hoặc `blackSocket` = newSocket
5. `clearTimeout(disconnectTimer)`, `disconnectedUid = undefined`
6. Gửi **snapshot** cho reconnecting client:
   ```json
   {type:'reconnected', roomId, yourColor, redUid, blackUid, moves, chat, currentTurn, clock, startedAt}
   ```
7. Broadcast `{type:'peer-reconnected', uid}` cho peer kia

Client `_onReconnected` replay `moves` vào fresh `XiangqiGame.initial()` → state phục hồi đúng.

### 7.4. Grace expire

Sau 60s nếu không reconnect, `disconnectTimer` callback fire:

```typescript
if (beforeRoom.disconnectedUid === uid && beforeRoom.status === 'playing') {
  finishGame(beforeRoom, otherColor-win, 'disconnect');
}
```

Điều kiện kép: vẫn còn được mark disconnected + vẫn đang playing. Nếu reconnect đã xảy ra, cả 2 đều false → callback no-op.

### 7.5. Clock trong grace period

**Không pause**. Clock vẫn chạy theo `turnStartedAt`. Nếu disconnect đúng lượt mình → clock mình bị trừ. Standard chess server behavior.

Implication: nếu disconnect lâu hơn clock còn lại → khi grace timer fire, applyMove logic không liên quan, finishGame trực tiếp với `'disconnect'` thay vì `'timeout'`.

Có 1 edge case: peer vẫn đi nước trong khi player kia disconnected. Hiện tại `applyMove` không block (status='playing', currentTurn switch sang remaining player nếu disconnected player vừa đi). Nhưng broadcast `opponent-move` đến socket dead → no-op. Khi reconnect, snapshot có moves đã chơi → state đồng bộ. Hành xử OK.

---

## 8. Persistence (Step 7)

Sau mỗi `finishGame`, `persistGame(room)` chạy fire-and-forget. Admin SDK bypass Firestore security rules.

Ghi **2 mirror documents** (một cho mỗi player) tại:
- `users/{redUid}/game_records/{gameId}`
- `users/{blackUid}/game_records/{gameId}`

`gameId = ${roomId}_${startedAt}` (vd `K8M4T7_1779462950000`).

Mỗi document chứa:

```json
{
  "gameId": "...",
  "roomId": "...",
  "mode": "ranked",
  "redUid": "...",
  "blackUid": "...",
  "opponent": "<uid của bên kia>",
  "humanColor": "red|black",
  "result": "win|loss|draw",          ← perspective của user
  "endReason": "timeout|resign|disconnect",
  "moveList": ["e2e4", "h9g7", ...],
  "moveCount": 21,
  "duration": 134567,                  ← ms
  "clockRemainingMs": { "red": 495400, "black": 510661 },
  "startingPosition": "standard",
  "startedAt": <Timestamp>,
  "endedAt": <Timestamp>,
  "isFavorite": false
}
```

Schema mirror với local `GameRecord` model (Hive) — sau này có thể sync 2 chiều.

**ELO update đã làm (Step A2)**: trong cùng transaction, server:

1. Đọc `eloChess` hiện tại của cả 2 player
2. Tính delta qua `computeElo(redOld, blackOld, result)` trong [elo.ts](cchess-backend/src/elo.ts) — chuẩn Elo K=32
3. Update `users/{uid}.eloChess` + tăng `totalGames` + `wins`/`losses`/`draws` qua `FieldValue.increment`
4. Ghi `eloChange`/`eloBefore`/`eloAfter` vào mỗi record perspective

ELO delta được gửi kèm trong `game-ended` payload (`elo: { red: {old,new,delta}, black: {old,new,delta} }`) — client hiển thị trong result dialog với mũi tên + màu (tealSuccess nếu lên, vermilionRed nếu xuống).

Client splash sync (`cloud_sync_service._mergeCloudIntoLocal`) đã update để pull `eloChess`/`eloCup`/`totalGames`/`wins`/`losses`/`draws` từ cloud (server-authoritative). Bot/local games có `eloDelta=0` không ghi cloud nên không có conflict.

**Chưa làm**: separate "casual ELO" (bot games) vs "ranked ELO". Hiện cả 2 dùng chung field `eloChess` nhưng bot không write → safe. Sprint 13+ khi có Cờ Úp variant sẽ tách rõ.

---

## 9. Bảng tham chiếu message

### 9.1. Client → Server

| Type | Payload | Phase chạy được | Mô tả |
|---|---|---|---|
| `auth` | `{token}` | Sau connect, trước 10s | Verify Firebase ID token |
| `create-room` | `{}` | Authed, chưa trong room | Tạo room mới |
| `join-room` | `{roomId}` | Authed, chưa trong room | Vào room có sẵn (size < 2) |
| `list-active-rooms` | `{}` | Authed | A6 polish: lấy danh sách ván đang playing để lobby hiển thị nút xem nhanh |
| `reconnect-room` | `{roomId}` | Authed | Step 8: vào lại room đang grace |
| `spectate-room` | `{roomId}` | Authed, room đang playing | A6: vào xem ván theo room ID; socket vào `room.spectators`, không có quyền move/resign |
| `stop-spectating` | `{}` | Đang spectate | Rời khỏi danh sách spectator, không ảnh hưởng 2 player |
| `leave-room` | `{}` | Đang trong room | Rời (nếu đang playing → tương đương disconnect) |
| `move` | `{uci}` | Đang playing, đúng lượt | Đi 1 nước UCI |
| `resign` | `{}` | Đang playing | Đầu hàng |
| `chat-message` | `{text}` | Đang trong room chưa finished | Chat text trong ván. Server trim/collapse whitespace, giới hạn 120 ký tự, rate limit 1.5s/user, lưu tối đa 50 tin trong room memory. |
| `broadcast` | `{payload}` | Đang trong room | Generic message gửi peer (chưa dùng cho game real) |

### 9.2. Server → Client

| Type | Payload | Khi nào |
|---|---|---|
| `welcome` | `{message, ts}` | Ngay khi connect |
| `authed` | `{uid, email, anonymous}` | Sau auth thành công |
| `room-created` | `{roomId}` | Sau create-room |
| `room-joined` | `{roomId, members, status}` | Cho joiner sau join-room |
| `peer-joined` | `{uid}` | Cho member cũ khi 2nd join |
| `game-start` | `{roomId, redUid, blackUid, yourColor, clock, startedAt}` | Per-socket khi đủ 2 người |
| `active-rooms` | `{rooms, total, limit, ts}` | Reply cho `list-active-rooms`. Mỗi item gồm `{roomId, redUid, blackUid, moveCount, spectatorCount, startedAt, currentTurn, clock}` |
| `move-ack` | `{uci, moveNumber, clock}` | Cho người vừa đi |
| `opponent-move` | `{uci, from, color, moveNumber, clock, ts}` | Cho peer và spectators |
| `peer-disconnected` | `{uid, graceMs}` | Khi 1 bên disconnect mid-game |
| `peer-reconnected` | `{uid}` | Khi player rớt mạng vào lại |
| `reconnected` | `{roomId, yourColor, redUid, blackUid, moves, chat, currentTurn, clock, startedAt}` | Snapshot cho client vừa reconnect, gồm move list và chat history ngắn trong room |
| `spectate-started` | `{roomId, redUid, blackUid, moves, chat, currentTurn, clock, startedAt, spectatorCount}` | Snapshot cho viewer mới vào xem |
| `spectate-stopped` | `{roomId}` | Ack stop-spectating cho viewer |
| `spectator-joined` | `{uid, spectatorCount}` | Broadcast khi có viewer mới |
| `spectator-left` | `{uid, spectatorCount}` | Broadcast khi viewer rời/đóng socket |
| `game-ended` | `{roomId, result, reason, moves, startedAt, endedAt, durationMs, clock, redUid, blackUid, elo}` | Cuối ván. `elo` = `{red:{old,new,delta}, black:{old,new,delta}}` hoặc `null` nếu persist fail. `reason` có thể là `checkmate`/`stalemate` (Step 5 auto-detect) hoặc `timeout`/`resign`/`disconnect`. |
| `chat-message` | `{roomId, id, from, text, ts}` | Khi player/viewer gửi chat hợp lệ; server broadcast lại cho players + spectators, bao gồm sender. |
| `left-room` | `{roomId}` | Ack leave-room cho người gửi |
| `peer-left` | `{uid}` | Cho remaining member khi peer rời (lobby) |
| `peer-message` | `{from, payload, ts}` | Generic broadcast tới peer |
| `echo` | `{uid, original, ts}` | Fallback khi server không hiểu message type |
| `error` | `{code, message?, uci?}` | Mọi lỗi |

### 9.3. Error codes

| Code | Khi nào |
|---|---|
| `auth-timeout` | Không gửi auth trong 10s sau connect |
| `missing-token` | `auth` không có field token |
| `invalid-token` | verifyIdToken throw (sai chữ ký, hết hạn, sai project) |
| `not-authed` | Gửi message khác auth khi chưa authed |
| `invalid-json` | Message body parse JSON failed |
| `binary-not-supported` | Gửi binary frame |
| `missing-room-id` | join/reconnect/leave thiếu roomId |
| `room-not-found` | RoomId không tồn tại trong `rooms` map |
| `room-full` | Cố join room đã có 2 người |
| `already-in-room` | Cố create/join khi đã trong room |
| `not-spectator` | Gửi `stop-spectating` nhưng socket không phải spectator |
| `not-in-room` | Cố move/broadcast/resign khi không trong room |
| `invalid-chat` | Chat rỗng, không phải string, hoặc dài hơn 120 ký tự |
| `chat-rate-limited` | Gửi chat nhanh hơn 1.5s/tin/user trong cùng room |
| `no-opponent` | Cố move khi room < 2 người |
| `invalid-uci` | UCI fail regex |
| `not-playing` | Cố move khi room không ở status playing |
| `not-player` | Socket không phải redSocket cũng không phải blackSocket |
| `not-your-turn` | Cố move khi không phải lượt mình |
| `illegal-move` | Move không hợp lệ theo luật Xiangqi (Step 5 engine reject) |
| `engine-missing` | Internal: room.engine null (không nên xảy ra sau startMatch) |
| `time-out` | (internal) Trả về từ applyMove khi clock cạn — caller xử lý |
| `game-not-active` | reconnect-room/spectate-room nhưng room.status không phải playing |
| `not-disconnected-player` | reconnect-room nhưng uid không khớp disconnectedUid |

### 9.4. Close codes (WebSocket)

| Code | Lý do |
|---|---|
| `1000` | Bình thường |
| `1005` | No status (browser tab close) |
| `1006` | Abnormal (TCP RST, mobile kill) |
| `4001` | Auth timeout |
| `4002` | Invalid token |

---

## 10. Invariants + edge case

### 10.1. Invariants

1. **Sessions map = socket → uid**: 1-1. 1 socket chỉ map 1 uid. Cùng uid có thể có nhiều socket (vd solo test, multi-tab).
2. **socketToRoom = socket → roomId**: max 1 room per socket.
3. **`room.members` ⊆ socketToRoom keys**: mọi socket trong members phải có entry trong socketToRoom (cùng roomId).
4. **`room.spectators` tách khỏi `room.members`**: viewers nhận broadcast/snapshot nhưng không tham gia startGame, move, resign, reconnect-loss.
5. **`room.status = 'playing'` ⇒ `redSocket` + `blackSocket` + `redUid` + `blackUid` đều set**: thiết lập trong `startMatch`.
6. **`room.disconnectedUid` set ⇒ `room.disconnectTimer` set**: cả 2 cùng tồn tại hoặc cùng null.
7. **Color identification dùng socket reference, không phải uid**: cùng uid vẫn distinct 2 sockets (solo test case).
8. **`leaveRoom(preserveStatus:true)` chỉ remove khỏi maps**: không đổi status, không xóa room. Chỉ dùng trong disconnect-during-game path.

### 10.2. Edge case đã handle

| Case | Hành vi |
|---|---|
| 2 socket cùng uid (solo test) | yourColor per-socket → mỗi socket biết màu riêng |
| Kill app khi peer turn | Heartbeat 5-10s phát hiện → grace 60s → finishGame disconnect nếu không quay lại |
| Home button (paused) | Không trigger leave — connection giữ alive, ping/pong tự handle |
| Swipe-up kill (detached) | `WidgetsBindingObserver` fire → `disconnectKeepingReconnectState()` → server detect (graceful) |
| App background lâu (OS kill) | Heartbeat eventually fire → grace flow |
| Reconnect đúng uid | Snapshot restore moves → resume |
| Reconnect sai uid | error `not-disconnected-player` |
| Reconnect quá 60s | Server đã `finishGame(disconnect)` rồi → error `game-not-active` |
| Spectator xem room đang chơi | Nhận `spectate-started` gồm moves/chat/clock/currentTurn, sau đó nhận move/chat/game-ended broadcast |
| Spectator gửi move/resign | Bị reject `not-player` vì không có `redSocket`/`blackSocket` |
| Spectator rời/đóng app | Chỉ remove khỏi `room.spectators`, broadcast `spectator-left`, không đổi trạng thái ván |
| Cả 2 disconnect đồng thời | `disconnectedUid` bị overwrite bởi người disconnect sau; người trước reconnect sẽ fail. Sprint 12+ refinement. |
| Server restart giữa ván | Tất cả rooms mất, clients nhận socket close → reconnect attempt fail → user thấy lobby error. Acceptable cho dev. Production cần persistence layer ở backend. |

### 10.3. Edge case chưa handle (TODO)

- **2 player disconnect cùng lúc**: chỉ track 1 `disconnectedUid`. Cần Map<uid, timer>.
- **Spectator public discovery**: đã có danh sách ván đang chơi qua `list-active-rooms`; chưa có invite/share link, moderation cho viewer public.
- **Server restart graceful**: chưa save room state. Khi restart, ván đang chơi mất.
- **Chat / emoji nâng cao**: text chat cơ bản đã có; emoji preset/whitelist, mute/report chưa làm.
- **Room state persistence**: move/chat history hiện vẫn ở memory, restart backend là mất ván.

---

## 11. Cấu hình

Constants trong `match.ts`:

```typescript
export const INITIAL_CLOCK_MS = 600_000;     // 10 phút mỗi bên
export const RECONNECT_GRACE_MS = 60_000;    // 60s grace
```

Constants trong `server.ts`:

```typescript
const PORT = Number(process.env.PORT ?? 8080);
const AUTH_TIMEOUT_MS = 10_000;              // auth phải gửi trong 10s
const HEARTBEAT_INTERVAL_MS = 5_000;         // ping every 5s
const UCI_REGEX = /^[a-i][0-9][a-i][0-9]$/;
```

Khi đổi `RECONNECT_GRACE_MS` ⇒ phải đồng bộ `ReconnectStore.freshness` ở client (`cchess/lib/data/services/reconnect_store.dart`) để client không thử reconnect ngoài cửa sổ.

---

## 12. Vận hành

### 12.1. Run local

```bash
cd cchess-backend
npm install
# Đặt service account
# Tải JSON từ https://console.firebase.google.com/project/cchess-dev/settings/serviceaccounts/adminsdk
# Lưu thành cchess-backend/serviceAccount.json (đã gitignore)
npm run dev   # tsx watch, auto-restart khi file thay đổi
```

Log mẫu khi 1 ván chạy:

```
[admin] initialized from .../serviceAccount.json
[server] HTTP+WS listening on http://localhost:8080
[ws] connected from ::ffff:192.168.1.112
[ws] authed uid=ytcI... email=hoan...
[room] K8M4T7 created by ytcI...
[ws] connected from ::ffff:192.168.1.106
[ws] authed uid=c7Bh... email=ding...
[room] K8M4T7 joined by c7Bh... (2/2)
[match] K8M4T7 started: red=ytcI... black=c7Bh...
[match] K8M4T7 #1 red h2e2 (red=599750ms black=600000ms)
[match] K8M4T7 #2 black h9g7 (red=599750ms black=596800ms)
...
[match] K8M4T7 ended result=red-win reason=resign moves=15
[persist] K8M4T7 → users/{ytcI..., c7Bh...}/game_records/K8M4T7_1779462950000
```

### 12.2. Test tự động backend

```bash
cd cchess-backend
npm test      # Node test runner qua tsx
npm run lint  # TypeScript strict/noEmit
```

Test hiện có: `src/rooms.test.ts` cover A6 spectator read-only (`not-player` khi move), spectator leave không đổi trạng thái phòng playing, và `activeRooms()` chỉ trả room đang chơi.

### 12.3. Test bằng browser console

Mở `http://localhost:8080/health` (HTTP → DevTools console không bị mixed-content block):

```js
const ws = new WebSocket('ws://localhost:8080');
ws.onopen = () => console.log('OPEN');
ws.onclose = e => console.log('CLOSE', e.code, e.reason);
ws.onmessage = e => console.log('<-', JSON.parse(e.data));

// Sau khi có ID token từ Flutter (Cloud Test screen → Copy ID token):
setTimeout(() => ws.send(JSON.stringify({type:'auth', token:'<PASTE>'})), 1000);

// Tạo phòng / vào phòng / đi nước:
function create() { ws.send(JSON.stringify({type:'create-room'})); }
function join(id) { ws.send(JSON.stringify({type:'join-room', roomId:id})); }
function move(uci) { ws.send(JSON.stringify({type:'move', uci})); }
function resign() { ws.send(JSON.stringify({type:'resign'})); }
```

### 12.4. Deploy (chưa làm)

Production hosting candidates (theo doc 06 + 08):

| Provider | Pros | Cons |
|---|---|---|
| Render | Free tier có WebSocket, deploy git push | Free instance ngủ sau 15ph idle |
| Railway | Đơn giản, $5/tháng base | Phải gắn thẻ |
| Fly.io | Global edge, generous free tier | Setup CLI hơi phức tạp |
| Cloud Run | Tích hợp Firebase project sẵn | WS giới hạn 60min/request, không phù hợp game dài |

Khuyến nghị: **Render** cho prototype, **Fly.io** khi launch.

Production cần thêm:
- Domain + HTTPS → URL chuyển thành `wss://` (secure WebSocket)
- Env vars cho `FIREBASE_*` thay vì file JSON
- Logging tập trung (vd Datadog, Logtail)
- Health check endpoint (`/health` đã có) cho load balancer

---

## 13. Lịch sử fix + lessons learned

Tóm tắt các bug + lý do để tránh lặp lại:

### Fix 1: Heartbeat phát hiện disconnect

**Triệu chứng**: User kill app → bên kia không nhận thông báo, ván tiếp tục đến khi clock chạy hết.

**Nguyên nhân**: Mobile OS kill app process không kịp gửi TCP FIN. Server tưởng kết nối vẫn open.

**Fix**: Implement WS ping/pong heartbeat. Server ping mỗi 5s, terminate nếu không nhận pong trong chu kỳ tiếp theo.

**Lesson**: Đừng tin TCP close events một mình cho mobile clients. Heartbeat là tiêu chuẩn industry.

### Fix 2: `yourColor` per-socket

**Triệu chứng**: Solo testing (cùng Google account trên 2 endpoint) → bên joiner (black) không click được quân.

**Nguyên nhân**: Client code so `myUid == redUid` để xác định màu. Khi 2 socket cùng uid, cả 2 đều match red.

**Fix**: Server gửi `game-start` per-socket, mỗi cái có `yourColor: 'red' | 'black'` riêng dựa vào socket reference.

**Lesson**: Identity dựa vào uid là không đủ. Socket reference cũng cần thiết khi cùng người có thể có nhiều connection.

### Fix 3: `colorOfSocket` thay `colorOfPlayer`

**Triệu chứng**: Server cho qua move khi không đúng lượt (cũng do solo test cùng uid).

**Nguyên nhân**: `colorOfPlayer(room, uid)` check `uid === redUid` → cả 2 socket cùng uid đều thấy mình là red.

**Fix**: Đổi sang `colorOfSocket(room, socket)` so sánh socket reference.

**Lesson**: Cùng pattern với Fix 2 — chỗ nào identify color phải dùng socket, không uid.

### Fix 4: `leaveRoom(preserveStatus)` cho reconnect

**Triệu chứng**: Reconnect và grace timer cả 2 đều fail. Server trả `game-not-active`, grace timer không fire finishGame.

**Nguyên nhân**: `leaveRoom()` mặc định set `room.status = 'waiting'`. Sau đó `reconnect-room` check `status === 'playing'` fail. Grace timer cũng check `status === 'playing'` fail.

**Fix**: Thêm option `preserveStatus: true` cho `leaveRoom` — chỉ remove socket khỏi maps, không đổi status. Close handler dùng option này khi `wasPlaying`.

**Lesson**: Khi thêm state mới (status playing/finished/...), audit MỌI mutation có thể đụng đến state đó. Helpers cũ có thể có side effect không mong đợi cho flow mới.

### Fix 5: Heartbeat 15s → 5s

**Triệu chứng**: Sau khi peer kill app, A đợi 10-15s mới thấy banner countdown.

**Nguyên nhân**: Heartbeat interval 15s → worst case 30s mới phát hiện zombie. UX chậm.

**Fix**: Hạ xuống 5s. Detection trong 5-10s.

**Lesson**: Test heartbeat lag bằng kill thật (không phải background). Default 30s của lib `ws` quá chậm cho game realtime.

### Fix 6: Client-initiated `leave-room` trong khi đang playing

**Triệu chứng**: A (creator/red) lifecycle observer fire detached → gọi `leave()` → gửi `leave-room` → server treat như "rời bình thường" không phải disconnect → B không nhận game-ended.

**Nguyên nhân**: `leave-room` handler chỉ broadcast `peer-left`, không gọi `finishGame`. Nhưng client lifecycle dùng nó trong tình huống disconnect.

**Fix**: 2 đầu:
- Server: nếu `leave-room` khi room đang `playing` → coi như disconnect, gọi `finishGame`
- Client: khi `isPlaying`, chỉ `disconnect()` (không send `leave-room` trước) để server đi đường natural close

**Lesson**: Phân biệt rõ "user chủ động rời lobby" vs "user mất kết nối giữa ván" — 2 flow khác hẳn nhau dù cùng dẫn tới socket close.

### Fix 7: Double-flip bug trong `ChessBoard.onTapDown`

**Triệu chứng**: Black side click quân nhưng không có gì xảy ra (online game).

**Nguyên nhân**: `ChessBoard` widget khi `flipped:true` áp dụng flip pixel + flip cell coords → double-flip → onTap trả về sai board position. Local game không bao giờ flip nên bug latent.

**Fix**: Bỏ `_maybeFlip` trong tap handler, chỉ giữ cell-flip.

**Lesson**: Bug latent trong widget chung sẽ chỉ lộ khi có UI mới dùng feature ít được test. Code review widget shared cẩn thận khi mở thêm flow.

### Fix 8: Countdown UI khi 0s

**Triệu chứng**: Banner kẹt ở "còn 0s để reconnect" sau khi countdown về 0, không có dialog game-ended.

**Nguyên nhân**: Client countdown đếm theo CLIENT time (nhận peer-disconnected). Server's grace timer fire SAU client countdown vài giây (do latency network + heartbeat lag). User tưởng app đứng máy.

**Fix**: Khi `sec <= 0`, đổi text sang "Hết thời gian chờ — đang xác nhận kết quả…" để cho biết app vẫn đang chờ.

**Lesson**: UI countdown không bao giờ chính xác 100% với server timer. Khi đến 0, phải có trạng thái "chờ xác nhận" rõ ràng để user không tưởng đứng app.

---

## 14. Tài liệu liên quan trong repo

- [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md) — sprint status tracker (8c đang ở đây)
- [`06_KIEN_TRUC_BACKEND_THUC_DUNG.md`](06_KIEN_TRUC_BACKEND_THUC_DUNG.md) — lý do chọn Node WS thay Cloud Functions
- [`07_HUONG_DAN_THIET_LAP_FIREBASE.md`](07_HUONG_DAN_THIET_LAP_FIREBASE.md) — Firestore + Auth setup
- [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md) — thiết kế + roadmap Step 1-8
- [`cchess-backend/README.md`](cchess-backend/README.md) — quick start + checklist Step 1-7

## 15. Tài liệu nên đọc thêm (external)

- [ws library guide](https://github.com/websockets/ws/blob/master/doc/ws.md) — đặc biệt mục `WebSocket.send()` + `terminate()` + heartbeat example
- [Firebase Admin SDK verifyIdToken](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Cloudflare WebSocket guide](https://developers.cloudflare.com/workers/runtime-apis/websockets/) — nếu sau này cân nhắc edge deployment
