# ✅ KẾ HOẠCH TEST — CChess (các mục chưa xác nhận đã test)

> Tài liệu sống — tạo ngày **2026-06-07**, cập nhật **2026-06-18** (bổ sung kế hoạch chuyển test tay sang test tự động).
> Mục đích: liệt kê **các kịch bản còn tồn đọng chưa test xong** để sắp lịch test dần.
> Phạm vi: tập trung các tính năng **online/multiplayer Sprint 12** (Đấu lại, Chat, Spectate, Reconnect, Matchmaking) + **engine service Pikafish / nút Gợi ý** (Sprint 15 sớm) — phần engine/offline (Sprint 1–7) đã có unit test xanh, không lặp lại ở đây.
> Tham chiếu: [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md), [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md), [`09_BACKEND_SERVER_HOAT_DONG.md`](09_BACKEND_SERVER_HOAT_DONG.md), [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md).
>
> **Trạng thái test tự động 2026-06-19:** Backend `cd cchess-backend && npm test` → **51/51 xanh** (9 file). Flutter `cd cchess && flutter test` → **198/198 xanh** (20 file). Chi tiết ở Nhóm T (§8).
> **Test tay:** đợt 1 (2026-06-12) Nhóm R 11/12, bug R9 sửa cùng ngày; đợt 2 (2026-06-13) **R9 retest PASS → Nhóm R đóng 12/12**, **C8 PASS** (rate-limit nâng 1.5s→2s), **H1–H3 PASS** (tuning best-effort, theo dõi H4), **S1–S12 PASS** → feedback UX sinh 3 case mới S13–S15 (số mắt xem cho người chơi, dialog người xem 1 nút Thoát + tự xem tiếp khi rematch, phòng chờ tự hủy 1 phút) — **đã test tay PASS 2026-06-13 → Nhóm S đóng 15/15** (lưu ý: S15 chỉ chạy đúng sau khi `npm run build` lại backend — server chạy từ `dist/`).
> **Kế hoạch tự động hóa 2026-06-18:** Tổng còn lại vẫn là **23 case chưa PASS test tay** (§9), nhưng phần lõi của nhiều case đã hoặc có thể chuyển sang test tự động bằng backend lab, Flutter controller/widget test, smoke script staging/prod. Xem §8b.

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

- [ ] **C1 — Gửi/nhận realtime giữa 2 người.** Tin nhắn hiện đúng bên (bong bóng mình bên phải, đối thủ bên trái), kèm thời gian.
- [ ] **C2 — Badge số tin nhắn.** Nút "Chat" hiển thị số lượng `(n)` khi có tin mới.
- [ ] **C3 — Rate limit.** Gửi liên tiếp < 2s → nhận lỗi **"Bạn gửi chat quá nhanh."** (`chat-rate-limited`). *(Nâng từ 1.5s → 2s ngày 2026-06-13 theo feedback test tay C8.)*
- [ ] **C4 — Giới hạn 120 ký tự.** Gõ > 120 ký tự → bị chặn (client cắt + server `invalid-chat`).
- [ ] **C5 — Spectator chat.** Người xem gửi/nhận được chat trong phòng.
- [ ] **C6 — Khôi phục lịch sử chat sau reconnect.** Mất mạng → reconnect trong 60s → lịch sử chat (snapshot từ server) hiện lại đúng.
- [ ] **C7 — Chặn chat khi ván đã kết thúc.** Sau `game-ended`, gửi chat → server trả `not-playing` (kiểm hành vi UI không gửi được).
- [x] **C8 — Chip tin nhắn nhanh (preset) — code 2026-06-11, test tay PASS 2026-06-13.** Hàng chip preset (Chào bạn 👋 / Chúc may mắn 🍀 / …) hiện trên ô nhập trong chat sheet; chạm 1 chip → gửi ngay như chat thường; chạm 2 chip liên tiếp < 2s → dính rate-limit như C3; chip bị disable khi `canChat=false`. *(Theo feedback đợt test: rate-limit server nâng 1.5s → 2s.)*

---

## 4. Nhóm S — Spectate + danh sách ván đang diễn ra + share link — ✅ **S1–S12 PASS** (test tay 2026-06-13)

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

> **Bug D2 (test tay 2026-06-14) → ĐÃ SỬA, chờ retest:** reconnect kịp nhưng (1) **ván bị reset về bàn cờ gốc**, (2) state kẹt — server/lobby vẫn coi A,B "đang đánh" nên tạo/vào phòng mới hiện trạng thái xanh "đang đánh" mà **không có bàn cờ** ⇒ chặn D3/D4/D5. Nguyên nhân: client **reconnect chồng chéo** — `connectivity_plus` bắn nhiều sự kiện + timer định kỳ → nhiều chu kỳ `disconnect/connect` đua nhau, làm server churn socket (re-grace lặp) và client xử lý nhầm snapshot. **Xác nhận server + client replay ĐÚNG khi reconnect sạch** (test tự động: server `moves` được giữ qua liveness drop; controller replay nước đi). Sửa: thay vòng lặp reconnect bằng **state machine 1-attempt** (guard `_attemptInFlight` + `_awaitingResponse` + timeout 8s) → gộp mọi burst thành **đúng 1 lần** reconnect; mid-game dùng `readRoomId()` (bỏ gate 70s, để server grace 60s là bound). Test tự động bổ sung trong **T15**.

> **Bug D2 đợt 2 (test tay 2026-06-15) → ĐÃ SỬA tiếp:** vẫn loạn — A đi được nhưng **B không đi được** (nước A không tới B), thoát ra vào lại hiện "đang đánh" không bàn cờ, và **A thoát vẫn xem được trận A–B** (phòng cũ kẹt `playing`). Nguyên nhân còn lại: (1) **state rò rỉ trên Render** từ các lần test hỏng trước (phòng/socket chết còn trong RAM); (2) `attachReconnectingSocket` **không xoá socket cũ** khỏi `room.members` → broadcast `opponent-move` tới socket chết; (3) reconnect store cũ làm lobby **tự nối lại phòng ma** mỗi lần vào → kẹt. Sửa: server **evict socket cũ** khi reconnect (members luôn sạch); client **clear store + về lobby** khi reconnect bị từ chối (hết vòng lặp nối phòng ma). ⚠️ **Bắt buộc: REDEPLOY/restart Render** (xoá state rò rỉ + nạp fix server) **+ rebuild app**; sau đó lần reconnect tới phòng ma sẽ tự fail → store tự xoá. Test: rooms eviction + controller "lobby nối phòng ma".

- [x] **D1 — Phát hiện rớt nhanh + banner.** Đối thủ tắt mạng → trong **~15s** (trước đây ~3 phút) mình thấy banner vàng **"Đối thủ mất kết nối — còn 60s…"** đếm ngược. ✅ **PASS 2026-06-14**.
- [ ] **D2 — Reconnect kịp (mở lại app HOẶC bật lại wifi giữa ván).** Trong 60s: bật lại mạng khi app vẫn mở → A thấy "đang kết nối lại…" rồi ván tiếp tục **đúng thế cờ**/đồng hồ (KHÔNG reset bàn cờ); HOẶC mở lại app → auto-reconnect từ lobby. Banner phía B biến mất (`peer-reconnected`). *(test tay 06-14 FAIL: reset bàn + kẹt state → đã sửa single-flight, chờ retest sau redeploy Render).*
- [ ] **D3 — Hết grace.** Để quá 60s → ván tự kết thúc với lý do `disconnect`, người còn lại thắng, dialog kết quả hiện (lưu ý R8: không cho đấu lại).
- [ ] **D4 — Lifecycle nền vs kill.** Bấm Home (paused/hidden) → KHÔNG mất kết nối; vuốt kill app (detached) → vào grace + lần mở app sau auto-reconnect từ lobby (`tryAutoReconnect`).
- [ ] **D5 — Double-disconnect** *(✅ hardening ĐÃ CODE 2026-06-11 + có test tự động T10).* Server giờ giữ grace **theo từng uid** (map `disconnectGrace`) nên cả 2 người chơi cùng rớt vẫn giữ được cửa sổ reconnect riêng; người rớt TRƯỚC hết grace trước → xử thua trước; snapshot `reconnected` có thêm trường `peerInGrace{uid, remainingMs}` để client vẽ banner ngay. Phòng kết thúc khi cả 2 vắng mặt sẽ tự dọn (không leak). *Việc còn lại của test tay: quan sát UI 2 thiết bị thật khi cả 2 cùng mất mạng rồi cùng quay lại (banner + đồng hồ).*

---

## 6. Nhóm M — Matchmaking + ELO + Clock

> Code: [matchmaking.ts](cchess-backend/src/matchmaking.ts), [elo.ts](cchess-backend/src/elo.ts), [persistence.ts](cchess-backend/src/persistence.ts).

- [ ] **M1 — Ghép trận tự động.** 2 người bấm "Tìm trận" cùng mức clock → được ghép, vào ván.
- [ ] **M2 — Nới tolerance theo thời gian.** Chênh lệch ELO lớn vẫn ghép được sau khi chờ (ticker 5s nới bucket).
- [ ] **M3 — Huỷ tìm trận.** Bấm huỷ khi đang chờ → rời queue (`matching-canceled`).
- [ ] **M4 — Clock per-room.** Chọn 3/5/10/15/30 phút → đồng hồ khởi tạo đúng cho cả 2 bên.
- [ ] **M5 — ELO 2 chiều.** Sau ván ranked, người thắng +điểm / người thua −điểm theo K=32; ghi `eloChess` + counters lên Firestore; dialog hiện delta đúng dấu/màu.

---

## 7. Nhóm G — Vòng đời ván & dialog kết quả

- [ ] **G1 — Chiếu bí.** Auto `game-ended` với result đúng, reason=`checkmate`.
- [ ] **G2 — Hết giờ.** Bên hết giờ thua (reason=`timeout`), đồng hồ về 0:00.
- [ ] **G3 — Xin thua.** Xác nhận dialog → đối thủ thắng (reason=`resign`).
- [ ] **G4 — Nội dung dialog kết quả.** Tiêu đề Thắng/Thua/Hòa đúng theo `myColor`; lý do tiếng Việt; ELO delta (mũi tên lên/xuống/ngang + màu).
- [ ] **G5 — Auto-refresh hồ sơ.** Sau dialog, ELO + số ván trên màn Hồ Sơ cập nhật ngay (`cloudSync.refreshFromCloud` + `profileController.refresh`).
- [ ] **G6 — Rollback nước đi.** Khi server reject (`illegal-move`/`not-your-turn`) → client undo nước optimistic, hiện thông báo "đã rollback", trạng thái client–server đồng bộ lại.

---

## 7b. Nhóm H — Nút Gợi ý in-game — ✅ **ĐÓNG 3/3 PASS** (test tay 2026-06-13, cả online lẫn offline)

> Code: [game_screen.dart](cchess/lib/presentation/game/game_screen.dart) (`_onHint`), [game_controller.dart](cchess/lib/presentation/game/game_controller.dart) (`showHint`/`clearHint`), [game_action_bar.dart](cchess/lib/presentation/game/widgets/game_action_bar.dart), [chess_board.dart](cchess/lib/widgets/chess/chess_board.dart) (marker xanh ngọc), [engine_router.dart](cchess/lib/core/chess_engine/engine_router.dart). Logic controller đã có test tự động (T11).

- [x] **H1 — Nút Gợi ý hoạt động (online engine).** Đang ván bot, đến lượt mình, server engine chạy (`CCHESS_ENGINE_URL` trỏ đúng) → bấm 💡 Gợi ý → 2 ô from/to sáng **xanh ngọc** (khác màu vàng của nước cuối); icon chuyển hourglass trong lúc chờ.
- [x] **H2 — Fallback offline.** Tắt mạng / không cấu hình engine URL → bấm Gợi ý → vẫn nhận gợi ý từ minimax local + snackbar "Gợi ý offline (minimax)…".
- [x] **H3 — Gợi ý tự xoá đúng lúc.** Sau khi đi nước (bất kỳ), undo, hoặc ván mới → marker gợi ý biến mất; bấm Gợi ý khi chưa đến lượt/bot đang nghĩ → nút disabled.

> **Feedback đợt test 2026-06-13:** gợi ý "hơi lâu, hơi kém" → **đã tuning cùng ngày** (T13): chế độ best-effort cho hint/analysis trong `BotEngine` — bỏ delay nhân tạo `minThinkTime` 1.2s, bỏ randomness, **iterative deepening có ngân sách ~2s** (thế nhẹ/tàn cuộc tự đào sâu tới depth 6 — mạnh hơn trước; giữa ván nặng trả kết quả depth đã xong thay vì treo). Lưu ý: chất lượng offline vẫn bị chặn bởi minimax + evaluator đơn giản — gợi ý "mạnh thật" đến từ Pikafish server-side khi deploy `cchess-engine` (xem [`11`](11_KE_HOACH_TICH_HOP_ENGINE.md)). → Đáng theo dõi tiếp ở case **H4** dưới đây.

- [ ] **H4 — Đánh giá lại tốc độ/chất lượng gợi ý sau tuning.** Kỳ vọng sau fix: gợi ý offline trả về trong ~0.5–2.5s (không còn +1.2s delay); nước gợi ý không còn ngẫu nhiên kém; tàn cuộc gợi ý sâu hơn. Nếu vẫn "kém" → đẩy ưu tiên deploy Pikafish.

---

## 8. Nhóm T — Test tự động ✅ XANH TOÀN BỘ (cập nhật 2026-06-11)

> Mục này là **viết test code**, không phải test tay. Ưu tiên làm để khỏi phải test tay lặp lại các case ở trên.
> **Trạng thái 2026-06-13 (đợt 2):** T1–T14 đều xanh. Backend `cd cchess-backend && npm test` → **28/28** (8 file). Flutter `cd cchess && flutter test` → **156/156** (19 file).

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

- [x] **T16 — Đợt 1 tự động hóa M/G/ELO** (mới 2026-06-19, Phase A3a/A4 + P-C1 của §8b): backend [`matchmaking.test.ts`](cchess-backend/src/matchmaking.test.ts) — `toleranceForWait()` nới đúng nấc; `tryMatch()` ghép trong tolerance (M1), nới theo thời gian chờ (M2), không tự ghép cùng uid, chọn đối thủ ELO gần nhất, enqueue idempotent + dequeue *(7 test)*; [`elo.test.ts`](cchess-backend/src/elo.test.ts) — `computeElo` K=32, thắng equal ±16, zero-sum, upset > favourite, hòa equal=0, hòa lệch ELO kéo về nhau (M5/G4) *(6 test)*; `server.test.ts` thêm **G3** resign → `result/reason` đúng + **idempotency** (resign lần 2 không bắn `game-ended` thứ 2), **P-C1** inject fake persist → map `game-ended.elo` đúng shape cho cả 2 bên (M5/G4/R11) + `elo:null` khi persist rỗng, **M4** clock chọn lúc create-room tới đủ 2 bên *(5 test)*. *(18 test, pass — lõi M1/M2/M4/M5/G3/G4 đã có auto test; vẫn giữ `- [ ]` ở các nhóm tới khi xác nhận 1 vòng tay cuối theo §8b.1.)* G1 checkmate hoãn sang đợt engine-fixture (chuỗi chiếu bí dễ vỡ nếu hard-code).

- [x] **T17 — Đợt 2 tự động hóa Flutter (Phase B B1/B2/B4 + P-D3 CI)** (mới 2026-06-19): [`online_match_controller_test.dart`](cchess/test/online/online_match_controller_test.dart) thêm nhóm **B1 — chat** (C1 append + dedup + lọc sai room, C3 rate-limit→VN, C4 invalid + guard 120 ký tự client, C5 spectator nhận chat, C6 reconnect khôi phục history, C7 ended chặn gửi) *(11 test)* + nhóm **B2 — reconnect/lifecycle** (D2 `peer-disconnected`/`peer-reconnected` + grace data, spectator không vào countdown, D3 hết grace → `game-ended{disconnect}`, D4 `disconnectKeepingReconnectState` giữ store / `leave` xóa / `tryAutoReconnect`) *(8 test)*; tách [`online_result_format.dart`](cchess/lib/presentation/online/online_result_format.dart) (title G4, reason VN, `OnlineEloDelta` dấu/hướng, grace giây, `refreshProfileAfterRankedGame` G5 guard-unmount) + [`online_result_format_test.dart`](cchess/test/online/online_result_format_test.dart) *(16 test)*; screen chỉ delegate lại, không đổi hành vi. **Flutter CI** [`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) chạy `flutter analyze` + `flutter test` khi chạm `cchess/**`. *(35 test mới, pass — `flutter test` 163→**198 xanh**, `flutter analyze` sạch.)* Hoãn: B3 lobby/matchmaking UI, widget test C2/banner/dialog đầy đủ; vẫn manual: D4 OS-thật + `peerInGrace` (chưa wire phía client).

> **Backend `npm test` tổng cộng 51/51 xanh** (`rooms.test.ts` 4 + `match.test.ts` 8 + `matchmaking.test.ts` 7 + `elo.test.ts` 6 + `server.test.ts` 12 + `server.disconnect.test.ts` 2 + `server.waitingroom.test.ts` 2 + `server.liveness.test.ts` 3 + engine-service 6).
> **Flutter `flutter test` tổng cộng 198/198 xanh** (20 file — `online_match_controller_test.dart` 40 test + `online_result_format_test.dart` 16 test).

---

## 8b. Kế hoạch chuyển test tay còn lại sang test tự động

> Mục tiêu: giảm số bước phải bấm tay lặp lại, đặc biệt các flow online nhiều socket. Không đổi trạng thái `- [ ]` ở các nhóm C/D/M/G/H cho tới khi test tương ứng được code, chạy xanh, và nếu cần vẫn được xác nhận một vòng tay cuối.

### 8b.1. Phân loại 23 case còn lại

| Nhóm còn lại | Còn lại | Đã có test tự động/lab phủ lõi | Nên tự động hóa thêm | Vẫn nên test tay cuối |
|---|:---:|---|---|---|
| C — Chat | 7 | T8 đã phủ server cho C1/C3/C4/C7 | C1–C7 bằng Flutter controller/widget + backend lab cho spectator/reconnect chat | Gần như không, trừ kiểm cảm giác chat sheet trên thiết bị thật |
| D — Reconnect | 4 | T7/T10/T15 + lab đã phủ snapshot, double-disconnect, liveness | D2–D5 bằng lab kịch bản rút ngắn timer + Flutter state/widget banner | D4 Home/kill app, bật/tắt mạng thật, Render sau redeploy |
| M — Matchmaking/ELO | 5 | Lab đã có M1/M3 cơ bản; match/unit đã phủ clock một phần | M1–M5 bằng backend integration, unit matchmaking tolerance, fake persistence/Firestore emulator | M5 một vòng với 2 tài khoản Firebase thật trước release |
| G — Lifecycle | 6 | T2/T5 + lab đã phủ timeout/resign/rollback một phần | G1–G6 bằng backend integration + Flutter dialog/profile-refresh test | Dialog kết quả nên nhìn lại một vòng trên mobile |
| H — Gợi ý | 1 | T13 đã đo budget best-effort + T11 logic hint | H4 bằng benchmark/script fixed positions + smoke Pikafish thật | Chất lượng nước gợi ý vẫn cần người chơi đánh giá |

**Kết luận khuyến nghị:** phần có thể đưa vào automation gate thường xuyên là **C, phần lớn D, M1–M4, G1–G6**. Phần còn phải test tay không nên biến mất hoàn toàn gồm **D4 lifecycle/OS thật**, **M5 với hạ tầng Firebase thật**, **H4 chất lượng chủ quan**, và một vòng visual UX cuối cho dialog/chat/reconnect.

### 8b.2. Phase A — Mở rộng backend protocol/lab

**Mục tiêu:** biến các flow cần 2–3 người chơi thành kịch bản bot chạy lặp lại được qua `cchess-backend/lab`.

- [ ] **A1 — Chat protocol nâng cao.** Thêm scenario/test cho **C5** spectator gửi/nhận chat; **C6** reconnect nhận lại `chat` history trong snapshot; assert thứ tự, `from`, trim lịch sử, và không duplicate message. Có thể đặt trong `server.test.ts` nếu muốn vào `npm test`, hoặc trong `lab/scenarios.ts` nếu muốn chạy qua `npm run lab`.
- [ ] **A2 — Reconnect hết grace + double-disconnect UI data.** Mở rộng lab cho **D3/D5**: dùng `reconnectGraceMs` rút ngắn, assert `game-ended{reason:"disconnect"}`, người thắng đúng, room cleanup, `peerInGrace` có đủ dữ liệu cho client vẽ banner.
- [x] **A3 — Matchmaking tolerance/clock.** ✅ 2026-06-19: `matchmaking.test.ts` unit cho `toleranceForWait()` + `tryMatch()` (M1/M2) — dùng stub `Date.now()` điều khiển `joinedAt`, KHÔNG cần sửa code (module đã export `__resetQueueForLab`); **M4** clock per-room test ở `server.test.ts` (create-room `clockMs` → `game-start.clock` đủ 2 bên). *Lưu ý phát hiện: `tryMatch()` chỉ ghép theo ELO, KHÔNG xét clock — "khác clock không ghép nhầm" không phải hành vi matchmaking mà do room lấy clock của người ghép đầu.* M3 đã có lab `cancel-matching-clears-queue`.
- [x] **A4 — Lifecycle server (một phần).** ✅ 2026-06-19: **G3** resign result/reason + idempotency ở `server.test.ts`. **G2** timeout đã có (`match.test.ts` unit + lab `running out of time forfeits`). ⏭️ **G1 checkmate** hoãn — cần fixture engine / chuỗi nước cố định (hard-code chuỗi chiếu bí Xiangqi dễ vỡ).
- [ ] **A5 — Đưa lab vào tài liệu/gate rõ ràng.** Vì GitHub Actions đã chạy `npm run lab`, `lab:load`, `lab:fuzz`, cập nhật dòng tổng test tự động sau khi thêm scenario để bảng T không chỉ phản ánh `npm test`.

### 8b.3. Phase B — Flutter controller/widget tests

**Mục tiêu:** thay phần bấm UI lặp lại bằng fake socket + widget test; server đã đúng chưa đủ nếu UI không phản ứng đúng.

- [x] **B1 — Chat UI/controller.** ✅ 2026-06-19 (T17): controller test cho **C1/C3/C4/C5/C6/C7** trong `online_match_controller_test.dart` — nhận chat append + dedup theo id + lọc sai room, spectator nhận chat, reconnect snapshot khôi phục history, `chat-rate-limited`/`invalid-chat` map sang tiếng Việt, guard >120 ký tự client, `canChat=false` chặn gửi sau `game-ended`. **C2** badge `(n)`/disable hiện được phủ ở mức state (`chatMessages.length` + `canChat`); widget test nút Chat đầy đủ vẫn hoãn.
- [x] **B2 — Reconnect banners/state.** ✅ 2026-06-19 (T17): controller test cho **D2/D3** + lifecycle **D4** — `peer-disconnected` vào phase countdown kèm `peerDisconnectGraceMs`/`peerDisconnectedAtMs` (mặc định 60s khi thiếu), spectator KHÔNG vào countdown, `peer-reconnected` xoá banner + về playing, hết grace → `game-ended{disconnect}`, `disconnectKeepingReconnectState` giữ store còn `leave` xóa, `tryAutoReconnect` phát `reconnect-room`. Công thức đếm ngược tách `onlineRemainingGraceSec` (unit test). **D5 `peerInGrace`** chưa được client tiêu thụ (chỉ tồn tại phía server T10) → không tự động hóa phía Flutter; **D4 OS thật** vẫn test tay.
- [ ] **B3 — Matchmaking/lobby UI.** Test `findMatch/cancelMatching/createRoom(clockMs)` gửi đúng command, clock đang chọn truyền xuống socket, state chờ/huỷ/ghép trận phản ánh đúng. Nếu lobby widget khó dựng, tách helper/presenter nhỏ để unit test trước.
- [x] **B4 — Result dialog/profile refresh.** ✅ 2026-06-19 (T17): tách logic thuần ra `online_result_format.dart` + unit test `online_result_format_test.dart` — **G4** `onlineResultTitle` (Thắng/Thua/Hòa + nhãn người xem), `onlineReasonLabel` tiếng Việt, `OnlineEloDelta` (dấu/hướng up/down/flat, chọn đúng phía theo màu, null khi không ranked/người xem). **G5** `refreshProfileAfterRankedGame` test fake `refreshFromCloud` + `refreshProfile` đảm bảo refresh cloud→profile và guard unmount. **G6** đã có lõi T5. Widget test dựng AlertDialog đầy đủ (màu icon) hoãn — màu suy ra trực tiếp từ `EloDeltaDirection`.

### 8b.4. Phase C — Persistence/ELO tự động

**Mục tiêu:** phủ phần hiện khó test tay là ghi ELO/counters/game_records hai chiều.

- [x] **P-C1 — Fake persistence contract.** ✅ 2026-06-19: `server.test.ts` inject fake persist qua `createCChessServer({ persist })` trả `EloUpdate` cố định → assert `game-ended.elo` đúng shape `{red:{old,new,delta}, black:{...}}` cho **M5/G4/R11** + case `elo:null` khi persist rỗng — không cần Firebase. Toán K=32 tách riêng ở `elo.test.ts` (xem T16, phủ một phần P-C2).
- [ ] **P-C2 — Tách adapter Firestore hoặc chạy emulator.** Sửa `persistence.ts` theo hướng adapter nhỏ (`getUser`, `updateUserStats`, `writeGameRecord`) để unit test transaction bằng fake store; hoặc thêm profile Firestore Emulator nếu muốn giống thật hơn. Assert: winner +điểm, loser -điểm, draw 0/đúng công thức K=32, counters `wins/losses/draws/totalGames`, mirror `game_records` cho cả 2 bên.
- [ ] **P-C3 — Idempotency.** Có test double-finish không gọi persist/ELO lần 2; nếu đã phủ bằng lab thì ghi rõ mapping sang **M5/G lifecycle**.

### 8b.5. Phase D — Smoke/staging scripts

**Mục tiêu:** kiểm deploy thật nhưng không biến CI thành bài test phá dữ liệu production.

- [ ] **P-D1 — Mở rộng `npm run lab:smoke`.** Hiện smoke prod-safe chưa để game bắt đầu. Thêm chế độ opt-in `SMOKE_ALLOW_RANKED_WRITE=1` hoặc trỏ staging để chạy create/join/resign/reconnect thật, xác nhận **D2/D3/M1/M3/G3** trên server deploy.
- [ ] **P-D2 — Engine smoke thật.** Thêm script `engine:smoke` cho `cchess-engine`: gọi health/best-move với vài FEN/X-FEN cố định, timeout budget, auth/rate-limit, cache hit. Script này tự động hóa phần hạ tầng của **H4** và mục smoke Pikafish thật trong [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md).
- [x] **P-D3 — Flutter CI.** ✅ 2026-06-19 (T17): [`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) chạy `flutter analyze` + `flutter test` (Flutter 3.38.5, `subosito/flutter-action`) trên push/PR khi chạm `cchess/**` → các test Phase B thành gate trước merge song song với `backend-ci`.

### 8b.6. Phase E — Manual test còn giữ lại

Các mục này vẫn nên giữ ở lịch test tay, vì tự động hóa chỉ kiểm được một phần:

- [ ] **P-E1 — D4 lifecycle thật:** Home/Resume, app switcher kill, đổi mạng Wi-Fi/4G, OS background policy trên Android/iOS.
- [ ] **P-E2 — Render/prod sau redeploy:** cold start, restart xoá state rò rỉ, smoke sau deploy, độ trễ mạng thật.
- [ ] **P-E3 — Native UX:** clipboard/share sheet/QR/deep link OS-level nếu mở ngoài app.
- [ ] **P-E4 — H4 chất lượng nước gợi ý:** benchmark tự động đo nhanh/chậm và hợp lệ, nhưng "nước có hay không" cần người chơi/engine mạnh đối chiếu.

---

## 9. Bảng theo dõi tiến độ

| Nhóm | Tổng case | Đã PASS | Bug | Còn lại |
|---|:---:|:---:|:---:|:---:|
| R — Đấu lại | 12 | 12 ✅ | 0 | 0 |
| C — Chat | 8 | 1 | 0 | 7 |
| S — Spectate + share link | 15 | 15 ✅ | 0 | 0 |
| D — Reconnect | 5 | 1 | 1 (D2 đã sửa, chờ retest) | 4 |
| M — Matchmaking/ELO | 5 | 0 | 0 | 5 |
| G — Lifecycle | 6 | 0 | 0 | 6 |
| H — Gợi ý in-game | 4 | 3 | 0 | 1 (H4 — đánh giá sau tuning) |
| T — Test tự động | 17 | 17 | 0 | 0 |
| **Tổng** | **72** | **49** | **1** | **23** |

> Cập nhật bảng này sau mỗi đợt test. **Nhóm R đóng 12/12; Nhóm S đóng 15/15** (S13–S15 PASS test tay 2026-06-13). Tiếp theo: phiên 2 thiết bị gom **D1–D5** (reconnect), tiện tay chấm **M/G** và **H4**; **C1–C7** có thể test solo nhanh.

---

### Phân loại nguồn test tự động (để khỏi lẫn khi bảo trì)

| Bộ test | Loại | Cần hạ tầng thật? | Chạy bằng |
|---|---|---|---|
| Flutter `test/chess_engine/`, `test/game/`, `test/puzzle/`, `test/data/`, … | Unit thuần Dart | Không | `flutter test` |
| Flutter `test/online/` (controller + room_share) | Unit với fake socket | Không (socket giả) | `flutter test test/online` |
| Backend `rooms.test.ts`, `match.test.ts` | Unit thuần TS | Không | `npm test` |
| Backend `server.test.ts`, `server.disconnect.test.ts`, `server.waitingroom.test.ts`, `server.liveness.test.ts` | **Integration WS thật** (in-process, auth/persist inject giả) | Không cần Firebase | `npm test` |
| Backend `lab/*` | Scenario bot + invariant + load/fuzz cho realtime server | Không cần Firebase | `npm run lab`, `npm run lab:load`, `npm run lab:fuzz` |
| Backend `lab:smoke` | Black-box smoke trên server deploy thật | Cần Firebase Anonymous + endpoint deploy | `npm run lab:smoke` / workflow `post-deploy-smoke` |
| Backend `engine-service/*.test.ts` | Unit + HTTP integration (fake engine process) | **Không cần binary Pikafish** | `npm test` |
| Smoke test Pikafish thật (mục 11 của [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md)) | Thủ công hiện tại / nên chuyển thành `engine:smoke` | **Cần binary + NNUE thật** | tay hoặc script (chưa làm) |

---

*Tạo 2026-06-07 cùng đợt hoàn thiện nút "Đấu lại". Cập nhật 2026-06-07 (đợt 2): đóng hết Nhóm T — thêm `cchess-backend/src/server.test.ts` (integration WS) cho T3 rematch handshake + T7 reconnect + T8 chat; tách `server.ts` thành `createCChessServer()` factory để test in-process không cần Firebase. Cập nhật 2026-06-11 (đợt 3): hardening double-disconnect (D5) + test T10; nút Gợi ý in-game (Nhóm H + T11); chip chat nhanh (C8); ghi nhận bộ test engine-service (T9) vào tài liệu. Cập nhật 2026-06-12 (đợt 4): **kết quả test tay Nhóm R đầu tiên — 11/12 PASS**; bug R9 (độ trễ ~10s khi đối thủ rời phòng) tìm ra 3 nguyên nhân gốc và sửa cùng ngày + T12 regression. Cập nhật 2026-06-13 (đợt 5): **R9 retest PASS → Nhóm R đóng 12/12; C8 PASS** (rate-limit chat nâng 1.5s→2s theo feedback); **H1–H3 PASS** với feedback "gợi ý hơi lâu/hơi kém" → tuning best-effort (bỏ delay 1.2s, iterative deepening ngân sách 2s, depth tối đa 6) + T13, thêm case H4 theo dõi. Cập nhật 2026-06-13 (đợt 6): **S1–S12 PASS hết**; theo feedback UX code thêm: số mắt xem hiển thị cho cả người chơi, dialog kết quả người xem chỉ còn nút "Thoát" + tự xem tiếp khi rematch (sửa kèm bug spectator-thành-người-chơi-Đỏ sau rematch), phòng chờ tự hủy sau 1 phút (`room-expired`, TTL override env `CCHESS_WAITING_ROOM_TTL_MS`) → 3 case test tay mới S13–S15 + T14 (4 test tự động); tổng backend 28/28 + Flutter 156/156. Cập nhật 2026-06-18: thêm §8b — phân loại 23 case còn lại theo khả năng tự động hóa và lập phase A–E để chuyển dần test tay sang backend lab, Flutter controller/widget test, persistence/ELO test, smoke/staging script. Cập nhật 2026-06-19 (Đợt 1 tự động hóa backend — T16): hoàn thành **A3** (`matchmaking.test.ts` M1/M2 + M4 clock-per-room), **A4 một phần** (G3 resign + idempotency; G1 checkmate hoãn), **P-C1** (fake-persist → `game-ended.elo` wiring M5/G4/R11) + `elo.test.ts` (K=32). Backend `npm test` 32→**51 xanh**, không refactor source. Cập nhật 2026-06-19 (Đợt 2 tự động hóa Flutter — T17): hoàn thành **B1** (chat C1/C3/C4/C5/C6/C7), **B2** (reconnect D2/D3 + lifecycle D4), **B4** (result dialog G4/G5 — tách `online_result_format.dart`), và **P-D3** (workflow `flutter-ci.yml`: analyze + test trên `cchess/**`). Flutter `flutter test` 163→**198 xanh**, `flutter analyze` sạch; screen chỉ delegate sang helper thuần, không đổi hành vi. Lần cập nhật kế tiếp: B3 lobby/matchmaking UI + widget test trực quan (C2 badge / banner reconnect / dialog kết quả), hoặc phiên test tay D/M/G/H4.*
