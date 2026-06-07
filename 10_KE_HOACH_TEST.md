# ✅ KẾ HOẠCH TEST — CChess (các mục chưa xác nhận đã test)

> Tài liệu sống — tạo ngày **2026-06-07**.
> Mục đích: liệt kê **các kịch bản còn tồn đọng chưa test xong** để sắp lịch test dần.
> Phạm vi: tập trung các tính năng **online/multiplayer Sprint 12** vừa code xong (Đấu lại, Chat, Spectate, Reconnect, Matchmaking) — phần engine/offline (Sprint 1–7) đã có unit test xanh, không lặp lại ở đây.
> Tham chiếu: [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md), [`08_HUONG_DAN_BACKEND_WEBSOCKET.md`](08_HUONG_DAN_BACKEND_WEBSOCKET.md), [`09_BACKEND_SERVER_HOAT_DONG.md`](09_BACKEND_SERVER_HOAT_DONG.md).

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

## 2. Nhóm R — Đấu lại (Rematch) ⭐ *mới code, chưa test lần nào*

> Code liên quan: [online_game_screen.dart](cchess/lib/presentation/online/online_game_screen.dart) (`_showResultDialog`), [online_match_controller.dart](cchess/lib/presentation/online/online_match_controller.dart) (`offerRematch`/`declineRematch`/handlers), [server.ts](cchess-backend/src/server.ts) (`rematch-offer`/`rematch-decline`), [match.ts](cchess-backend/src/match.ts) (`startRematch`).

- [ ] **R1 — Hiện nút Đấu lại sau ván kết thúc bình thường.** Kết ván bằng chiếu bí (hoặc xin thua / hết giờ) → dialog kết quả hiện **"Về Đối Đầu"** + **"🔄 Đấu lại"**; tiêu đề đúng (Thắng/Thua/Hòa), dòng "Lý do" hiển thị tiếng Việt (Chiếu bí / Xin thua / Hết giờ), có dòng ELO.
- [ ] **R2 — Mời đấu lại (offer).** Bấm "Đấu lại" → dialog đổi sang **spinner + "Đang chờ đối thủ đồng ý đấu lại…"**, còn nút **"Hủy"** + "Về Đối Đầu". Bên đối thủ thấy banner **"Đối thủ muốn đấu lại!"** + nút **"Từ chối"/"Đồng ý"**.
- [ ] **R3 — Cả hai đồng ý → ván mới.** Khi cả 2 cùng mời/đồng ý:
  - Dialog kết quả **tự đóng** ở cả 2 máy.
  - Bàn cờ reset về thế ban đầu, đồng hồ reset đúng mức clock đã chọn.
  - **Màu đổi chỗ** (ai vừa đi Đỏ giờ đi Đen) — kiểm strip tên/màu trên–dưới.
  - Không còn highlight ô chọn cũ từ ván trước.
- [ ] **R4 — Đối thủ từ chối lời mời của mình.** Đang chờ (R2) mà đối thủ bấm "Từ chối" → mình thấy text đỏ **"Đối thủ đã từ chối đấu lại."**, dialog quay lại trạng thái mặc định (Về Đối Đầu + Đấu lại).
- [ ] **R5 — Tự hủy lời mời.** Đang chờ (R2) bấm **"Hủy"** → quay về mặc định ở máy mình; đối thủ nhận thông báo huỷ (banner "muốn đấu lại" biến mất).
- [ ] **R6 — Đối thủ mời trước, mình "Đồng ý".** Đối thủ mời (mình thấy banner) → bấm **"Đồng ý"** → ván mới bắt đầu (như R3).
- [ ] **R7 — Đối thủ mời trước, mình "Từ chối".** Bấm **"Từ chối"** → dialog quay về mặc định; đối thủ nhận thông báo từ chối.
- [ ] **R8 — Kết ván do đối thủ disconnect → KHÔNG cho đấu lại.** Nếu ván kết thúc với lý do `disconnect` → dialog chỉ có **"Về Đối Đầu"**, banner **"Đối thủ đã rời — không thể đấu lại."**, không có nút Đấu lại.
- [ ] **R9 — Đối thủ rời rồi mình mới bấm Đấu lại (xử lý lỗi êm).** Đối thủ bấm "Về Đối Đầu" thoát hẳn → mình bấm "Đấu lại" → nhận lỗi gracefully: text đỏ **"Không thể đấu lại — đối thủ đã rời phòng."**, **không** văng sang màn lỗi (phase=error), vẫn ở dialog kết quả. *(Đây là case dễ vỡ nhất — test kỹ.)*
- [ ] **R10 — Vòng lặp nhiều ván.** Sau R3, chơi hết ván 2 → dialog kết quả ván 2 hiện đúng, lại có nút Đấu lại; lặp được nhiều lần không treo / không double-dialog.
- [ ] **R11 — ELO/Profile cập nhật mỗi ván rematch.** Mỗi ván ranked sau rematch đều ghi ELO riêng; sau khi đóng dialog → màn Hồ Sơ phản ánh ELO/win-loss mới (auto-refresh).
- [ ] **R12 — Spectator khi 2 bên rematch.** Nếu có người đang xem trong phòng lúc rematch → họ nhận `game-start` ván mới (board reset), không bị kẹt ở màn kết quả.

---

## 3. Nhóm C — Chat trong ván

> Code: [online_game_screen.dart](cchess/lib/presentation/online/online_game_screen.dart) (chat sheet), [game_socket_service.dart](cchess/lib/data/services/game_socket_service.dart) (`sendChatMessage`), [server.ts](cchess-backend/src/server.ts) (`chat-message` + rate limit).

- [ ] **C1 — Gửi/nhận realtime giữa 2 người.** Tin nhắn hiện đúng bên (bong bóng mình bên phải, đối thủ bên trái), kèm thời gian.
- [ ] **C2 — Badge số tin nhắn.** Nút "Chat" hiển thị số lượng `(n)` khi có tin mới.
- [ ] **C3 — Rate limit.** Gửi liên tiếp < 1.5s → nhận lỗi **"Bạn gửi chat quá nhanh."** (`chat-rate-limited`).
- [ ] **C4 — Giới hạn 120 ký tự.** Gõ > 120 ký tự → bị chặn (client cắt + server `invalid-chat`).
- [ ] **C5 — Spectator chat.** Người xem gửi/nhận được chat trong phòng.
- [ ] **C6 — Khôi phục lịch sử chat sau reconnect.** Mất mạng → reconnect trong 60s → lịch sử chat (snapshot từ server) hiện lại đúng.
- [ ] **C7 — Chặn chat khi ván đã kết thúc.** Sau `game-ended`, gửi chat → server trả `not-playing` (kiểm hành vi UI không gửi được).

---

## 4. Nhóm S — Spectate + danh sách ván đang diễn ra + share link

> Code: [online_lobby_screen.dart](cchess/lib/presentation/online/online_lobby_screen.dart) (active rooms, deep-link), [rooms.ts](cchess-backend/src/rooms.ts) + [server.ts](cchess-backend/src/server.ts) (`list-active-rooms`, `spectate-room`, landing page `/r/:id`), [room_share.dart](cchess/lib/presentation/online/room_share.dart) + [share_room_sheet.dart](cchess/lib/presentation/online/share_room_sheet.dart).

- [ ] **S1 — Danh sách ván đang diễn ra.** Lobby hiển thị các phòng `playing` (roomId, số nước, số người xem, đồng hồ), sắp xếp theo thời gian bắt đầu mới nhất.
- [ ] **S2 — Xem bằng room ID.** Nhập/chạm 1 phòng → vào màn xem, nhận snapshot moves/clock/chat, bàn cờ cập nhật theo nước đi realtime.
- [ ] **S3 — Read-only.** Spectator KHÔNG chọn/đi quân được, KHÔNG có nút Xin thua.
- [ ] **S4 — Đếm người xem.** `spectatorCount` tăng/giảm khi có người vào/ra (cả ở header màn xem lẫn list lobby).
- [ ] **S5 — Dừng xem.** Bấm back/stop → quay lại lobby sạch sẽ, server nhận `stop-spectating`.
- [ ] **S6 — Refresh list.** Làm mới danh sách phản ánh phòng mới tạo / phòng vừa kết thúc (biến mất khỏi list).
- [ ] **S7 — Chia sẻ phòng từ lobby (đang chờ đối thủ).** Tạo phòng riêng → bấm **"Chia sẻ phòng (link / QR)"** → bottom sheet hiện QR + mã phòng + nút **Sao chép link / Chia sẻ**; QR quét ra link `/r/<ID>?mode=join`.
- [ ] **S8 — Chia sẻ link xem từ tile "ván đang diễn ra".** Icon share trên mỗi tile → sheet "Mời xem ván" (link `/r/<ID>` không có `mode=join`).
- [ ] **S9 — Chia sẻ từ app bar màn ván.** Đang chơi hoặc đang xem → icon share trên app bar mở sheet "Mời xem ván".
- [ ] **S10 — Sao chép & native share.** Nút "Sao chép link"/"Sao chép mã" → clipboard + snackbar; nút "Chia sẻ" mở native share sheet (Android/iOS); desktop không có handler → fallback copy.
- [ ] **S11 — Deep-link in-app.** Mở route `online-lobby?spectate=<ID>` → tự kết nối + vào xem; `?join=<ID>` → tự vào đánh. (Test nhanh qua [backend-test] hoặc điều hướng nội bộ; OS-level deep link chưa wire.)
- [ ] **S12 — Landing page backend.** Mở `https://cchess-backend.onrender.com/r/<ID>` trên trình duyệt → trang hiện mã phòng + nút "Sao chép mã"; `?mode=join` đổi tiêu đề sang "Lời mời vào phòng"; mã sai định dạng → HTTP 400.

---

## 5. Nhóm D — Disconnect / Reconnect (grace 60s)

> Code: [server.ts](cchess-backend/src/server.ts) (`reconnect-room`, grace timer), [online_game_screen.dart](cchess/lib/presentation/online/online_game_screen.dart) (`_remainingGraceSec` banner), [reconnect_store.dart](cchess/lib/data/services/reconnect_store.dart).

- [ ] **D1 — Banner mất kết nối.** Đối thủ tắt mạng → mình thấy banner vàng **"Đối thủ mất kết nối — còn 60s…"** đếm ngược.
- [ ] **D2 — Reconnect kịp.** Bật mạng/mở lại app trong 60s → ván tiếp tục đúng thế cờ, đúng đồng hồ, banner biến mất (`peer-reconnected`).
- [ ] **D3 — Hết grace.** Để quá 60s → ván tự kết thúc với lý do `disconnect`, người còn lại thắng, dialog kết quả hiện (lưu ý R8: không cho đấu lại).
- [ ] **D4 — Lifecycle nền vs kill.** Bấm Home (paused/hidden) → KHÔNG mất kết nối; vuốt kill app (detached) → vào grace + lần mở app sau auto-reconnect từ lobby (`tryAutoReconnect`).
- [ ] **D5 — Double-disconnect** *(hardening chưa code — chỉ ghi nhận hành vi hiện tại).* Cả 2 mất mạng cùng lúc → quan sát server xử lý ra sao, ghi lại để làm hardening sau.

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

## 8. Nhóm T — Test tự động ✅ ĐÃ ĐÓNG HẾT (8/8 xanh)

> Mục này là **viết test code**, không phải test tay. Ưu tiên làm để khỏi phải test tay lặp lại các case ở trên.
> **Trạng thái 2026-06-07:** T1–T8 đều xanh. Backend `cd cchess-backend && npm test` → 17/17. Flutter `cd cchess && flutter test test/online` → 25/25 (`online_match_controller_test.dart` 8 + `room_share_test.dart` 17).

- [x] **T1 — `rooms.test.ts`** (backend): spectator read-only, spectator leave, active room filtering. *(3 test, pass)*
- [x] **T2 — `match.test.ts`** (backend): `startMatch` (gán màu/clock/turn/engine), `applyMove` hợp lệ/`not-your-turn`/`illegal-move`/`not-player`/`time-out` + trừ đồng hồ, **`startRematch`** (đổi màu + reset clock/engine/moves + clear cờ offer; fail khi <2 người). *(8 test, pass)*
- [x] **T3 — `server.test.ts` rematch handshake** (backend, **integration WS thật** qua `createCChessServer` + 2 client `ws` trên cổng ephemeral, auth/persist được inject giả): cả 2 `rematch-offer` → cả 2 nhận `game-start{rematch:true}` với **màu đã đổi chỗ** (cùng `roomId`); `rematch-decline` → bên mời nhận `rematch-declined{from}`; `rematch-offer` khi ván **chưa kết thúc** → `error{not-finished}`. *(3 test, pass — đã dựng được server test harness in-process, không cần Firebase nhờ tách `server.ts` thành factory + guard `CCHESS_NO_LISTEN`.)*
- [x] **T4 — `OnlineMatchController` test** (Flutter, fake socket): `offerRematch` set cờ + gửi lệnh (no-op khi chưa ended); nhận `rematch-offered`/`rematch-declined` set/clear cờ đúng; `game-start` rematch reset cờ + về playing; `_onError` giữ phase=ended khi lỗi rematch (`no-opponent`). *(test tại [online_match_controller_test.dart](cchess/test/online/online_match_controller_test.dart))*
- [x] **T5 — `OnlineMatchController` core** (Flutter): `_onGameEnded` set result/reason + clear reconnect store; `attemptMove` optimistic (flip turn + gửi move) + rollback khi server `illegal-move`. *(gộp chung file test ở trên — tổng 8 test, pass)*
- [x] **T6 — `room_share_test.dart`** (Flutter, A6 share link): `normalizeRoomId`/`isValidRoomId`, `linkFor` (spectate vs `mode=join`, strip trailing slash), `inviteText`, `roomIdFromLink` (bare code / `/r/` / `cchess://` / `?spectate|join=` / junk→null / round-trip), `isJoinLink`. *(17 test, pass)*
- [x] **T7 — `server.test.ts` reconnect integration** (backend, integration WS): chơi 1 nước hợp lệ → đỏ rớt mạng (đóng socket) → đối thủ nhận `peer-disconnected{graceMs>0}` → đỏ `reconnect-room` trong grace → nhận `reconnected` snapshot đúng (`yourColor`, `moves`, `currentTurn`) + đối thủ nhận `peer-reconnected`. *(1 test, pass — tự động hoá phần lõi Nhóm D2.)*
- [x] **T8 — `server.test.ts` chat integration** (backend, integration WS): `chat-message` phát cho cả 2 bên kèm `from`; gửi liên tiếp → `error{chat-rate-limited}`; >120 ký tự → `error{invalid-chat}`; sau `game-ended` → `error{not-playing}`. *(2 test, pass — tự động hoá Nhóm C1/C3/C4/C7.)*

> **Backend `npm test` tổng cộng 17/17 xanh** (`rooms.test.ts` 3 + `match.test.ts` 8 + `server.test.ts` 6).

---

## 9. Bảng theo dõi tiến độ

| Nhóm | Tổng case | Đã PASS | Bug | Còn lại |
|---|:---:|:---:|:---:|:---:|
| R — Đấu lại | 12 | 0 | 0 | 12 |
| C — Chat | 7 | 0 | 0 | 7 |
| S — Spectate + share link | 12 | 0 | 0 | 12 |
| D — Reconnect | 5 | 0 | 0 | 5 |
| M — Matchmaking/ELO | 5 | 0 | 0 | 5 |
| G — Lifecycle | 6 | 0 | 0 | 6 |
| T — Test tự động | 8 | 8 | 0 | 0 |
| **Tổng** | **55** | **8** | **0** | **47** |

> Cập nhật bảng này sau mỗi đợt test. **Nhóm T đã ĐÓNG HẾT (8/8 xanh)** — T3 handshake WS đã viết xong cùng harness in-process (`server.test.ts`), thêm T7 (reconnect integration) + T8 (chat integration) tự động hoá luôn phần lõi của Nhóm D2 và Nhóm C1/C3/C4/C7. Phần còn lại chủ yếu là **test tay E2E cần 2 thiết bị** (Nhóm R/S/D/M/G còn các nhánh UI + đa thiết bị mà test tự động không phủ được). Tiếp theo ưu tiên test tay **Nhóm R** (tính năng mới nhất, rủi ro cao nhất, đặc biệt R9), rồi **S7–S12** (A6 share link).

---

*Tạo 2026-06-07 cùng đợt hoàn thiện nút "Đấu lại". Cập nhật 2026-06-07 (đợt 2): đóng hết Nhóm T — thêm `cchess-backend/src/server.test.ts` (integration WS) cho T3 rematch handshake + T7 reconnect + T8 chat; tách `server.ts` thành `createCChessServer()` factory để test in-process không cần Firebase. Lần cập nhật kế tiếp: sau đợt test tay Nhóm R đầu tiên.*
