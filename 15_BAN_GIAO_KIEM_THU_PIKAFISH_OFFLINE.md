# 15 — Bàn giao kiểm thử Pikafish Offline

> Cập nhật: 2026-07-23 — Android QA thiết bị thật **PASS toàn bộ** (xem mục 4); tài liệu này đã merge vào `main`.
> Mục tiêu: có thể tiếp tục nghiệm thu engine và Pikafish Offline trên bất kỳ máy nào mà không phải lặp lại các bước đã xác nhận.

## 1. Mốc hiện tại

- Nhánh gốc kiểm thử: `main` tại `6d6d559` — Cờ Úp replay với theo dõi quân úp/lật quân.
- Backend: `npm test` **186/186 pass**; `npx tsc --noEmit` pass.
- Render `cchess-engine`: đang `live` tại commit `23fa74e` (`feat: Enhance analysis engine with progress reporting and caching`).
- So với `23fa74e`, `main` chỉ có thay đổi Flutter/replay Cờ Úp; **không có thay đổi trong `cchess-backend/`**, vì vậy không cần redeploy engine chỉ để bắt đầu QA này.

## 2. Đã xác nhận trên production

Endpoint mặc định: `https://cchess-engine.onrender.com`.

| Kiểm tra | Kết quả | Bằng chứng |
|---|---|---|
| Engine smoke | PASS | `npm run engine:smoke` — **8/8 passed** |
| Auth + engine pool + FEN lỗi + best move + cache + hint + analyze + FEN/UCI | PASS | Nằm trong smoke 8/8 |
| Async analysis | PASS | `POST /engine/analyze-jobs` nhận job `queued`; poll đầu tiên trả `done`, `progress=1`, `completedMoves=1/1` |
| Dữ liệu đánh giá | PASS | Response có `perMove.evalAfterCp`, `classification`, `summary` |
| Tải NNUE có auth | PASS | `GET /engine/nnue` tải file **50.75 MB** |
| Toàn vẹn NNUE | PASS | SHA-256: `c4026370d7516d9b0f668447f9ca1931241538bdc689cde6fec6a991ac4d5f77` — khớp `AppConstants.pikafishNnueSha256` |

## 3. Chuẩn bị lại trên máy khác

1. Clone repo, checkout nhánh cần test (thường là `main`) và chạy trong `cchess-backend/`:

   ```powershell
   npm ci
   npm test
   npx tsc --noEmit
   ```

2. Nếu cần xem/trig deploy Render, tạo API key tại Render → Account Settings → API Keys, lưu ở **user environment variable** `RENDER_API_KEY` (không commit/paste vào repo), sau đó mở terminal mới:

   ```powershell
   npm run render:status -- cchess-engine
   ```

3. Smoke production trước khi test app:

   ```powershell
   npm run engine:smoke
   ```

## 4. Android thật — ĐÃ NGHIỆM THU (PASS, 2026-07-23)

**Kết quả: PASS toàn bộ A/B/C** (cài NNUE, gợi ý offline, phân tích/phục bàn offline) trên thiết bị Android thật, bản release. Chi tiết đo đạc từng bước (thiết bị cụ thể, thời gian tải, nhiệt độ/pin) chưa được ghi lại kèm — xem mẫu ở mục D nếu cần bổ sung sau.

Thiết bị thật arm64 Android đã được phát hiện; cần chạy bản **release**, không dùng emulator cho phần nhiệt/pin và extraction native binary.

```powershell
cd cchess
flutter run --release -d <android-device-id>
```

Sau khi app mở, thực hiện checklist theo thứ tự. Không test AI trên Cờ Úp: sản phẩm chủ động chặn phân tích Cờ Úp.

### A. Cài NNUE — ✅ PASS

- Vào **Hồ sơ → Cài đặt → AI Offline**.
- Tải AI Offline; xác nhận hoàn tất, không có lỗi checksum và trạng thái ready/đã cài.
- Ghi thời gian tải và dung lượng hiển thị (xấp xỉ 50.75 MB).

### B. Gợi ý khi offline — ✅ PASS

- Bật Airplane mode **sau** khi NNUE đã tải xong.
- Tạo ván **Cờ Tướng thường** với bot, đi một vài nước, bấm **Gợi ý**.
- Pass khi UI ghi nguồn **Pikafish Offline**, trả nước hợp lệ và app không crash.
- Fail cần ghi rõ nếu UI chỉ dùng "Phân tích nhanh (offline)"/minimax, báo không có AI Offline, treo hoặc crash.

### C. Phân tích/phục bàn khi offline — ✅ PASS

- Kết thúc ván thường khoảng 8–15 nước, mở lại từ Lịch sử → Phục bàn → Phân tích ván.
- Pass khi có tiến độ, kết quả nước đi + biểu đồ, nguồn **Pikafish Offline**, và không fallback âm thầm sang minimax.
- Thoát hẳn app, mở lại khi vẫn Airplane mode, chạy lại Gợi ý hoặc Phân tích để xác nhận NNUE tồn tại sau restart.

### D. Ghi nhận hiệu năng

Kết quả tổng hợp 2026-07-23: **PASS** cả A/B/C, không crash, không fallback âm thầm sang minimax. Số liệu chi tiết theo mẫu dưới đây **chưa được ghi lại** (thiết bị cụ thể, thời gian tải, nhiệt độ/pin) — bổ sung khi có lần chạy tiếp theo:

```text
Thiết bị / Android:
NNUE: tải thành công / lỗi; thời gian; dung lượng
Gợi ý offline: Pikafish Offline / nguồn khác / lỗi; thời gian
Phân tích offline: pass / lỗi; số nước; thời gian
Restart: pass / lỗi
Nhiệt / pin / UI: bình thường / chi tiết bất thường
```

## 5. Việc còn lại sau Android QA

1. Đối chiếu chất lượng chấm điểm trên 3 ván mẫu: một blunder mất Xe, một ván cân bằng, một mate sớm.
2. Xác nhận license thương mại của NNUE/Pikafish trước phát hành thương mại.
3. Chỉ khi có traffic thật mới nâng `cchess-engine` Render từ Free lên Standard và theo dõi cold start/latency.

## 6. Lưu ý an toàn

- `FIREBASE_SERVICE_ACCOUNT_JSON`, Firebase ID token và `RENDER_API_KEY` là bí mật; tuyệt đối không ghi vào tài liệu, commit hoặc chat.
- Smoke/quota smoke có thể tạo Firebase Anonymous user thử nghiệm; không dùng tài khoản người chơi thật để kiểm quota.

---

## 7. QA S16 Economy trên Android — PASS (2026-07-23, emulator)

Bản release `main@3dbb804`, emulator Phone_3 (Android, 1080×2400), backend production Render + Firestore `cchess-dev`. Đi trọn vòng lặp kinh tế bằng tay:

| Bước | Kết quả |
|---|---|
| Hub Khám Phá: 6 tile sống + ví | PASS — ví khớp từng phép cộng/trừ (410 đồng + 22 ngọc cuối phiên) |
| D5 Sự Kiện: nhận 2 quà `quoc-khanh-2026` | PASS — "+290 đồng, +2 ngọc" và "+5 hint_pack_5, +3 manh-ngoc"; nhận lại bị chặn (✓) |
| D7 Đúc Bàn Cờ: đúc Bàn Ngọc Bích | PASS — nguyên liệu 3/3→0/3, ví −200, nút chuyển "Đã sở hữu"; recipe thiếu nguyên liệu bị khóa đúng |
| Balo: bàn đúc xuất hiện + Trang bị | PASS — "Đang dùng" + nút Gỡ; tab Công cụ có 5 gói gợi ý |
| D6 Phúc Lợi: điểm danh + quà tân thủ | PASS — "+20 đồng" (N1 ✓, chuỗi 1) và "+200 đồng, +10 ngọc"; điểm danh lại bị chặn, thẻ tân thủ biến mất |
| D4 Hộp Thư: gửi qua Admin SDK → badge → nhận | PASS — badge "1" trên hub, mail hiện đủ, "+68 đồng, +1 ngọc", "Đã nhận" + nút xóa |

**Bug tìm thấy & đã sửa trong phiên** (`3dbb804`): hub badge giữ `mailProvider` (autoDispose) sống → mở Hộp Thư dùng cache cũ, mail gửi sau khi mở app không hiện (phải restart); màn trống không kéo-refresh được. Fix: invalidate khi vào màn + bọc empty state trong RefreshIndicator.

**Ghi chú còn lại (ngoài phạm vi S16):**
1. Restart app sau force-stop quay lại onboarding (`onboardingCompleted` chưa bền?) — cần xem lại luồng onboarding.
2. Balo tab Công cụ hiển thị nhãn payloadKey ("Công cụ • hint_pack") thay vì tên đẹp từ catalog — polish nhỏ có sẵn từ trước.
3. Nội dung QA này chạy trên emulator (đủ cho REST+UI economy); không thay thế QA nhiệt/pin thiết bị thật của Pikafish (mục 4).
