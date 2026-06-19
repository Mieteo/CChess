# CChess Test Lab

Công cụ kiểm thử logic real-time của server (ghép trận, hủy, chờ, connect/disconnect,
reconnect grace, tạo/xóa phòng) một cách **xác định và lặp lại được** — không phải
thao tác tay trên app thật.

Server thật được chạy **in-process** qua `createCChessServer()` với auth/persist
stub (token = uid, không cần Firebase). Mọi mốc thời gian (grace, TTL phòng chờ,
heartbeat) được rút ngắn và cấu hình được, nên một ván "60s grace" test xong trong ~1s.

> Lab nằm ngoài `src/` nên **không lọt vào bản build/deploy production** (`tsc` chỉ
> biên dịch `src/`). Server production hoàn toàn không có debug endpoint.

## Chạy

```bash
npm run lab            # chạy toàn bộ kịch bản (headless), in PASS/FAIL
npm run lab reconnect  # chỉ kịch bản có tên khớp "reconnect"
LAB_VERBOSE=1 npm run lab   # kèm log server
npm run lab:check      # type-check riêng thư mục lab
npm run lab:dashboard  # mở dashboard tại http://localhost:7700
npm run lab:fuzz       # soak ngẫu nhiên (thêm --burst để săn race)
npm run lab:load 150   # 150 ván song song rồi rút hết → phải về 0 phòng
npm run lab:smoke      # black-box test trên server thật (onrender)
SMOKE_ALLOW_RANKED_WRITE=1 npm run lab:smoke
# opt-in: bắt đầu/kết thúc ván thật để smoke matchmaking, reconnect, resign
npm run engine:smoke   # black-box HTTP smoke cho cchess-engine
ENGINE_SMOKE_CHECK_QUOTA=1 npm run engine:smoke
npm run engine:smoke:quota
# opt-in: kiểm quota free user đến khi nhận quota-exceeded
```

`lab:smoke` mặc định **prod-safe**: xác thực, tạo/rời phòng chờ, enqueue/cancel matchmaking, nhưng không để ván bắt đầu nên không ghi `game_records`/ELO. Khi chạy với `SMOKE_ALLOW_RANKED_WRITE=1`, script cần 2 Firebase user khác nhau (tự mint anonymous users, hoặc truyền `FIREBASE_ID_TOKEN_A` + `FIREBASE_ID_TOKEN_B`) và sẽ tạo ván ranked thật để kiểm deploy end-to-end.

## Thành phần

| File | Vai trò |
|---|---|
| `harness.ts` | Khởi tạo server in-process + điều khiển timing (gồm `minClockMs`) |
| `bot.ts` | `Bot` — client WebSocket kịch bản (1 bot = 1 user mô phỏng) |
| `invariants.ts` | **Cốt lõi:** các bất biến state phải luôn đúng ở trạng thái ổn định |
| `scenarios.ts` | Các kịch bản đặt tên (thêm coverage = thêm 1 entry) |
| `run-one.ts` | Chạy 1 kịch bản trên server cô lập + assert invariant |
| `runner.ts` | Chạy hàng loạt kịch bản headless |
| `fuzz.ts` | Soak ngẫu nhiên có seed (tái hiện được) + `--burst` (đua tin nhắn) |
| `load.ts` | Test tải/rò rỉ: nhiều ván song song → khẳng định về bàn sạch |
| `smoke.ts` | Smoke test trên server thật (auth Firebase ẩn danh; prod-safe mặc định, có opt-in ranked-write) |
| `engine_smoke.ts` | Smoke test HTTP cho `cchess-engine` (`/health`, auth, best-move, cache, hint, analyze, quota opt-in) |
| `render.ts` | Trigger + giám sát deploy Render (cần `RENDER_API_KEY`) |
| `control.ts` + `public/` | Dashboard web: bot thủ công + nút chạy kịch bản |

## Bất biến đang kiểm (invariants.ts)

1. **playing-room-has-someone** — phòng `playing` mà 0 người kết nối thì phải đang
   trong grace (nếu không → ghost kẹt vĩnh viễn). *Đây là class bug "đang đánh" gốc.*
2. **no-stale-member-socket** — không socket chết nào còn nằm trong `members`.
3. **playing-room-has-both-colors** — ván sống phải có đủ redUid/blackUid.
4. **waiting-room-not-empty** — phòng `waiting` luôn còn người tạo.
5. **finished-room-cleaned-up** — phòng `finished` không còn ai phải được xóa.
6. **no-orphan-clock-timer** — clock ticker chỉ chạy khi `playing`.
7. **socket-map-consistency** — `rooms` và `socketToRoom` luôn khớp nhau.
8. **no-dead-socket-in-queue** — không socket đã đóng nào kẹt trong hàng chờ.
9. **playing-seat-live-or-grace** — mỗi ghế của ván `playing` phải có socket OPEN,
   trừ khi ghế đó đang trong grace (grace key theo GHẾ, hỗ trợ cả ván cùng-uid).
10. **playing-room-has-clock** — ván `playing` đã khởi tạo đồng hồ.
11. **grace-uids-are-players** — ai trong grace phải là một trong hai kỳ thủ.
12. **move-count-consistent** — `moveCount` khớp `movesUci.length`.

## Bug do lab/fuzzer tìm ra (đã sửa)

- **Ghost room "đang đánh"** sau khi cả 2 rời (Nhóm gốc).
- **Double-booking:** `find` rồi `create` không rời hàng chờ → matchmaking ghép vào ván thứ 2.
- **Dead socket trong queue:** `find` rồi rớt *trong lúc* handler `await` fetch ELO → enqueue socket đã chết (race, burst fuzzer).
- **Join-hijack:** join vào phòng `playing` (ghế đang grace) làm reset ván + cướp ghế.
- **Double-finish:** kết thúc ván 2 lần → cộng ELO 2 lần (đã guard idempotent).
- **Same-uid double-disconnect:** grace key theo uid gộp 2 ghế → reconnect 1 ghế xóa grace ghế kia (đã đổi sang key theo ghế).

## Nhóm 5 — chống lạm dụng / DoS

- **Rate-limit** mọi message theo token-bucket per-socket (`rate-limited`; flood quá mức → terminate).
- **Re-auth bị chặn** (`already-authed`) — một socket auth đúng một lần.
- **Giới hạn payload** 16 KB (ws `maxPayload`).
- Hành vi sản phẩm đã chốt (khóa bằng scenario): spectator **được** chat; đồng hồ **vẫn chạy** khi đối thủ trong grace.

## Lưu ý harness (config-threading)

Timing/limits truyền qua `createCChessServer({ config })` **mỗi instance**, KHÔNG qua env.
Env chỉ đọc một lần lúc import → bị module-cache đóng băng → các scenario sau sẽ
âm thầm chạy sai config. `config` thì áp đúng cho từng lần gọi (mỗi scenario một server).

## Thêm kịch bản

Thêm một entry vào mảng `scenarios` trong `scenarios.ts`. Mỗi bước dùng `Bot`
(`createRoom`, `findMatch`, `joinRoom`, `resign`, `leaveRoom`, `drop`,
`reconnectRoom`…), `await` message từ server, rồi `lab.assertHealthy()`.
`drop()` mô phỏng rớt mạng đột ngột; `close()` là rời êm.
