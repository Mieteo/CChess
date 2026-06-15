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
```

## Thành phần

| File | Vai trò |
|---|---|
| `harness.ts` | Khởi tạo server in-process + điều khiển timing |
| `bot.ts` | `Bot` — client WebSocket kịch bản (1 bot = 1 user mô phỏng) |
| `invariants.ts` | **Cốt lõi:** các bất biến state phải luôn đúng ở trạng thái ổn định |
| `scenarios.ts` | Các kịch bản đặt tên (thêm coverage = thêm 1 entry) |
| `run-one.ts` | Chạy 1 kịch bản trên server cô lập + assert invariant |
| `runner.ts` | Chạy hàng loạt kịch bản headless |
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

## Thêm kịch bản

Thêm một entry vào mảng `scenarios` trong `scenarios.ts`. Mỗi bước dùng `Bot`
(`createRoom`, `findMatch`, `joinRoom`, `resign`, `leaveRoom`, `drop`,
`reconnectRoom`…), `await` message từ server, rồi `lab.assertHealthy()`.
`drop()` mô phỏng rớt mạng đột ngột; `close()` là rời êm.
