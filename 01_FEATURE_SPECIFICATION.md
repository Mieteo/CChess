# 📋 TÀI LIỆU ĐẶC TẢ TÍNH NĂNG
# Game Cờ Tướng Việt Nam — Dự án CChess
# Phiên bản: 1.0 | Ngày: 2026-05-12 (spec gốc; trạng thái triển khai cập nhật riêng ở [`05_KE_HOACH_DU_AN.md`](05_KE_HOACH_DU_AN.md))

> Doc này là **spec đặc tả** — nội dung tính năng ổn định, không thay đổi theo từng commit. Trạng thái "đã làm / chưa làm / chờ phụ thuộc" được track ở doc 05 và làm sống. Doc 01 chỉ revise khi scope tính năng thật sự đổi.

---

## 1. TỔNG QUAN SẢN PHẨM

### 1.1 Định hướng sản phẩm
- **Tên dự án:** CChess (tên tạm, có thể đổi)
- **Platform:** Flutter (Android, iOS, Web)
- **Ngôn ngữ UI:** Tiếng Việt
- **Phong cách đồ họa:** Thủy mặc Á Đông (ink-wash), gam màu nâu gỗ + vàng đồng
- **Đối tượng:** Người chơi cờ tướng Việt Nam, mọi lứa tuổi
- **Mô hình kinh doanh:** Freemium (miễn phí cơ bản + VIP subscription + cosmetics)

### 1.2 Benchmark tham chiếu
- **Cờ Ziga** (Việt Nam): chuẩn tối thiểu về UX, ELO, kết bạn
- **Thiên Thiên Tượng Kỳ** (Tencent): chuẩn đích về học cờ, AI analysis, cộng đồng

---

## 2. KIẾN TRÚC TÍNH NĂNG (Feature Architecture)

```
CChess App
├── [TAB 1] Đánh Cờ        (下棋)
├── [TAB 2] Học Cờ          (学棋)
├── [TAB 3] Cộng Đồng       (棋界)
├── [TAB 4] Khám Phá        (发现)
└── [TAB 5] Cá Nhân         (我)
```

---

## 3. CHI TIẾT TÍNH NĂNG TỪNG MODULE

---

### MODULE A — ĐÁNH CỜ (下棋)

#### A1. Cờ Tướng Online (Ranked Match)
- Ghép đối thủ tự động theo ELO (matchmaking)
- Hiển thị số người đang online real-time
- Thời gian mỗi ván: 15 phút, mỗi nước tối đa 60 giây
- Kết thúc ván: Chiếu bí / Hết nước / Chống tướng / Hết giờ / Đầu hàng / Hòa
- Đánh giá: Cộng/trừ ELO sau mỗi ván

#### A2. Cờ Tướng Casual (Friendly Match)
- Chơi không tính điểm ELO
- Mời bạn bè qua ID hoặc link

#### A3. Cờ Úp (Biến thể)
- Quân cờ úp ngẫu nhiên ban đầu, trừ Tướng
- ELO riêng biệt với Cờ Tướng thường

#### A4. Các biến thể mở rộng (giai đoạn sau)
- Kiệt kỳ (揭棋): biến thể từ Hồng Kông
- Ngũ tử kỳ (五子棋)
- Phiên kỳ / Tứ quốc tượng kỳ

#### A5. Tính năng trong ván đấu
- Chat nhanh (câu cố định) + emoji biểu cảm
- Gợi ý nước đi (AI hint) — giới hạn lần dùng/ngày
- Xin hòa, đầu hàng, ra ngoài
- Bật/tắt âm thanh, nhạc nền
- Hiển thị đồng hồ đếm ngược trực quan

#### A6. Chế độ Xem Cờ (Spectate)
- Xem ván đấu đang diễn ra của người khác
- Bình luận chat cùng người xem khác

#### A7. Chế độ Luyện với AI (Bot)
- 5–10 cấp độ AI từ dễ đến rất khó
- Không tính ELO, phù hợp người mới

---

### MODULE B — HỌC CỜ (学棋)

#### B1. Khóa học cơ bản (Khai tâm)
- Luật đi từng loại quân: Xe, Pháo, Mã, Tượng, Sĩ, Tốt, Tướng
- Các tình huống đặc biệt: Chiếu bí, Chống tướng
- Phù hợp hoàn toàn người mới

#### B2. Khóa học online (Video + Text)
- Nội dung do cộng tác viên kỳ thủ Việt Nam sản xuất
- Phân cấp: Cơ bản → Trung cấp → Nâng cao
- Các chủ đề: Khai cuộc, Trung cuộc, Tàn cuộc

#### B3. Gia sư cờ riêng (AI Coach)
- AI phân tích lịch sử ván đấu của người chơi
- Xác định điểm yếu (khai cuộc/trung cuộc/tàn cuộc)
- Đề xuất bài tập cá nhân hóa hàng ngày
- *[VIP]*: Phân tích sâu hơn, không giới hạn

#### B4. Kho bài tập (Đề thư)
- Tàn cục cổ điển: mục tiêu chiếu hết trong N nước
- Phân loại theo độ khó và chủ đề chiến thuật
- Mục tiêu: 10.000+ bài tập
- Chấm điểm và thống kê tỷ lệ đúng

#### B5. Kỳ phổ & Phục bàn
- Lưu trữ ván đấu dưới dạng kỳ phổ (PGN/XiangQi format)
- Phục bàn thủ công: đi từng nước
- **Phục bàn thông minh (AI Replay):** AI đánh giá từng nước, chỉ ra nước hay/dở
- *[VIP]*: Lưu trữ không giới hạn kỳ phổ

#### B6. Khai cuộc của Đại sư
- Thư viện các thế khai cuộc phổ biến
- Cây biến thể (variation tree) trực quan

#### B7. Chụp ảnh nhận dạng thế cờ (OCR/AI)
- Dùng camera chụp bàn cờ thực
- AI nhận dạng vị trí quân và import vào app
- Cho phép phân tích hoặc tiếp tục đánh từ thế đó

#### B8. Chế độ Học thuộc kỳ phổ (暗棋 mode)
- Người chơi tự nhớ và tái hiện lại một ván đấu mẫu
- Hỗ trợ ghi nhớ khai cuộc và endgame pattern

---

### MODULE C — CỘNG ĐỒNG (棋界)

#### C1. Bạn bè
- Tìm bạn theo tên/ID
- Mời bạn vào ván đấu, xem ván đấu
- Danh sách bạn bè online/offline

#### C2. Bảng xếp hạng (Leaderboard)
- Top toàn quốc theo ELO Cờ Tướng
- Top theo khu vực (tỉnh/thành phố)
- Top Cờ Úp riêng biệt

#### C3. Câu lạc bộ Cờ (Kỳ Xã)
- Tạo/tham gia CLB theo nhóm bạn bè hoặc địa phương
- Phòng riêng CLB để thi đấu nội bộ
- Bảng điểm CLB

#### C4. Giải đấu (Thi đấu)
- Giải đấu định kỳ do hệ thống tổ chức
- Giải đấu do người dùng tự tổ chức
- Bracket system, live scoring

#### C5. Livestream
- Phát trực tiếp ván đấu của bản thân
- Xem livestream kỳ thủ khác
- Chat real-time khi xem livestream

#### C6. Tin tức & Bài viết
- Tin tức giới cờ Việt Nam
- Bài phân tích ván đấu nổi bật
- Thử thách tàn cục hàng ngày (Tàn Cục Thách Đấu)

#### C7. Diễn đàn Cộng đồng
- Đăng bài, bình luận, chia sẻ thế cờ hay
- Chức năng "Thách đấu" từ bài viết

---

### MODULE D — KHÁM PHÁ (发现)

#### D1. Thương Thành (Shop)
- Mua vật phẩm trang trí bằng tiền thật hoặc tiền game
- Bán theo thời gian (vĩnh viễn) hoặc sự kiện giới hạn

#### D2. Balo vật phẩm (Inventory)
- Quản lý tất cả items đã sở hữu
- Tab con: Công cụ, Nhạc hiệu, Bàn cờ, Quân cờ, Trang phục nhân vật

#### D3. Khung Avatar & Danh hiệu
- Khung avatar theo mùa giải / sự kiện
- Bong bóng chat tùy chỉnh
- Biệt danh (Nickname badge)
- Biển hiệu (Nameplate)

#### D4. Hộp thư (Mail)
- Nhận quà từ hệ thống
- Thông báo giải đấu, sự kiện

#### D5. Sự kiện (Activities)
- Sự kiện theo mùa: Tết, 30/4, 2/9...
- Nhiệm vụ hàng ngày/hàng tuần
- Đổi quà sự kiện

#### D6. Phúc Lợi (Welfare)
- Điểm danh hàng ngày nhận thưởng
- Quà tân thủ (người mới)
- Quà quay lại (người đã lâu không chơi)

#### D7. Đúc Bàn Cờ / Điểm Sáng Quân Cờ
- Hệ thống crafting: Kết hợp vật liệu để tạo bàn cờ unique
- Nâng cấp hiệu ứng quân cờ

---

### MODULE E — CÁ NHÂN (我)

#### E1. Hồ sơ người chơi
- Avatar, tên, ID, khu vực
- Điểm tín dụng (thái độ chơi)
- Cấp bậc hiển thị: Tập sự → Kỳ Sĩ → Kỳ Tướng → Kỳ Vương → ...

#### E2. Thống kê chi tiết
- Tổng ván, tỷ lệ thắng tổng
- ELO theo từng thể loại
- Thống kê theo khai cuộc yêu thích
- Biểu đồ tiến bộ theo thời gian

#### E3. Hệ thống Huy chương (Achievement/Badge)
- Huy chương thành tích: 10 thắng liên, 100 thắng, ...
- Huy chương sự kiện giới hạn
- Huy chương kỹ năng: Pháo thủ, Xe điên, ...

#### E4. Hệ thống Nhiệm vụ
- Nhiệm vụ hàng ngày (Daily Quest)
- Nhiệm vụ hàng tuần (Weekly Quest)
- Nhiệm vụ thành tích dài hạn

#### E5. VIP Center (Hội Viên)
- Xem quyền lợi VIP hiện tại
- Nâng cấp VIP
- Tặng VIP trải nghiệm cho bạn bè (VIP chính thức)
- Cửa hàng điểm VIP

#### E6. Tài khoản & Bảo mật
- Liên kết: Facebook, Google, Apple ID
- Đổi tên (giới hạn 1 lần)
- Đăng xuất, Xóa tài khoản

#### E7. Cài đặt
- Nhạc game, âm hiệu
- Cài đặt ván đấu (góc nhìn quân mặc định...)
- Riêng tư & chống quấy rối
- Giới hạn thời gian chơi (Healthy Gaming)
- Chính sách thu thập dữ liệu

---

## 4. HỆ THỐNG XẾP HẠNG ELO

### 4.1 Thang ELO Cờ Tướng
| Điểm ELO | Cấp bậc |
|---|---|
| < 1200 | Tập Sự ⭐ |
| 1200–1400 | Kỳ Sinh ⭐⭐ |
| 1400–1600 | Kỳ Sĩ ⭐⭐⭐ |
| 1600–1800 | Kỳ Tướng ⭐⭐⭐ |
| 1800–2000 | Kỳ Soái ⭐⭐⭐ |
| 2000–2200 | Kỳ Vương ⭐⭐⭐ |
| 2200+ | Kỳ Thánh 👑 |

### 4.2 Quy tắc tính ELO
- Công thức ELO chuẩn quốc tế (K-factor tùy theo số ván đã chơi)
- ELO Cờ Tướng và Cờ Úp tính riêng biệt
- ELO ban đầu: 1000 điểm

---

## 5. MÔ HÌNH MONETIZATION

### 5.1 Loại tiền tệ
| Loại | Nguồn gốc | Dùng để |
|---|---|---|
| Đồng Tiền (铜钱) | Điểm danh, nhiệm vụ, thắng ván | Mua items cơ bản |
| Ngọc Bội (元宝) | Nạp tiền, xem quảng cáo | Mua items cao cấp |
| Điểm VIP | Dùng VIP, nạp tiền | Cửa hàng VIP exclusive |

### 5.2 Gói VIP (đề xuất)
- **VIP Tháng:** 29.000đ/tháng
- **VIP Quý:** 79.000đ/3 tháng
- **VIP Năm:** 249.000đ/năm

### 5.3 VIP bao gồm
- AI Coach phân tích không giới hạn
- Lưu trữ kỳ phổ không giới hạn
- Tắt quảng cáo hoàn toàn
- AI hint không giới hạn
- Đặc quyền cosmetic hàng tháng
- Giải đấu VIP exclusive

---

## 6. LỘ TRÌNH PHÁT TRIỂN (Roadmap)

### 🟢 GIAI ĐOẠN 1 — MVP (Tháng 1–3)
**Mục tiêu:** App có thể chơi được, đủ tính năng cơ bản

**Tính năng:**
- [A1] Cờ Tướng Online với ELO cơ bản
- [A5] Chat nhanh + emoji trong ván
- [A7] Chế độ luyện với AI (3 cấp độ)
- [B1] Khóa học vỡ lòng
- [B4] Kho bài tập tàn cục (500 bài)
- [C1] Hệ thống bạn bè cơ bản
- [C2] Bảng xếp hạng ELO
- [E1] Hồ sơ người chơi + cấp bậc
- [E2] Thống kê ván đấu cơ bản
- [D6] Điểm danh hàng ngày

**Tech stack:**
- Flutter (Android + iOS)
- Backend: Firebase (Auth, Firestore, Realtime DB)
- Chess engine: Pikafish/Stockfish port
- WebSocket cho multiplayer real-time

---

### 🟡 GIAI ĐOẠN 2 — Community (Tháng 4–6)
**Mục tiêu:** Xây dựng cộng đồng, giữ chân người dùng

**Tính năng mới:**
- [A3] Cờ Úp Online
- [A6] Chế độ Xem Cờ (Spectate)
- [B5] Kỳ phổ & Phục bàn thủ công
- [B6] Khai cuộc Đại sư
- [C3] Câu lạc bộ Cờ (Kỳ Xã)
- [C4] Giải đấu định kỳ
- [C6] Tin tức & Tàn cục thách đấu hàng ngày
- [D2] Balo vật phẩm + cosmetics cơ bản (bàn cờ, quân cờ)
- [D3] Khung avatar
- [E3] Huy chương thành tích
- [E4] Nhiệm vụ hàng ngày/tuần

---

### 🔴 GIAI ĐOẠN 3 — Monetization & AI (Tháng 7–12)
**Mục tiêu:** Doanh thu bền vững, tính năng học cờ cạnh tranh với TTK

**Tính năng mới:**
- [B3] AI Coach cá nhân hóa
- [B5] AI Replay (phục bàn thông minh)
- [B7] Chụp ảnh nhận dạng thế cờ
- [B8] Chế độ học thuộc kỳ phổ
- [C5] Livestream ván đấu
- [C7] Diễn đàn cộng đồng
- [D1] Thương Thành đầy đủ
- [D5] Sự kiện theo mùa
- [D7] Hệ thống crafting bàn cờ
- [E5] VIP Center đầy đủ
- Giải đấu quốc gia / Mùa giải chính thức

---

### 🔵 GIAI ĐOẠN 4 — Expansion (Năm 2+)
- Kiệt kỳ, Ngũ tử kỳ
- Hệ thống chứng chỉ棋力 (thi chứng nhận trình độ)
- Tích hợp giáo viên dạy cờ real (marketplace)
- Web version đầy đủ
- Giải đấu quốc tế (kết nối với platform Trung Quốc/quốc tế)

---

## 7. YÊU CẦU KỸ THUẬT

### 7.1 Frontend (Flutter)
- Flutter SDK >= 3.x
- State management: Riverpod hoặc BLoC
- Navigation: GoRouter
- Animation: Flutter Animation + Lottie
- Local storage: Hive / SharedPreferences

### 7.2 Backend
- Firebase: Authentication, Firestore, Realtime Database, Cloud Functions
- WebSocket server (Node.js): Game room management, real-time moves
- REST API: Kỳ phổ, ranking, content
- CDN: Ảnh, video khóa học

### 7.3 AI / Chess Engine
- Pikafish — engine cờ tướng mạnh nhất (phái sinh từ Stockfish, đánh giá NNUE). **Lưu ý: KHÔNG phải Fairy-Stockfish** (Fairy-Stockfish là engine đa biến thể khác) — Pikafish là engine chuyên cờ tướng.
- Tích hợp **server-side** (chạy trên backend, app gọi qua API) thay vì FFI on-device — tránh ràng buộc GPL-3.0 khi phát hành app thương mại. Xem [`11_KE_HOACH_TICH_HOP_ENGINE.md`](11_KE_HOACH_TICH_HOP_ENGINE.md).
- Engine offline/bot nhẹ: minimax Dart on-device (đã có). AI Coach: Pikafish (server) + rule-based feedback.

### 7.4 Bảo mật
- JWT authentication
- Chống gian lận: move validation phía server
- Rate limiting
- Mã hóa dữ liệu người dùng

---

*Tài liệu này sẽ được cập nhật theo từng giai đoạn phát triển.*
*Phiên bản tiếp theo: Chi tiết database schema và API design.*
