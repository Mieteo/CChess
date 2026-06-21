# ✅ KẾ HOẠCH TEST — CChess (các mục chưa xác nhận đã test)

> Tài liệu sống — tạo ngày **2026-06-07**, cập nhật **2026-06-21** (chốt test tay D4/M5 + phân loại H4 offline minimax).
> Mục đích: liệt kê **các kịch bản còn tồn đọng chưa test xong** để sắp lịch test dần.
> Phạm vi: tập trung các tính năng **online/multiplayer Sprint 12** (Đấu lại, Chat, Spectate, Reconnect, Matchmaking) + **engine service Pikafish / nút Gợi ý** (Sprint 15 sớm) — phần engine/offline (Sprint 1–7) đã có unit test xanh, không lặp lại ở đây.
> Tham chiếu: [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md), [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md), [`09_BACKEND_SERVER_HOAT_DONG.md`](09_BACKEND_SERVER_HOAT_DONG.md), [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md).
>
> **Trạng thái test tự động 2026-06-20:** Backend `cd cchess-backend && npm test` → **71/71 xanh** (12 file). Flutter `cd cchess && flutter test` → **226/226 xanh** (21 file). Chi tiết ở Nhóm T (§8).
> **Test tay:** đợt 1 (2026-06-12) Nhóm R 11/12, bug R9 sửa cùng ngày; đợt 2 (2026-06-13) **R9 retest PASS → Nhóm R đóng 12/12**, **C8 PASS** (rate-limit nâng 1.5s→2s), **H1–H3 PASS** (tuning best-effort, theo dõi H4), **S1–S12 PASS** → feedback UX sinh 3 case mới S13–S15 (số mắt xem cho người chơi, dialog người xem 1 nút Thoát + tự xem tiếp khi rematch, phòng chờ tự hủy 1 phút) — **đã test tay PASS 2026-06-13 → Nhóm S đóng 15/15** (lưu ý: S15 chỉ chạy đúng sau khi `npm run build` lại backend — server chạy từ `dist/`).
> **Test tay 2026-06-21:** **D4 PASS** (disconnect/reconnect đúng logic người dùng; peer phát hiện sau khoảng 5–10s, hiển thị countdown 59s, quá grace không reconnect lại được), **M5 PASS** (Firebase thật khớp trang Hồ sơ trong app). **H4 phát hiện bug chất lượng offline/minimax:** Pikafish online gợi ý rất tốt/rất mạnh, nhưng offline minimax quá yếu, giống nước random-hợp-lệ; 5 cấp AI đầu trong Luyện tập cũng dễ vì dùng minimax.
> **Kế hoạch sau test 2026-06-21:** bảng chính còn **1 case chưa PASS** (§9): H4 offline/minimax cần nâng chất lượng hoặc tách kỳ vọng rõ so với Pikafish. Các case D4/M5 đã đóng bằng test tay thật.

---

## 0. Quy ước trạng thái

| Ký hiệu | Ý nghĩa |
|---|---|
| `- [ ]` | Chưa test |
| `- [x]` | Đã test, **PASS** |
| `❌ BUG:` | Test **FAIL** — ghi mô tả lỗi ngay sau dòng |
| `⏭️ SKIP` | Tạm bỏ qua (ghi lý do) |

> Khi một mục đã PASS và ổn định, có thể chuyển trạng thái tương ứng sang ✅ trong [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md).

---

## 1. Chuẩn bị môi trường test

**Cần 2 "người chơi" (2 socket).** Có 3 cách:

1. **2 thiết bị/emulator thật** — chuẩn nhất, mỗi máy đăng nhập 1 tài khoản Firebase khác nhau.
2. **1 thiết bị + màn Backend Test** (`/backend-test`, route `routeBackendTest`) — mở console WS thủ công trên Chrome/PC để đóng vai đối thủ.
3. **Solo cùng 1 uid** — server phân màu theo *socket reference* nên 2 socket cùng 1 Firebase uid vẫn chơi được (xem `colorOfSocket` trong [match.ts](cchess-backend/src/match.ts)). Tiện test nhanh nhưng KHÔNG kiểm được ELO 2 chiều thật.

**Chọn backend:**
- **Local** (khuyến nghị khi test logic, xem log): `cd cchess-backend && npm run dev` rồi build app với
  `flutter run --dart-define=CCHESS_BACKEND_URL=ws://<LAN-IP>:8080` (chú ý `ws://` không phải `wss://`).
- **Production**: mặc định `wss://cchess-backend.onrender.com` (Render free tier — **ngủ sau 15 phút idle**, lần kết nối đầu chờ ~30–60s khi máy chủ wake).

**Mẹo quan sát:** mở log backend song song — mỗi event in ra `[match] / [rematch] / [spectate] / [matchmaking]` rất dễ đối chiếu kết quả mong đợi.

---

## 2. Nhóm R — Đấu lại (Rematch) — ✅ **ĐÓNG 12/12 PASS** (đợt 1: 2026-06-12, retest R9: 2026-06-13)

> Code liên quan: [online_game_screen.dart](cchess/lib/presentation/online/online_game_screen.dart) (`_showResultDialog`), [online_match_controller.dart](cchess/lib/presentation/online/online_match_controller.dart) (`offerRematch`/`declineRematch`/handlers), [server.ts](cchess-backend/src/server.ts) (`rematch-offer`/`rematch-decline`), [match.ts](cchess-backend/src/match.ts) (`startRematch`).

- [x] **R1 — Hiện nút Đấu lại sau ván kết thúc bình thường.** Kết ván bằng chiếu bí (hoặc xin thua / hết giờ) → dialog kết quả hiện **"Về Đối Đầu"** + **"🔄 Đấu lại"**; tiêu đề đúng (Thắng/Thua/Hòa), dòng "Lý do" hiển thị tiếng Việt (Chiếu bí / Xin thua / Hết giờ), có dòng ELO.
- [x] **R2 — Mời đấu lại (offer).** Bấm "Đấu lại" → dialog đổi sang **spinner + "Đang chờ đối thủ đồng ý đấu lại…"**, còn nút **"Hủy"** + "Về Đối Đầu". Bên đối thủ thấy banner **"Đối thủ muốn đấu lại!"** + nút **"Từ chối"/"Đồng ý"**.
- [x] **R3 — Cả hai đồng ý → ván mới.** Khi cả 2 cùng mời/đồng ý:
  - Dialog kết quả **tự đóng** ở cả 2 máy.
  - Bàn cờ reset về thế ban đầu, đồng hồ reset đúng mức clock đã chọn.
  - **Màu đổi chỗ** (ai vừa đi Đỏ giờ đi Đen) — kiểm strip tên/màu trên–dưới.
  - Không còn highlight ô chọn cũ từ ván trước.
- [x] **R4 — Đối thủ từ chối lời mời của mình.** Đang chờ (R2) mà đối thủ bấm "Từ chối" → mình thấy text đỏ **"Đối thủ đã từ chối đấu lại."**, dialog quay lại trạng thái mặc định (Về Đối Đầu + Đấu lại).
- [x] **R5 — Tự hủy lời mời.** Đang chờ (R2) bấm **"Hủy"** → quay về mặc định ở máy mình; đối thủ nhận thông báo huỷ (banner "muốn đấu lại" biến mất).
- [x] **R6 — Đối thủ mời trước, mình "Đồng ý".** Đối thủ mời (mình thấy banner) → bấm **"Đồng ý"** → ván mới bắt đầu (như R3).
- [x] **R7 — Đối thủ mời trước, mình "Từ chối".** Bấm **"Từ chối"** → dialog quay về mặc định; đối thủ nhận thông báo từ chối.
- [x] **R8 — Kết ván do đối thủ disconnect → KHÔNG cho đấu lại.** Nếu ván kết thúc với lý do `disconnect` → dialog chỉ có **"Về Đối Đầu"**, banner **"Đối thủ đã rời — không thể đấu lại."**, không có nút Đấu lại.
- [x] **R9 — Đối thủ rời rồi mình mới bấm Đấu lại (xử lý lỗi êm).** Đối thủ bấm "Về Đối Đầu" thoát hẳn → mình bấm "Đấu lại" → nhận lỗi gracefully + dialog cập nhật ngay banner "Đối thủ đã rời", **không** văng phase=error. ✅ **RETEST PASS 2026-06-13** — banner "đối thủ đã rời" hiện rất nhanh sau khi A thoát.
  - ❌ **BUG (2026-06-12, test tay đợt 1):** A thoát trận xong, trong ~10s đầu B bấm "Đấu lại" vẫn nhận "Đang chờ đối thủ đồng ý…"; phải đợi ~10s (heartbeat server giết socket A) rồi bấm lại mới ra "Không thể đấu lại — đối thủ đã rời phòng".
  - ✅ **ĐÃ SỬA 2026-06-12** (3 nguyên nhân gốc):
    1. `game_socket_service.dart` xoá `roomId` ngay khi `game-ended` → `leave()` của A **không gửi `leave-room`** (chỉ đóng socket). → Giữ `roomId` đến khi `left-room` thật.
    2. Nút back app-bar + back hệ thống Android của người chơi **không gọi `leave()`** (chỉ `context.go`) → socket A "ma" còn trong phòng tới khi heartbeat dọn (~5–10s). → Gom về `_onBackPressed()` duy nhất + `PopScope`; đang chơi thì hỏi xác nhận rồi resign+leave.
    3. Client B **bỏ qua sự kiện `peer-left`** → dù server báo ngay, dialog không đổi. → Controller xử lý `peer-left` khi phase=ended: set `opponentLeftRoom`, dialog lập tức hiện banner "Đối thủ đã rời — không thể đấu lại." và ẩn nút Đấu lại; `offerRematch` chặn local không cần round-trip.
  - Test tự động đã thêm: backend `server.test.ts` "R9: leave-room after game end broadcasts peer-left + rematch fails fast"; Flutter 4 test nhóm "R9 — opponent left" trong `online_match_controller_test.dart`. Retest tay 2026-06-13: **PASS** → Nhóm R đóng 12/12.
- [x] **R10 — Vòng lặp nhiều ván.** Sau R3, chơi hết ván 2 → dialog kết quả ván 2 hiện đúng, lại có nút Đấu lại; lặp được nhiều lần không treo / không double-dialog.
- [x] **R11 — ELO/Profile cập nhật mỗi ván rematch.** Mỗi ván ranked sau rematch đều ghi ELO riêng; sau khi đóng dialog → màn Hồ Sơ phản ánh ELO/win-loss mới (auto-refresh).
- [x] **R12 — Spectator khi 2 bên rematch.** Nếu có người đang xem trong phòng lúc rematch → họ nhận `game-start` ván mới (board reset), không bị kẹt ở màn kết quả.

---

## 3. Nhóm C — Chat trong ván

> Code: [online_game_screen.dart](cchess/lib/presentation/online/online_game_screen.dart) (chat sheet), [game_socket_service.dart](cchess/lib/data/services/game_socket_service.dart) (`sendChatMessage`), [server.ts](cchess-backend/src/server.ts) (`chat-message` + rate limit).

- [x] **C1 — Gửi/nhận realtime giữa 2 người.** ✅ AUTO PASS 2026-06-20: backend integration `server.test.ts` broadcast tới cả hai kỳ thủ; Flutter controller append/dedup/lọc room trong `online_match_controller_test.dart`.
- [x] **C2 — Badge số tin nhắn.** ✅ AUTO PASS 2026-06-20: widget test `OnlineChatButton` hiển thị `Chat (n)` và disable đúng theo `canChat`.
- [x] **C3 — Rate limit.** ✅ AUTO PASS 2026-06-20: backend integration trả `chat-rate-limited`; Flutter controller map sang **"Bạn gửi chat quá nhanh."** *(Nâng từ 1.5s → 2s ngày 2026-06-13 theo feedback test tay C8.)*
- [x] **C4 — Giới hạn 120 ký tự.** ✅ AUTO PASS 2026-06-20: backend integration reject >120 ký tự; Flutter controller chặn client trước khi gửi.
- [x] **C5 — Spectator chat.** ✅ AUTO PASS 2026-06-20: backend integration spectator nhận history và gửi chat tới cả hai kỳ thủ; Flutter controller cho spectator nhận chat.
- [x] **C6 — Khôi phục lịch sử chat sau reconnect.** ✅ AUTO PASS 2026-06-20: backend integration snapshot `reconnected.chat`; Flutter controller restore history đúng thứ tự.
- [x] **C7 — Chặn chat khi ván đã kết thúc.** ✅ AUTO PASS 2026-06-20: backend integration trả `not-playing`; Flutter controller `canChat=false` không gửi sau `game-ended`.
- [x] **C8 — Chip tin nhắn nhanh (preset) — code 2026-06-11, test tay PASS 2026-06-13.** Hàng chip preset (Chào bạn 👋 / Chúc may mắn 🍀 / …) hiện trên ô nhập trong chat sheet; chạm 1 chip → gửi ngay như chat thường; chạm 2 chip liên tiếp < 2s → dính rate-limit như C3; chip bị disable khi `canChat=false`. *(Theo feedback đợt test: rate-limit server nâng 1.5s → 2s.)*

---

## 4. Nhóm S — Spectate + danh sách ván đang diễn ra + share link — ✅ **ĐÓNG 15/15 PASS** (test tay 2026-06-13)

> Code: [online_lobby_screen.dart](cchess/lib/presentation/online/online_lobby_screen.dart) (active rooms, deep-link), [rooms.ts](cchess-backend/src/rooms.ts) + [server.ts](cchess-backend/src/server.ts) (`list-active-rooms`, `spectate-room`, landing page `/r/:id`), [room_share.dart](cchess/lib/presentation/online/room_share.dart) + [share_room_sheet.dart](cchess/lib/presentation/online/share_room_sheet.dart).

- [x] **S1 — Danh sách ván đang diễn ra.** Lobby hiển thị các phòng `playing` (roomId, số nước, số người xem, đồng hồ), sắp xếp theo thời gian bắt đầu mới nhất.
- [x] **S2 — Xem bằng room ID.** Nhập/chạm 1 phòng → vào màn xem, nhận snapshot moves/clock/chat, bàn cờ cập nhật theo nước đi realtime.
- [x] **S3 — Read-only.** Spectator KHÔNG chọn/đi quân được, KHÔNG có nút Xin thua.
- [x] **S4 — Đếm người xem.** `spectatorCount` tăng/giảm khi có người vào/ra (cả ở header màn xem lẫn list lobby).
- [x] **S5 — Dừng xem.** Bấm back/stop → quay lại lobby sạch sẽ, server nhận `stop-spectating`.
- [x] **S6 — Refresh list.** Làm mới danh sách phản ánh phòng mới tạo / phòng vừa kết thúc (biến mất khỏi list).
- [x] **S7 — Chia sẻ phòng từ lobby (đang chờ đối thủ).** Tạo phòng riêng → bấm **"Chia sẻ phòng (link / QR)"** → bottom sheet hiện QR + mã phòng + nút **Sao chép link / Chia sẻ**; QR quét ra link `/r/<ID>?mode=join`.
- [x] **S8 — Chia sẻ link xem từ tile "ván đang diễn ra".** Icon share trên mỗi tile → sheet "Mời xem ván" (link `/r/<ID>` không có `mode=join`).
- [x] **S9 — Chia sẻ từ app bar màn ván.** Đang chơi hoặc đang xem → icon share trên app bar mở sheet "Mời xem ván".
- [x] **S10 — Sao chép & native share.** Nút "Sao chép link"/"Sao chép mã" → clipboard + snackbar; nút "Chia sẻ" mở native share sheet (Android/iOS); desktop không có handler → fallback copy.
- [x] **S11 — Deep-link in-app.** Mở route `online-lobby?spectate=<ID>` → tự kết nối + vào xem; `?join=<ID>` → tự vào đánh. (Test nhanh qua [backend-test] hoặc điều hướng nội bộ; OS-level deep link chưa wire.)
- [x] **S12 — Landing page backend.** Mở `https://cchess-backend.onrender.com/r/<ID>` trên trình duyệt → trang hiện mã phòng + nút "Sao chép mã"; `?mode=join` đổi tiêu đề sang "Lời mời vào phòng"; mã sai định dạng → HTTP 400.

> **Feedback đợt test S 2026-06-13 → đã code cùng ngày, sinh 3 case mới (S13–S15):**
> 1. Người chơi cũng phải thấy số mắt xem (trước chỉ người xem thấy).
> 2. Dialog kết quả phía người xem có 2 nút "Về Đối Đầu"/"Đấu lại" là vô lý → chỉ còn 1 nút **"Thoát"**; nếu 2 kỳ thủ đấu lại thì dialog tự đóng và xem tiếp; kỳ thủ rời thì hiện banner khép trận. *(Sửa kèm 1 bug tiềm ẩn: rematch `game-start{yourColor:null}` từng biến người xem thành "người chơi Đỏ" trong state client — chạm quân sẽ văng phase=error.)*
> 3. Phòng chờ không ai vào phải tự hủy (~1 phút) → server TTL `room-expired`.

- [x] **S13 — Người chơi thấy số người xem.** Trong ván (và sau khi kết thúc), cả 2 người chơi thấy 👁 + số ở góc phải app bar; số tăng/giảm realtime khi viewer vào/ra (đồng bộ với S4 phía người xem).
- [x] **S14 — Dialog kết quả của người xem.** Ván kết thúc → người xem thấy "Đỏ/Đen thắng + Lý do" với đúng **1 nút "Thoát"** (bấm → rời phòng về Đối Đầu, server nhận spectator-left). Nếu 2 kỳ thủ bấm Đấu lại → dialog **tự đóng**, tiếp tục xem ván mới (bàn reset, không tương tác được). Nếu 1 kỳ thủ thoát sau ván → banner "Một kỳ thủ đã rời — trận đấu khép lại."
- [x] **S15 — Phòng chờ tự hủy sau 1 phút.** ✅ PASS 2026-06-13 (chỉ pass sau khi `npm run build` lại backend — server cũ chạy `dist/` chưa có code TTL). Tạo phòng riêng, không ai vào → sau ~60s lobby tự quay về màn chính + thông báo "Phòng đã hủy — không có đối thủ vào sau 1 phút"; mã phòng cũ join/quét QR → `room-not-found`. Có người vào trước 60s → ván bắt đầu bình thường, không bị hủy ngang.

---

## 5. Nhóm D — Disconnect / Reconnect (grace 60s)

> Code: [server.ts](cchess-backend/src/server.ts) (`reconnect-room`, grace timer, heartbeat app-level), [online_game_screen.dart](cchess/lib/presentation/online/online_game_screen.dart) (`_remainingGraceSec` banner, banner reconnecting, listener `connectivity_plus`), [game_socket_service.dart](cchess/lib/data/services/game_socket_service.dart) (ping/watchdog/`onConnectionLost`), [online_match_controller.dart](cchess/lib/presentation/online/online_match_controller.dart) (auto-reconnect giữa ván), [reconnect_store.dart](cchess/lib/data/services/reconnect_store.dart).

> **Bug D1 (test tay 2026-06-13) → ✅ ĐÃ SỬA & PASS 2026-06-14 (sau redeploy Render):** Triệu chứng: B mất **~3 phút** mới thấy banner mất kết nối, và A bật lại wifi **không chơi tiếp được** (không nhận nước đi). Nguyên nhân: (1) server chỉ phát hiện rớt qua TCP timeout vì ping/pong **WS control-frame bị proxy Render che**; (2) client **không có heartbeat riêng** và **không tự reconnect giữa ván** (chỉ reconnect khi mở lại app từ lobby). Sửa: **heartbeat tầng ứng dụng 2 đầu** (client gửi `{ping}` mỗi 5s, server `{pong}` + sweep `lastSeenAt`>15s → terminate ngay) ⇒ phát hiện ~15s; client thêm **watchdog 15s + auto-reconnect giữa ván** + **`connectivity_plus`**; guard tránh push trùng màn chơi. ⚠️ **Server chạy từ `dist/` → bắt buộc `npm run build` + REDEPLOY Render** mới có hiệu lực.

> **Bug D2 (test tay 2026-06-14) → ĐÃ SỬA & AUTO PASS 2026-06-20:** reconnect kịp nhưng (1) **ván bị reset về bàn cờ gốc**, (2) state kẹt — server/lobby vẫn coi A,B "đang đánh" nên tạo/vào phòng mới hiện trạng thái xanh "đang đánh" mà **không có bàn cờ** ⇒ chặn D3/D4/D5. Nguyên nhân: client **reconnect chồng chéo** — `connectivity_plus` bắn nhiều sự kiện + timer định kỳ → nhiều chu kỳ `disconnect/connect` đua nhau, làm server churn socket (re-grace lặp) và client xử lý nhầm snapshot. **Xác nhận server + client replay ĐÚNG khi reconnect sạch** (test tự động: server `moves` được giữ qua liveness drop; controller replay nước đi). Sửa: thay vòng lặp reconnect bằng **state machine 1-attempt** (guard `_attemptInFlight` + `_awaitingResponse` + timeout 8s) → gộp mọi burst thành **đúng 1 lần** reconnect; mid-game dùng `readRoomId()` (bỏ gate 70s, để server grace 60s là bound). Test tự động bổ sung trong **T15/T25**; phần bật/tắt Wi-Fi và OS lifecycle thật giữ ở D4.

> **Bug D2 đợt 2 (test tay 2026-06-15) → ĐÃ SỬA tiếp:** vẫn loạn — A đi được nhưng **B không đi được** (nước A không tới B), thoát ra vào lại hiện "đang đánh" không bàn cờ, và **A thoát vẫn xem được trận A–B** (phòng cũ kẹt `playing`). Nguyên nhân còn lại: (1) **state rò rỉ trên Render** từ các lần test hỏng trước (phòng/socket chết còn trong RAM); (2) `attachReconnectingSocket` **không xoá socket cũ** khỏi `room.members` → broadcast `opponent-move` tới socket chết; (3) reconnect store cũ làm lobby **tự nối lại phòng ma** mỗi lần vào → kẹt. Sửa: server **evict socket cũ** khi reconnect (members luôn sạch); client **clear store + về lobby** khi reconnect bị từ chối (hết vòng lặp nối phòng ma). ⚠️ **Bắt buộc: REDEPLOY/restart Render** (xoá state rò rỉ + nạp fix server) **+ rebuild app**; sau đó lần reconnect tới phòng ma sẽ tự fail → store tự xoá. Test: rooms eviction + controller "lobby nối phòng ma".

- [x] **D1 — Phát hiện rớt nhanh + banner.** Đối thủ tắt mạng → trong **~15s** (trước đây ~3 phút) mình thấy banner vàng **"Đối thủ mất kết nối — còn 60s…"** đếm ngược. ✅ **PASS 2026-06-14**.
- [x] **D2 — Reconnect kịp (mở lại app HOẶC bật lại wifi giữa ván).** ✅ AUTO PASS 2026-06-20: backend integration restore snapshot/move list sau drop; liveness test xác nhận reconnect không reset bàn; Flutter controller replay move list, single-flight reconnect và xoá banner `peer-reconnected`. Phần bật/tắt Wi-Fi thật vẫn nằm trong D4 manual.
- [x] **D3 — Hết grace.** ✅ AUTO PASS 2026-06-20: `server.disconnect.test.ts` rút ngắn grace, xác nhận `game-ended{reason:"disconnect"}` đúng người thắng và reconnect muộn bị reject; Flutter controller chuyển sang ended + clear banner.
- [x] **D4 — Lifecycle nền vs kill.** ✅ TEST TAY PASS 2026-06-21: reconnect/disconnect đúng logic người dùng; khoảng **5–10s** sau khi người dùng A bị disconnect thì người dùng B nhận thông báo; hiển thị đếm ngược **59s** để A connect lại ván đấu; quá grace thì A **không thể reconnect** lại ván.
- [x] **D5 — Double-disconnect.** ✅ AUTO PASS 2026-06-20: `server.disconnect.test.ts` xác nhận cả 2 người chơi cùng rớt vẫn reconnect được theo cửa sổ riêng; người rớt trước hết grace trước thì thua; room không leak/không còn trong active list khi cả 2 vắng. Phần quan sát UI 2 thiết bị thật được gom vào D4/manual visual sanity, không tính là case tự động.

---

## 6. Nhóm M — Matchmaking + ELO + Clock

> Code: [matchmaking.ts](cchess-backend/src/matchmaking.ts), [elo.ts](cchess-backend/src/elo.ts), [persistence.ts](cchess-backend/src/persistence.ts).

- [x] **M1 — Ghép trận tự động.** ✅ AUTO PASS 2026-06-20: `server.test.ts` integration mới chạy 2 socket `find-match` → `match-found` cùng room + `game-start`; controller test nhận `match-found`.
- [x] **M2 — Nới tolerance theo thời gian.** ✅ AUTO PASS 2026-06-20: `matchmaking.test.ts` điều khiển `Date.now()` để xác nhận ELO gap lớn chỉ ghép sau khi tolerance nới đủ.
- [x] **M3 — Huỷ tìm trận.** ✅ AUTO PASS 2026-06-20: `server.test.ts` integration mới xác nhận `cancel-matching` trả `matching-canceled{removed:true}` và xoá queue; controller test cũng phủ command/ack.
- [x] **M4 — Clock per-room.** ✅ AUTO PASS 2026-06-20: `server.test.ts` kiểm `create-room` và `find-match` clock chọn truyền tới `game-start.clock` đủ 2 bên; controller test kiểm clock gửi xuống socket.
- [x] **M5 — ELO 2 chiều.** ✅ TEST TAY PASS 2026-06-21: lõi đã AUTO PASS bằng `elo.test.ts`, `persistence.test.ts` fake-store và `server.test.ts` fake persist (`game-ended.elo` đúng shape); phần Firebase thật được kiểm bằng cách đọc dữ liệu trực tiếp trên Firebase và so sánh với trang **Hồ sơ** người dùng trong app — kết quả trùng khớp.

---

## 7. Nhóm G — Vòng đời ván & dialog kết quả

- [x] **G1 — Chiếu bí.** ✅ 2026-06-19 (T23): backend auto test xác nhận nước chiếu bí bắn `game-ended` với result đúng, reason=`checkmate`.
- [x] **G2 — Hết giờ.** ✅ AUTO PASS 2026-06-20: `match.test.ts` và lab scenario rút ngắn clock xác nhận timeout xử thua đúng.
- [x] **G3 — Xin thua.** ✅ AUTO PASS 2026-06-20: `server.test.ts` integration xác nhận `game-ended{reason:"resign"}` và idempotency không bắn double end.
- [x] **G4 — Nội dung dialog kết quả.** ✅ AUTO PASS 2026-06-20: `online_result_format_test.dart` + widget test `OnlineResultDialog` phủ title Thắng/Thua/Hòa, lý do tiếng Việt, ELO delta, actions rematch/spectator.
- [x] **G5 — Auto-refresh hồ sơ.** ✅ AUTO PASS 2026-06-20: `online_result_format_test.dart` test `refreshProfileAfterRankedGame` gọi `refreshFromCloud` rồi `refreshProfile`, có guard unmounted.
- [x] **G6 — Rollback nước đi.** ✅ AUTO PASS 2026-06-20: `online_match_controller_test.dart` kiểm optimistic move rollback khi server trả `illegal-move`.

---

## 7b. Nhóm H — Nút Gợi ý in-game — **3/4 PASS; H4 mở bug chất lượng offline/minimax**

> Code: [game_screen.dart](cchess/lib/presentation/game/game_screen.dart) (`_onHint`), [game_controller.dart](cchess/lib/presentation/game/game_controller.dart) (`showHint`/`clearHint`), [game_action_bar.dart](cchess/lib/presentation/game/widgets/game_action_bar.dart), [chess_board.dart](cchess/lib/widgets/chess/chess_board.dart) (marker xanh ngọc), [engine_router.dart](cchess/lib/core/chess_engine/engine_router.dart). Logic controller đã có test tự động (T11).

- [x] **H1 — Nút Gợi ý hoạt động (online engine).** Đang ván bot, đến lượt mình, server engine chạy (`CCHESS_ENGINE_URL` trỏ đúng) → bấm 💡 Gợi ý → 2 ô from/to sáng **xanh ngọc** (khác màu vàng của nước cuối); icon chuyển hourglass trong lúc chờ.
- [x] **H2 — Fallback offline.** Tắt mạng / không cấu hình engine URL → bấm Gợi ý → vẫn nhận gợi ý từ minimax local + snackbar "Gợi ý offline (minimax)…".
- [x] **H3 — Gợi ý tự xoá đúng lúc.** Sau khi đi nước (bất kỳ), undo, hoặc ván mới → marker gợi ý biến mất; bấm Gợi ý khi chưa đến lượt/bot đang nghĩ → nút disabled.

> **Feedback đợt test 2026-06-13:** gợi ý "hơi lâu, hơi kém" → **đã tuning cùng ngày** (T13): chế độ best-effort cho hint/analysis trong `BotEngine` — bỏ delay nhân tạo `minThinkTime` 1.2s, bỏ randomness, **iterative deepening có ngân sách ~2s** (thế nhẹ/tàn cuộc tự đào sâu tới depth 6 — mạnh hơn trước; giữa ván nặng trả kết quả depth đã xong thay vì treo). Lưu ý: chất lượng offline vẫn bị chặn bởi minimax + evaluator đơn giản — gợi ý "mạnh thật" đến từ Pikafish server-side khi app dùng `cchess-engine` remote thật (xem [`11`](11_KE_HOACH_TICH_HOP_ENGINE.md)).
> **Feedback test tay 2026-06-21:** nhánh **online/Pikafish PASS về chất lượng** — nước đi rất tốt, rất mạnh. Nhánh **offline/minimax FAIL về chất lượng** — nước đi quá yếu, giống random-hợp-lệ theo luật; hiện tượng tương tự ở chế độ **Luyện tập — đấu với AI** tại 5 cấp đầu dùng minimax, trong khi cấp Pikafish rất mạnh.

- [ ] **H4 — Đánh giá lại tốc độ/chất lượng gợi ý sau tuning.** ❌ BUG 2026-06-21: **Pikafish online đạt kỳ vọng** (nước tốt/mạnh), nhưng **offline minimax quá yếu** và có cảm giác như chọn nước random-hợp-lệ; cần nâng cấp bot offline/minimax hoặc tách rõ kỳ vọng chất lượng giữa fallback offline và engine Pikafish.

---

## 8. Nhóm T — Test tự động ✅ XANH TOÀN BỘ (cập nhật 2026-06-20)

> Mục này là **viết test code**, không phải test tay. Ưu tiên làm để khỏi phải test tay lặp lại các case ở trên.
> **Trạng thái 2026-06-20:** T1–T25 đều xanh. Backend `cd cchess-backend && npm test` → **71/71** (12 file). Flutter `cd cchess && flutter test` → **226/226** (21 file). `backend-ci` còn chạy thêm lab/load/fuzz ngoài `npm test`.

- [x] **T1 — `rooms.test.ts`** (backend): spectator read-only, spectator leave, active room filtering. *(3 test, pass)*
- [x] **T2 — `match.test.ts`** (backend): `startMatch` (gán màu/clock/turn/engine), `applyMove` hợp lệ/`not-your-turn`/`illegal-move`/`not-player`/`time-out` + trừ đồng hồ, **`startRematch`** (đổi màu + reset clock/engine/moves + clear cờ offer; fail khi <2 người). *(8 test, pass)*
- [x] **T3 — `server.test.ts` rematch handshake** (backend, **integration WS thật** qua `createCChessServer` + 2 client `ws` trên cổng ephemeral, auth/persist được inject giả): cả 2 `rematch-offer` → cả 2 nhận `game-start{rematch:true}` với **màu đã đổi chỗ** (cùng `roomId`); `rematch-decline` → bên mời nhận `rematch-declined{from}`; `rematch-offer` khi ván **chưa kết thúc** → `error{not-finished}`. *(3 test, pass — đã dựng được server test harness in-process, không cần Firebase nhờ tách `server.ts` thành factory + guard `CCHESS_NO_LISTEN`.)*
- [x] **T4 — `OnlineMatchController` test** (Flutter, fake socket): `offerRematch` set cờ + gửi lệnh (no-op khi chưa ended); nhận `rematch-offered`/`rematch-declined` set/clear cờ đúng; `game-start` rematch reset cờ + về playing; `_onError` giữ phase=ended khi lỗi rematch (`no-opponent`). *(test tại [online_match_controller_test.dart](cchess/test/online/online_match_controller_test.dart))*
- [x] **T5 — `OnlineMatchController` core** (Flutter): `_onGameEnded` set result/reason + clear reconnect store; `attemptMove` optimistic (flip turn + gửi move) + rollback khi server `illegal-move`. *(gộp chung file test ở trên — tổng 8 test, pass)*
- [x] **T6 — `room_share_test.dart`** (Flutter, A6 share link): `normalizeRoomId`/`isValidRoomId`, `linkFor` (spectate vs `mode=join`, strip trailing slash), `inviteText`, `roomIdFromLink` (bare code / `/r/` / `cchess://` / `?spectate|join=` / junk→null / round-trip), `isJoinLink`. *(17 test, pass)*
- [x] **T7 — `server.test.ts` reconnect integration** (backend, integration WS): chơi 1 nước hợp lệ → đỏ rớt mạng (đóng socket) → đối thủ nhận `peer-disconnected{graceMs>0}` → đỏ `reconnect-room` trong grace → nhận `reconnected` snapshot đúng (`yourColor`, `moves`, `currentTurn`) + đối thủ nhận `peer-reconnected`. *(1 test, pass — tự động hoá phần lõi Nhóm D2.)*
- [x] **T8 — `server.test.ts` chat integration** (backend, integration WS): `chat-message` phát cho cả 2 bên kèm `from`; gửi liên tiếp → `error{chat-rate-limited}`; >120 ký tự → `error{invalid-chat}`; sau `game-ended` → `error{not-playing}`. *(2 test, pass — tự động hoá Nhóm C1/C3/C4/C7.)*
- [x] **T9 — engine-service tests** (backend, thêm 2026-06-07 cùng đợt code engine Pikafish — ghi nhận vào tài liệu 2026-06-11): [`uci_parser.test.ts`](cchess-backend/src/engine-service/uci_parser.test.ts) parse `info`/`bestmove`/mate-score *(3 test)*; [`engine_pool.test.ts`](cchess-backend/src/engine-service/engine_pool.test.ts) giới hạn concurrency + reject khi queue đầy *(2 test)*; [`engine-service/server.test.ts`](cchess-backend/src/engine-service/server.test.ts) HTTP service đòi auth + trả best-move có cache *(1 test, fake engine — KHÔNG cần binary Pikafish thật)*. *(6 test, pass)*
- [x] **T10 — `server.disconnect.test.ts` double-disconnect** (backend, integration WS thật, mới 2026-06-11, grace rút ngắn qua env `CCHESS_RECONNECT_GRACE_MS`): cả 2 cùng rớt → cả 2 reconnect được trong grace (regression cho bug ghi-đè marker cũ) + snapshot có `peerInGrace`; cả 2 rớt không ai quay lại → người rớt trước bị xử thua `disconnect` (spectator quan sát `game-ended`). *(2 test, pass — tự động hoá phần lõi D5.)*
- [x] **T11 — hint tests trong `game_controller_test.dart`** (Flutter, mới 2026-06-11): `showHint` lưu nước hợp lệ / từ chối sai bên / từ chối sai luật; hint tự xoá sau khi đi nước, undo, ván mới; `setHintThinking`/`clearHint`. *(6 test, pass)*
- [x] **T12 — R9 regression tests** (mới 2026-06-12, sau bug test tay): backend `server.test.ts` thêm "leave-room sau game end → `peer-left` broadcast ngay + `rematch-offer` fail nhanh `no-opponent`" *(1 test)*; Flutter `online_match_controller_test.dart` thêm nhóm "R9 — opponent left": `peer-left` khi ended set `opponentLeftRoom` + clear cờ mời, `offerRematch` chặn local, `peer-left` ngoài phase ended chỉ log, `game-start` mới reset cờ *(4 test)*. *(5 test, pass)*
- [x] **T13 — `bot_engine_test.dart` best-effort hint** (Flutter, mới 2026-06-13 sau feedback "gợi ý hơi lâu/hơi kém"): best-effort trả nước hợp lệ trong ngân sách thời gian, KHÔNG dính delay `minThinkTime`; bot mode thường vẫn giữ delay tối thiểu. *(2 test, pass)*
- [x] **T14 — spectator UX + waiting-room TTL** (mới 2026-06-13 theo feedback test Nhóm S): backend [`server.waitingroom.test.ts`](cchess-backend/src/server.waitingroom.test.ts) — phòng chờ không ai vào hết TTL → `room-expired` + id hết hiệu lực; có người vào trước TTL → game-start, KHÔNG bị hủy ngang *(2 test)*; Flutter `online_match_controller_test.dart` — rematch `game-start{yourColor:null}` giữ người xem ở `spectating` (không thành "người chơi Đỏ", không lưu reconnect store); `room-expired` đưa người tạo phòng về authed + thông báo *(2 test)*. *(4 test, pass)*
- [x] **T15 — D1/D2 reconnect rớt-mạng-giữa-ván** (mới 2026-06-14, mở rộng 06-15 sau bug D2): backend [`server.liveness.test.ts`](cchess-backend/src/server.liveness.test.ts) — `ping`→`pong` giữ socket sống; client im lặng quá `LIVENESS_TIMEOUT_MS` → terminate, peer nhận `peer-disconnected` **<2s**; **D2 regression: đánh 1 nước → rớt liveness → reconnect → snapshot vẫn giữ đủ `moves`** (board không reset) *(3 test)*; Flutter `online_match_controller_test.dart` nhóm "D1 — mid-game auto-reconnect": mất kết nối → `reconnecting` → `authed` tự gửi `reconnect-room` → `reconnected` về `playing`; **replay moves đúng (board không reset)**; **burst connectivity gộp thành đúng 1 reconnect** (single-flight); server từ chối → dừng + clear; không có ván → KHÔNG reconnect *(6 test)*. *(9 test, pass)*

- [x] **T16 — Đợt 1 tự động hóa M/G/ELO** (mới 2026-06-19, Phase A3a/A4 + P-C1 của §8b): backend [`matchmaking.test.ts`](cchess-backend/src/matchmaking.test.ts) — `toleranceForWait()` nới đúng nấc; `tryMatch()` ghép trong tolerance (M1), nới theo thời gian chờ (M2), không tự ghép cùng uid, chọn đối thủ ELO gần nhất, enqueue idempotent + dequeue *(7 test)*; [`elo.test.ts`](cchess-backend/src/elo.test.ts) — `computeElo` K=32, thắng equal ±16, zero-sum, upset > favourite, hòa equal=0, hòa lệch ELO kéo về nhau (M5/G4) *(6 test)*; `server.test.ts` thêm **G3** resign → `result/reason` đúng + **idempotency** (resign lần 2 không bắn `game-ended` thứ 2), **P-C1** inject fake persist → map `game-ended.elo` đúng shape cho cả 2 bên (M5/G4/R11) + `elo:null` khi persist rỗng, **M4** clock chọn lúc create-room tới đủ 2 bên *(5 test)*. *(18 test, pass; M1/M3 WebSocket flow được đóng bổ sung ở T25.)* G1 checkmate được đóng riêng ở T23 bằng fixture FEN ổn định.

- [x] **T17 — Đợt 2 tự động hóa Flutter (Phase B B1/B2/B4 + P-D3 CI)** (mới 2026-06-19): [`online_match_controller_test.dart`](cchess/test/online/online_match_controller_test.dart) thêm nhóm **B1 — chat** (C1 append + dedup + lọc sai room, C3 rate-limit→VN, C4 invalid + guard 120 ký tự client, C5 spectator nhận chat, C6 reconnect khôi phục history, C7 ended chặn gửi) *(11 test)* + nhóm **B2 — reconnect/lifecycle** (D2 `peer-disconnected`/`peer-reconnected` + grace data, spectator không vào countdown, D3 hết grace → `game-ended{disconnect}`, D4 `disconnectKeepingReconnectState` giữ store / `leave` xóa / `tryAutoReconnect`) *(8 test)*; tách [`online_result_format.dart`](cchess/lib/presentation/online/online_result_format.dart) (title G4, reason VN, `OnlineEloDelta` dấu/hướng, grace giây, `refreshProfileAfterRankedGame` G5 guard-unmount) + [`online_result_format_test.dart`](cchess/test/online/online_result_format_test.dart) *(16 test)*; screen chỉ delegate lại, không đổi hành vi. **Flutter CI** [`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) chạy `flutter analyze` + `flutter test` khi chạm `cchess/**`. *(35 test mới, pass — `flutter test` 163→**198 xanh**, `flutter analyze` sạch.)* Phần D4 OS-thật đã PASS test tay 2026-06-21; `peerInGrace` vẫn chưa wire phía client vì không bắt buộc cho case chính.

- [x] **T18 — Đợt 3 đóng lõi C/D/M (A1 chat + A2 reconnect D3 + B3 matchmaking)** (mới 2026-06-19): backend `server.test.ts` thêm **A1** (C5 spectator history + gửi/nhận chat, C6 reconnect khôi phục `chat`) *(2 test)*; `server.disconnect.test.ts` thêm **A2/D3** (single-drop hết grace → forfeit + room freed, reconnect sau grace bị từ chối) *(2 test)*; Flutter `online_match_controller_test.dart` thêm nhóm **B3** (findMatch/createRoom truyền clock, cancelMatching, matching/match-found/matching-canceled/room-created, active-rooms parse, gate phase) *(7 test)*. *(11 test mới, pass — backend `npm test` 51→**55 xanh**, Flutter `flutter test` 198→**205 xanh**.)*

- [x] **T19 — Đợt 4 Phase C persistence (P-C2 adapter + P-C3 idempotency)** (mới 2026-06-19): refactor `persistence.ts` theo hướng **adapter** — tách hàm thuần `buildPersistPlan()` (current ELO → toàn bộ writes: ELO mới, counters, 2 mirror `game_records`) khỏi `PersistStore.commit()` (ranh giới nguyên tử; adapter Firestore vẫn dùng `runTransaction`). Test inject **fake in-memory store** (không cần Firebase): mới [`persistence.test.ts`](cchess-backend/src/persistence.test.ts) — **P-C2** winner +điểm / loser −điểm / draw 0 đúng K=32, counters `wins/losses/draws/totalGames` đúng phía, **mirror `game_records` 2 chiều** (opponent/humanColor/result perspective/eloChange/eloBefore/eloAfter), đọc đúng **ELO hiện tại** từng người (không lấy default), guard skip khi chưa finished / thiếu uid·result *(10 test)*; **P-C3 idempotency**: adapter kiểm `game_records/{gameId}` đã tồn tại → bỏ qua (no-op), test double-persist cùng `gameId` không double-counter + `server.test.ts` thêm **P-C3** đếm persist gọi đúng **1 lần** khi 2 end-condition đua *(1 test)*. *(11 test mới, pass — backend `npm test` 55→**66 xanh**; `tsc --noEmit` sạch; server chỉ đổi tầng adapter, hành vi `game-ended.elo` không đổi.)* Còn lại Phase C: chỉ phần Firestore Emulator (tùy chọn, giống thật hơn) — fake-store đã phủ logic.

- [x] **T20 — Đợt 5 widget test trực quan (B1 C2 / B2 banner / B4 dialog)** (mới 2026-06-19): tách phần "visual" khỏi [`online_game_screen.dart`](cchess/lib/presentation/online/online_game_screen.dart) sang [`online_game_widgets.dart`](cchess/lib/presentation/online/online_game_widgets.dart) (3 widget thuần `OnlineChatButton` / `OnlineReconnectBanner` / `OnlineResultDialog` — nhận input + callback, screen chỉ delegate), rồi widget-test trong [`online_game_widgets_test.dart`](cchess/test/online/online_game_widgets_test.dart): **C2** badge `(n)` hiện khi có tin + disable khi `canChat=false` + tap gọi callback *(4 test)*; **D banner** countdown `còn 42s` / `chờ reconnect…` / `đang xác nhận…` (sec 42/null/0) + spinner khi `reconnecting` + ẩn khi `playing` *(5 test)*; **G4 dialog** title Thắng/Thua/Hòa + lý do VN + ELO row (mũi tên lên/xuống), actions theo trạng thái rematch (mặc định / mình mời / đối thủ mời / đối thủ rời / người xem 1 nút Thoát) + lỗi hiển thị + tap nút gọi đúng `onLeave`/`onOfferRematch`/`onDeclineRematch` *(12 test)*. *(21 test mới, pass — `flutter test` 205→**226 xanh**, `flutter analyze` sạch; refactor giữ nguyên hành vi/layout, gỡ các ghi chú "widget test hoãn" ở B1/B2/B4.)* Sau T25, C2 và G4 đã được đóng bằng auto-test; chỉ còn D4 cần thiết bị/OS thật.

- [x] **T21 — Đợt 6 post-deploy smoke P-D1** (mới 2026-06-19): mở rộng [`lab/smoke.ts`](cchess-backend/lab/smoke.ts) theo hướng **prod-safe mặc định, ranked-write opt-in**. `npm run lab:smoke` vẫn chỉ xác thực Firebase thật, tạo/rời phòng chờ, enqueue/cancel matchmaking và chống double-booking nên không ghi game/ELO. Khi bật `SMOKE_ALLOW_RANKED_WRITE=1` (nên trỏ staging hoặc chủ động bật trong workflow), smoke thêm 3 flow black-box trên deploy thật: **M1+G3** matchmaking 2 user thật → `match-found`/`game-start` cùng room + resign ra `game-ended{reason:"resign"}`; **D2** create/join → đi 1 nước hợp lệ từ engine TS → drop → reconnect trong grace nhận snapshot `moves` đầy đủ; **D3** drop quá grace → `game-ended{reason:"disconnect"}` và reconnect muộn bị reject. Workflow [`post-deploy-smoke.yml`](.github/workflows/post-deploy-smoke.yml) có checkbox `allow_ranked_write`; script hỗ trợ `FIREBASE_ID_TOKEN_A/B` nếu không muốn mint anonymous users. *(Script/gate đã code; PASS production/staging cần chạy workflow thủ công với endpoint thật.)*

- [x] **T22 — Đợt 7 engine smoke P-D2** (mới 2026-06-19): thêm [`lab/engine_smoke.ts`](cchess-backend/lab/engine_smoke.ts) + script `npm run engine:smoke` cho `cchess-engine` HTTP. Script black-box gọi `/health`, dò auth mode (`auto|required|disabled`), xác nhận invalid FEN trả `invalid-fen`, `/engine/best-move` trả UCI hợp lệ trong budget, gọi lặp để kiểm `cached=true`, kiểm `/engine/hint`, `/engine/analyze` với 1 nước hợp lệ từ engine TS, và có opt-in `ENGINE_SMOKE_CHECK_QUOTA=1` để mint user mới rồi xác nhận `quota-exceeded`. Thêm workflow thủ công [`.github/workflows/engine-smoke.yml`](.github/workflows/engine-smoke.yml) với input endpoint/auth/quota. *(Script/gate đã code; PASS Pikafish thật cần chạy workflow hoặc local Docker với binary+NNUE.)*

- [x] **T23 — Đợt 8 G1 checkmate auto-test** (mới 2026-06-19): thêm fixture FEN một nước chiếu bí vào [`match.test.ts`](cchess-backend/src/match.test.ts) để unit-test `applyMove()` tự sinh `autoFinish={result:"red-win", reason:"checkmate"}`; thêm integration WS ở [`server.test.ts`](cchess-backend/src/server.test.ts) để hai client thật trong server in-process cùng nhận `game-ended{reason:"checkmate"}` sau nước `a8a9`. Không cần binary Pikafish/NNUE vì case này kiểm luật ván và protocol backend, không kiểm chất lượng engine gợi ý. *(2 test mới, pass.)*

- [x] **T24 — Engine quota smoke gate** (mới 2026-06-20): thêm regression ở [`engine-service/server.test.ts`](cchess-backend/src/engine-service/server.test.ts) để xác nhận free `/engine/hint` quota trả HTTP 429 `quota-exceeded`; thêm script cross-platform `npm run engine:smoke:quota` và CLI `npm run engine:smoke -- --quota --quota-limit=3`; workflow [`engine-smoke.yml`](.github/workflows/engine-smoke.yml) có input `hint_quota_limit` để chạy staging/prod đúng cấu hình. Đã chạy product smoke trên `https://cchess-engine.onrender.com` với quota bật: **8/8 PASS**, gồm bước `quota-exceeded`. *(1 backend test mới + live smoke gate quota.)*

- [x] **T25 — Đóng bảng C/D/M/G bằng auto-test đúng ranh giới** (mới 2026-06-20): thêm 2 integration test WebSocket ở [`server.test.ts`](cchess-backend/src/server.test.ts) cho **M1/M4** (`find-match` 2 socket → `match-found` cùng room + `game-start.clock` đúng) và **M3** (`cancel-matching` → `matching-canceled{removed:true}` + queue sạch, socket sau không bị ghép với entry cũ). Sau khi đối chiếu coverage sẵn có từ T16–T24, đóng C1–C7, D2/D3/D5, M1–M4, G2–G6; tại thời điểm 2026-06-20 giữ D4/M5/H4 cho test thật. Cập nhật 2026-06-21: D4/M5 đã PASS test tay, H4 còn bug chất lượng offline/minimax. *(2 backend integration test mới, pass.)*

> **Backend `npm test` tổng cộng 71/71 xanh** (`rooms.test.ts` 4 + `match.test.ts` 9 + `matchmaking.test.ts` 7 + `elo.test.ts` 6 + `persistence.test.ts` 10 + `server.test.ts` 18 + `server.disconnect.test.ts` 5 + `server.waitingroom.test.ts` 2 + `server.liveness.test.ts` 3 + engine-service 7).
> **Flutter `flutter test` tổng cộng 226/226 xanh** (21 file — `online_match_controller_test.dart` 47 test + `online_result_format_test.dart` 16 test + `online_game_widgets_test.dart` 21 test).
> **Smoke deploy:** `npm run lab:smoke` vẫn là black-box prod-safe; `SMOKE_ALLOW_RANKED_WRITE=1 npm run lab:smoke` là gate opt-in có ghi ranked game/ELO thật. `npm run engine:smoke` là gate black-box cho `cchess-engine`; `npm run engine:smoke:quota` bật thêm kiểm `quota-exceeded`; dùng `ENGINE_SMOKE_AUTH=disabled` cho local `ENGINE_AUTH_DISABLED=1`, hoặc workflow `engine-smoke` sau deploy.

---

## 8b. Kế hoạch chuyển test tay còn lại sang test tự động

> Mục tiêu: giảm số bước phải bấm tay lặp lại, đặc biệt các flow online nhiều socket. Chỉ đổi trạng thái khi case đã có test tự động chạy xanh; các case phụ thuộc OS/Firebase/chất lượng chủ quan vẫn giữ manual.

### 8b.1. Phân loại sau đợt tự động hóa 2026-06-20

| Nhóm | Còn lại trong bảng chính | Đã đóng bằng test tự động | Không ép auto |
|---|:---:|---|---|
| C — Chat | 0 | C1–C7 qua server integration + Flutter controller/widget | Có thể nhìn-mắt chat sheet khi polish UI, không tính case bắt buộc |
| D — Reconnect | 0 | D2/D3/D5 qua liveness/drop/reconnect/double-disconnect integration + controller/widget; **D4 PASS test tay 2026-06-21** | Đã đóng OS/mạng thật |
| M — Matchmaking/ELO | 0 | M1–M4 qua matchmaking unit + WebSocket integration + controller; **M5 PASS test tay Firebase thật 2026-06-21** | Đã đối chiếu Firebase thật với Hồ sơ app |
| G — Lifecycle | 0 | G1–G6 qua backend integration/unit + result dialog/profile/rollback tests | Có thể nhìn-mắt dialog trên mobile khi polish UI, không tính case bắt buộc |
| H — Gợi ý | 1 | H1–H3 + logic hint/router; Pikafish online đã được test tay tốt/mạnh | **H4** offline/minimax quá yếu, cần nâng chất lượng hoặc định nghĩa lại fallback |

**Kết luận khuyến nghị:** sau test tay 2026-06-21 chỉ còn **H4 offline/minimax** chưa PASS. D4 lifecycle/OS thật và M5 Firebase thật đã đóng; phần còn lại nên chuyển sang stage nâng cấp chất lượng AI offline hoặc định nghĩa rõ "fallback offline yếu nhưng hợp lệ".

### 8b.2. Phase A — Mở rộng backend protocol/lab

**Mục tiêu:** biến các flow cần 2–3 người chơi thành kịch bản bot chạy lặp lại được qua `cchess-backend/lab`.

- [x] **A1 — Chat protocol nâng cao.** ✅ 2026-06-19 (T18): `server.test.ts` (integration WS) — **C5** spectator nhận `chat` history trong `spectate-started` + gửi chat tới cả 2 kỳ thủ (broadcast đúng `from`); **C6** reconnect snapshot khôi phục `chat` đúng thứ tự + `from`/`text`. (Rate-limit/length-cap/finished-block đã có ở T8.)
- [x] **A2 — Reconnect hết grace + double-disconnect UI data.** ✅ 2026-06-19 (T18): `server.disconnect.test.ts` (grace 1500ms) thêm **D3 single-drop** — một kỳ thủ rớt không quay lại → `game-ended{reason:"disconnect"}` đúng người thắng + room rời khỏi `list-active-rooms`; reconnect SAU khi hết grace bị từ chối bằng reconnect-reject code (`game-not-active`/`room-not-found`). **D5 + `peerInGrace`** đã có sẵn ở T10 (`server.disconnect.test.ts`).
- [x] **A3 — Matchmaking tolerance/clock.** ✅ 2026-06-19/20: `matchmaking.test.ts` unit cho `toleranceForWait()` + `tryMatch()` (M1/M2) — dùng stub `Date.now()` điều khiển `joinedAt`; `server.test.ts` integration mới cho **M1** (`find-match` 2 socket → `match-found` + `game-start`) và **M3** (`cancel-matching` dọn queue); **M4** clock per-room test ở cả create-room và find-match path. *Lưu ý phát hiện: `tryMatch()` chỉ ghép theo ELO, KHÔNG xét clock — "khác clock không ghép nhầm" không phải hành vi matchmaking mà do room lấy clock của người ghép đầu.*
- [x] **A4 — Lifecycle server.** ✅ 2026-06-19: **G1** checkmate đã có fixture FEN ổn định ở `match.test.ts` + integration WS ở `server.test.ts`; **G3** resign result/reason + idempotency ở `server.test.ts`; **G2** timeout đã có (`match.test.ts` unit + lab `running out of time forfeits`).
- [x] **A5 — Đưa lab vào tài liệu/gate rõ ràng.** ✅ 2026-06-20: [`backend-ci.yml`](.github/workflows/backend-ci.yml) chạy `npm run lint`, `npm run lab:check`, `npm test`, `npm run lab`, `npm run lab:load -- 40`, `npm run lab:fuzz` steady + burst; [`cchess-backend/lab/README.md`](cchess-backend/lab/README.md) ghi rõ lab local, smoke deploy và engine smoke. Bảng phân loại nguồn test cuối tài liệu tách `npm test`, lab, post-deploy smoke và engine smoke để không nhầm test unit với gate hạ tầng.

### 8b.3. Phase B — Flutter controller/widget tests

**Mục tiêu:** thay phần bấm UI lặp lại bằng fake socket + widget test; server đã đúng chưa đủ nếu UI không phản ứng đúng.

- [x] **B1 — Chat UI/controller.** ✅ 2026-06-19 (T17): controller test cho **C1/C3/C4/C5/C6/C7** trong `online_match_controller_test.dart` — nhận chat append + dedup theo id + lọc sai room, spectator nhận chat, reconnect snapshot khôi phục history, `chat-rate-limited`/`invalid-chat` map sang tiếng Việt, guard >120 ký tự client, `canChat=false` chặn gửi sau `game-ended`. **C2** badge `(n)`/disable phủ ở mức state (`chatMessages.length` + `canChat`); ✅ widget test nút Chat đầy đủ đã thêm ở **T20** (`OnlineChatButton`).
- [x] **B2 — Reconnect banners/state.** ✅ 2026-06-19 (T17): controller test cho **D2/D3** + lifecycle **D4** — `peer-disconnected` vào phase countdown kèm `peerDisconnectGraceMs`/`peerDisconnectedAtMs` (mặc định 60s khi thiếu), spectator KHÔNG vào countdown, `peer-reconnected` xoá banner + về playing, hết grace → `game-ended{disconnect}`, `disconnectKeepingReconnectState` giữ store còn `leave` xóa, `tryAutoReconnect` phát `reconnect-room`. Công thức đếm ngược tách `onlineRemainingGraceSec` (unit test); ✅ widget test banner (`OnlineReconnectBanner`: countdown/waiting/confirming/spinner/ẩn) đã thêm ở **T20**. **D5 `peerInGrace`** chưa được client tiêu thụ (chỉ tồn tại phía server T10) → không tự động hóa phía Flutter; **D4 OS thật PASS test tay 2026-06-21**.
- [x] **B3 — Matchmaking/lobby UI.** ✅ 2026-06-19 (T18): `online_match_controller_test.dart` nhóm **B3** — `findMatch(clockMs)`/`createRoom(clockMs)` gửi đúng command **và** clock chọn truyền xuống socket (fake bắt `lastFindMatchClockMs`/`lastCreateRoomClockMs`), `cancelMatching` gửi `cancel-matching`; state `matching` → `match-found` (roomId+opponent) / `matching-canceled` / `room-created` phản ánh đúng; `active-rooms` parse vào `OnlineActiveRoom`; lobby action bị chặn ngoài phase `authed`. (Lobby widget thật chưa dựng — đã unit-test ở tầng controller như gợi ý.)
- [x] **B4 — Result dialog/profile refresh.** ✅ 2026-06-19 (T17): tách logic thuần ra `online_result_format.dart` + unit test `online_result_format_test.dart` — **G4** `onlineResultTitle` (Thắng/Thua/Hòa + nhãn người xem), `onlineReasonLabel` tiếng Việt, `OnlineEloDelta` (dấu/hướng up/down/flat, chọn đúng phía theo màu, null khi không ranked/người xem). **G5** `refreshProfileAfterRankedGame` test fake `refreshFromCloud` + `refreshProfile` đảm bảo refresh cloud→profile và guard unmount. **G6** đã có lõi T5. ✅ widget test dựng AlertDialog đầy đủ (title/reason/ELO row/actions theo trạng thái rematch + người xem 1 nút Thoát) đã thêm ở **T20** (`OnlineResultDialog`).

### 8b.4. Phase C — Persistence/ELO tự động

**Mục tiêu:** phủ phần hiện khó test tay là ghi ELO/counters/game_records hai chiều.

- [x] **P-C1 — Fake persistence contract.** ✅ 2026-06-19: `server.test.ts` inject fake persist qua `createCChessServer({ persist })` trả `EloUpdate` cố định → assert `game-ended.elo` đúng shape `{red:{old,new,delta}, black:{...}}` cho **M5/G4/R11** + case `elo:null` khi persist rỗng — không cần Firebase. Toán K=32 tách riêng ở `elo.test.ts` (xem T16, phủ một phần P-C2).
- [x] **P-C2 — Tách adapter Firestore.** ✅ 2026-06-19 (T19): `persistence.ts` tách hàm thuần `buildPersistPlan()` (current ELO → writes) khỏi `PersistStore.commit()` (ranh giới nguyên tử). Adapter Firestore giữ `runTransaction`; test inject **fake in-memory store** trong [`persistence.test.ts`](cchess-backend/src/persistence.test.ts) — assert winner +điểm / loser −điểm / draw 0 (K=32), counters `wins/losses/draws/totalGames`, mirror `game_records` cả 2 bên, đọc đúng ELO hiện tại từng người. *(Firestore Emulator để sau — fake-store đã phủ logic; muốn “giống thật” hơn thì thêm profile emulator.)*
- [x] **P-C3 — Idempotency.** ✅ 2026-06-19 (T19): adapter bỏ qua khi `game_records/{gameId}` đã tồn tại (no-op) — `persistence.test.ts` test double-persist cùng `gameId` không double-counter/ELO; `server.test.ts` thêm test cấp server đếm persist gọi **đúng 1 lần** khi 2 end-condition đua (mapping sang **G lifecycle** — guard `endMatch()` là single source of truth, xem cả test “resign is idempotent”).

### 8b.5. Phase D — Smoke/staging scripts

**Mục tiêu:** kiểm deploy thật nhưng không biến CI thành bài test phá dữ liệu production.

- [x] **P-D1 — Mở rộng `npm run lab:smoke`.** ✅ 2026-06-19 (T21): smoke prod-safe mặc định vẫn không để game bắt đầu; thêm `SMOKE_ALLOW_RANKED_WRITE=1` để chạy create/join/resign/reconnect thật trên staging/prod, xác nhận **M1/G3/D2/D3** black-box trên server deploy. **M3** enqueue/cancel vẫn nằm trong smoke mặc định; workflow `post-deploy-smoke` có checkbox bật ranked-write.
- [x] **P-D2 — Engine smoke thật.** ✅ 2026-06-19/20 (T22/T24): thêm `npm run engine:smoke` cho `cchess-engine`: gọi health, auth probe, invalid FEN, best-move với timeout budget, cache hit, hint, analyze 1 nước hợp lệ. Quota có gate riêng `npm run engine:smoke:quota` / `--quota --quota-limit=N` để mint user mới rồi xác nhận `quota-exceeded`; workflow `engine-smoke` chạy thủ công trên endpoint staging/prod với input `hint_quota_limit`. Script này tự động hóa phần hạ tầng của **H4** và mục smoke Pikafish thật trong [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md); product smoke thật trên `https://cchess-engine.onrender.com` đã PASS 8/8 ngày 2026-06-20, cần chạy lại sau mỗi deploy/config change.
- [x] **P-D3 — Flutter CI.** ✅ 2026-06-19 (T17): [`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) chạy `flutter analyze` + `flutter test` (Flutter 3.38.5, `subosito/flutter-action`) trên push/PR khi chạm `cchess/**` → các test Phase B thành gate trước merge song song với `backend-ci`.

### 8b.6. Phase E — Manual test còn giữ lại

Các mục này vẫn nên giữ ở lịch test tay, vì tự động hóa chỉ kiểm được một phần:

- [x] **P-E1 — D4 lifecycle thật:** ✅ PASS 2026-06-21: Home/kill/disconnect/reconnect đúng logic người dùng; peer phát hiện disconnect khoảng 5–10s, countdown 59s, quá grace không reconnect lại được.
- [ ] **P-E2 — Render/prod sau redeploy:** cold start, restart xoá state rò rỉ, smoke sau deploy, độ trễ mạng thật.
- [ ] **P-E3 — Native UX:** clipboard/share sheet/QR/deep link OS-level nếu mở ngoài app.
- [ ] **P-E4 — H4 chất lượng nước gợi ý:** Pikafish online đã được người chơi đánh giá tốt/mạnh; offline minimax quá yếu, giống random-hợp-lệ, cần nâng engine/evaluator hoặc chuyển chiến lược fallback.

---

## 9. Bảng theo dõi tiến độ

| Nhóm | Tổng case | Đã PASS | Bug | Còn lại |
|---|:---:|:---:|:---:|:---:|
| R — Đấu lại | 12 | 12 ✅ | 0 | 0 |
| C — Chat | 8 | 8 ✅ | 0 | 0 |
| S — Spectate + share link | 15 | 15 ✅ | 0 | 0 |
| D — Reconnect | 5 | 5 ✅ | 0 | 0 |
| M — Matchmaking/ELO | 5 | 5 ✅ | 0 | 0 |
| G — Lifecycle | 6 | 6 ✅ | 0 | 0 |
| H — Gợi ý in-game | 4 | 3 | 1 (H4 offline/minimax yếu) | 1 (H4 — nâng chất lượng offline/minimax) |
| T — Test tự động | 25 | 25 | 0 | 0 |
| **Tổng** | **80** | **79** | **1** | **1** |

> Cập nhật bảng này sau mỗi đợt test. Sau test tay 2026-06-21, **D4** và **M5** đã PASS. Mục còn lại là **H4 offline/minimax**: Pikafish online đạt kỳ vọng, nhưng fallback offline/minimax quá yếu nên cần stage nâng cấp AI offline hoặc điều chỉnh kỳ vọng sản phẩm.

---

### Phân loại nguồn test tự động (để khỏi lẫn khi bảo trì)

| Bộ test | Loại | Cần hạ tầng thật? | Chạy bằng |
|---|---|---|---|
| Flutter `test/chess_engine/`, `test/game/`, `test/puzzle/`, `test/data/`, … | Unit thuần Dart | Không | `flutter test` |
| Flutter `test/online/` (controller + room_share) | Unit với fake socket | Không (socket giả) | `flutter test test/online` |
| Backend `rooms.test.ts`, `match.test.ts` | Unit thuần TS | Không | `npm test` |
| Backend `server.test.ts`, `server.disconnect.test.ts`, `server.waitingroom.test.ts`, `server.liveness.test.ts` | **Integration WS thật** (in-process, auth/persist inject giả) | Không cần Firebase | `npm test` |
| Backend `lab/*` | Scenario bot + invariant + load/fuzz cho realtime server | Không cần Firebase | `npm run lab`, `npm run lab:load`, `npm run lab:fuzz` |
| Backend `lab:smoke` | Black-box smoke trên server deploy thật (prod-safe mặc định, ranked-write opt-in) | Cần Firebase Anonymous + endpoint deploy | `npm run lab:smoke`; `SMOKE_ALLOW_RANKED_WRITE=1 npm run lab:smoke` / workflow `post-deploy-smoke` |
| Backend `engine-service/*.test.ts` | Unit + HTTP integration (fake engine process) | **Không cần binary Pikafish** | `npm test` |
| Smoke test Pikafish thật (mục 11 của [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md)) | `npm run engine:smoke`, `npm run engine:smoke:quota` / workflow `engine-smoke` | **Cần binary + NNUE thật** | PASS thật trên `cchess-engine` 2026-06-20; chạy lại sau deploy/config change |

---

*Tạo 2026-06-07 cùng đợt hoàn thiện nút "Đấu lại". Cập nhật 2026-06-07 (đợt 2): đóng hết Nhóm T — thêm `cchess-backend/src/server.test.ts` (integration WS) cho T3 rematch handshake + T7 reconnect + T8 chat; tách `server.ts` thành `createCChessServer()` factory để test in-process không cần Firebase.
Cập nhật 2026-06-11 → 2026-06-18: hardening double-disconnect (D5), nút Gợi ý/chip chat, test tay Nhóm R/S, fix R9, tuning H1–H3, và thêm §8b để chuyển dần 23 case còn lại ở thời điểm đó sang backend lab, Flutter controller/widget test, persistence/ELO test, smoke/staging script.
Cập nhật 2026-06-19/20 (T16–T25): tự động hóa backend M/G/ELO, Flutter controller/widget, persistence adapter/idempotency, smoke deploy/engine, **G1 checkmate** bằng fixture FEN + integration WS, quota smoke gate cho `cchess-engine`, và thêm WebSocket integration cho M1/M3. Backend `npm test` 32→**71 xanh**, Flutter online suite **101 xanh** (`flutter test test/online`; full suite gần nhất 226 xanh), các lệnh analyze/lint sạch; engine product smoke 8/8 PASS trên Render.
Cập nhật 2026-06-21: test tay **D4 PASS** (disconnect/reconnect + countdown grace đúng), **M5 PASS** (Firebase thật khớp Hồ sơ app), **H4 tách kết luận** — Pikafish online rất tốt/rất mạnh, offline minimax quá yếu giống random-hợp-lệ; stage kế tiếp là nâng cấp AI offline/minimax hoặc định nghĩa lại fallback offline.*
