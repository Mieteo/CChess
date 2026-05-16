# 🎨 PROMPT — THIẾT KẾ UI/UX
# Game Cờ Tướng Việt Nam — CChess
# Dành cho: AI code assistant (GitHub Copilot, Cursor, Claude)
# File: 02_PROMPT_UI_UX.md

---

## PROMPT TỔNG QUAN (Master UI Prompt)

```
Bạn là một Flutter UI/UX expert chuyên về game mobile.
Nhiệm vụ: Thiết kế và implement toàn bộ UI/UX cho app cờ tướng Việt Nam "CChess" trên Flutter.

DESIGN LANGUAGE (bắt buộc áp dụng xuyên suốt):
- Phong cách: Cổ điển Á Đông, thủy mặc (ink-wash), gỗ quý
- Màu chủ đạo:
  • Background: #5C3A1E (nâu gỗ đậm) và #D4A96A (nâu gỗ sáng)
  • Accent: #C8960C (vàng đồng) và #8B0000 (đỏ son)
  • Text chính: #2C1810 (nâu đen)
  • Text phụ: #7D5A3C (nâu nhạt)
  • Card/Panel: #F5E6C8 (kem ngà)
  • Success: #4A7C59 (xanh cổ vịt)
- Typography:
  • Font chính: "Noto Serif" hoặc "Source Serif Pro" (có dấu tiếng Việt)
  • Font logo/title: Calligraphy-style nếu có (custom font)
  • Size: Title 24px, Heading 18px, Body 14px, Caption 12px
- Border radius: 8–12px cho card, 24px cho button chính
- Shadow: Soft drop shadow màu nâu (#5C3A1E33)
- Icon style: Line-art, nét mảnh, vintage

COMPONENT LIBRARY cần tạo (theo thứ tự):
```

---

## PROMPT 01 — App Shell & Navigation

```
Tạo AppShell cho CChess Flutter app với các yêu cầu sau:

1. BOTTOM NAVIGATION BAR:
   - 5 tab: Đánh Cờ (icon: bàn cờ), Học Cờ (icon: sách), Cộng Đồng (icon: nhóm người),
     Khám Phá (icon: la bàn), Cá Nhân (icon: avatar)
   - Background: #5C3A1E, selected icon: #C8960C, unselected: #A07850
   - Badge đỏ cho thông báo chưa đọc
   - Animation khi chuyển tab: slide + fade

2. APP BAR (custom):
   - Logo "CChess" ở giữa, font calligraphy, màu #C8960C
   - Nút thông báo (🔔) bên phải
   - Nút cài đặt gear bên phải
   - Background: linear gradient từ #5C3A1E xuống #7A4E2D

3. SPLASH SCREEN:
   - Background: full-screen ink-wash painting (asset SVG hoặc PNG)
   - Logo animate fade-in từ trung tâm
   - Loading indicator kiểu brush stroke (custom painter)
   - Delay 2 giây rồi navigate đến Home

4. Dùng GoRouter cho navigation.
5. State management: Riverpod (ProviderScope bọc ngoài cùng).

Output: app_shell.dart, bottom_nav_bar.dart, splash_screen.dart, router.dart
```

---

## PROMPT 02 — Màn hình Đánh Cờ (Chess Game Screen)

```
Tạo màn hình game cờ tướng với các component sau:

1. CHESS BOARD WIDGET (core):
   - Kích thước: 9 cột x 10 hàng
   - Background bàn cờ: màu gỗ #D4A96A, đường kẻ #5C3A1E, độ dày 1.5px
   - Vùng cung (palace): vẽ đường chéo X
   - Sông (river): text "Sở Hà" bên phải, "Hán Giới" bên trái, font Noto Serif italic
   - Fit màn hình mobile: bàn cờ chiếm ~65% chiều cao màn hình

2. CHESS PIECE WIDGET:
   - Hình tròn, viền 2px màu đỏ (#8B0000) cho quân đỏ / xanh (#1A3A5C) cho quân đen
   - Background: gradient nâu gỗ (#D4A96A → #A07850)
   - Chữ Hán ở giữa, font bold, màu tương ứng đỏ/đen
   - Kích thước: ~38px diameter (co dãn theo màn hình)
   - Quân được chọn: glow effect màu vàng + scale 1.1x
   - Valid move indicator: chấm tròn nhỏ màu vàng (#C8960C88) bán trong suốt

3. PLAYER INFO PANEL (trên và dưới bàn cờ):
   - Avatar tròn + border ELO color
   - Tên người chơi + badge cấp bậc
   - Đồng hồ đếm ngược: font monospace, màu đỏ khi < 10 giây
   - Hiển thị số quân đã ăn

4. GAME ACTION BAR (dưới cùng):
   - Nút: Ra ngoài | Cầu hòa | Xin thua | Bật tiếng | Tắt nhạc
   - Style: icon + text nhỏ, nền tối #3A2010

5. CHAT PANEL (collapsible):
   - Ô nhập text + nút Gửi
   - Grid 2x4 câu chat nhanh, style nút nâu
   - Row emoji biểu cảm cuộn ngang
   - Animate slide-up từ dưới

6. MOVE ANIMATION:
   - Quân cờ di chuyển: slide animation 200ms ease-in-out
   - Ăn quân: fade-out quân bị ăn + particle effect nhỏ
   - Chiếu tướng: glow đỏ xung quanh quân Tướng

7. GAME RESULT OVERLAY:
   - Modal full-screen mờ
   - "Bạn Thắng! 🏆" hoặc "Bạn Thua..." với animation confetti / falling pieces
   - Hiển thị: +/- ELO, thời gian ván, nút "Chơi lại" / "Về trang chủ"

Output: chess_board.dart, chess_piece.dart, player_info_panel.dart, 
        game_action_bar.dart, chat_panel.dart, game_screen.dart, game_result_overlay.dart
```

---

## PROMPT 03 — Màn hình Chờ Ghép Ván (Matchmaking)

```
Tạo màn hình chờ ghép đối thủ:

1. MATCHMAKING SCREEN:
   - Background: ink-wash art toàn màn hình (giống Cờ Ziga)
   - Center: hiệu ứng ripple tròn animate (như radar) màu vàng đồng
   - Text "Đang tìm đối thủ..." với font calligraphy, animate fade
   - Đồng hồ đếm số giây đã chờ
   - Nút "Hủy" ở dưới, style nâu mờ

2. FOUND MATCH PANEL (animate slide-up):
   - Hai avatar đối diện nhau với VS ở giữa
   - Tên + ELO của cả hai người chơi
   - Thanh loading "Chuẩn bị..." 3 giây rồi tự chuyển vào ván

3. ELO INFO CHIP:
   - Hiển thị ELO hiện tại của bản thân
   - Tooltip giải thích cấp bậc hiện tại

Output: matchmaking_screen.dart, found_match_panel.dart
```

---

## PROMPT 04 — Tab Học Cờ (Learning Hub)

```
Tạo màn hình hub học cờ với layout:

1. HEADER:
   - Tiêu đề "Học Cờ" + tagline "Nâng cao trình độ mỗi ngày"
   - Progress bar: "Nhiệm vụ học hôm nay: 2/3 hoàn thành"

2. SECTION GRID — 2 cột:
   a) Card "Khóa Học Vỡ Lòng" — icon sách, màu xanh lá
   b) Card "Bài Tập Tàn Cục" — icon cờ vua kiếm, màu đỏ son
   c) Card "Kỳ Phổ & Phục Bàn" — icon cuộn giấy, màu vàng
   d) Card "AI Tư Vấn" — icon robot, badge "VIP", màu tím
   e) Card "Khai Cuộc Đại Sư" — icon bản đồ, màu cam
   f) Card "Chụp Nhận Diện Cờ" — icon camera, badge "HOT"
   
   - Mỗi card: icon lớn + tên + số bài tập / mô tả ngắn
   - Card VIP: overlay mờ + icon khóa nếu chưa VIP

3. DAILY CHALLENGE BANNER:
   - Banner nổi bật: "Tàn Cục Thách Đấu Hôm Nay — 488 kỳ thủ đã thử"
   - Countdown đến khi đổi thách đấu
   - Nút "Thử Ngay" màu đỏ son

4. RECENT ACTIVITY:
   - List 3 bài tập gần đây với kết quả (✓ Đúng / ✗ Sai)

Output: learning_hub_screen.dart, learning_card.dart, daily_challenge_banner.dart
```

---

## PROMPT 05 — Màn hình Bài Tập Tàn Cục (Puzzle Screen)

```
Tạo puzzle screen (tàn cục luyện tập):

1. PUZZLE BOARD:
   - Sử dụng lại ChessBoard widget từ game screen
   - Mode: interactive (người dùng đi nước)
   - Chỉ hiện quân theo thế cờ bài tập (không phải đủ quân)

2. PUZZLE INFO PANEL (phía trên):
   - "Bài tập #1247 — Chiếu hết trong 3 nước"
   - Độ khó: ★★★☆☆
   - Tag: [Tàn cục] [Xe Pháo phối hợp]

3. FEEDBACK SYSTEM:
   - Nước đúng: flash xanh lá + âm "đúng rồi!"
   - Nước sai: shake animation + flash đỏ + âm "sai rồi!"
   - Hoàn thành: confetti + EXP animation +50 exp

4. HINT BUTTON:
   - Nút "Gợi ý" — highlight nước tốt nhất, trừ 1 lần gợi ý/ngày
   - Counter "Còn X gợi ý hôm nay"

5. NAVIGATION:
   - Nút "< Bài trước" và "Bài tiếp >"
   - Progress: "Bài 5/20 trong bộ Xe-Pháo"

Output: puzzle_screen.dart, puzzle_info_panel.dart, puzzle_feedback.dart
```

---

## PROMPT 06 — Tab Cá Nhân & Hồ Sơ

```
Tạo màn hình hồ sơ cá nhân:

1. PROFILE HEADER:
   - Avatar lớn (80px) với khung avatar theo rank
   - Tên + ID (#A91886313 style)
   - Badge cấp bậc: icon + text (vd: "Kỳ Sĩ ⭐⭐")
   - Hàng currency: 🪙 2278 | 💎 1000
   - Nút Chỉnh sửa (icon bút)

2. STATS GRID (2x2):
   - ELO Cờ Tướng: số + sparkline mini chart
   - ELO Cờ Úp
   - Tổng ván đã chơi
   - Tỷ lệ thắng %

3. WIN/LOSS BAR:
   - Thanh ngang: Thắng (xanh) | Hòa (vàng) | Thua (đỏ)
   - Số cụ thể bên dưới

4. ACHIEVEMENT SECTION:
   - Grid 4 cột, huy chương đã đạt màu sắc, chưa đạt mờ xám
   - "Xem tất cả" link

5. MENU LIST:
   - Hội Viên VIP (badge màu vàng)
   - Thống kê chi tiết
   - Huy chương
   - Trang phục cá nhân
   - Cài đặt
   - Trợ giúp & Phản hồi
   - Giới thiệu bạn bè
   - Phiên bản: V1.0.0

Output: profile_screen.dart, stats_grid.dart, achievement_grid.dart, profile_menu.dart
```

---

## PROMPT 07 — Màn hình Cộng Đồng

```
Tạo community hub screen:

1. COMMUNITY TAB LAYOUT:
   - AppBar với tên "Cộng Đồng Cờ Tướng"
   - ListView cuộn với các section:

2. FEED SECTION (dạng card):
   - Card "Tàn Cục Thách Đấu": thumbnail bàn cờ + tiêu đề + "X người đã thử"
   - Card "Ván Đấu Nổi Bật": 2 avatar VS nhau + ELO + nút "Xem"
   - Card "Tin tức": thumbnail + tiêu đề + thời gian đăng

3. QUICK ACCESS ROW:
   - Icon grid ngang: Bạn Bè | Bảng XH | Kỳ Xã | Giải Đấu | Livestream

4. LEADERBOARD PREVIEW:
   - Top 3 người chơi có avatar lớn + ELO
   - Link "Xem đầy đủ bảng xếp hạng"

5. NEARBY PLAYERS (khám phá kỳ thủ gần):
   - "Kỳ thủ gần bạn" — horizontal scroll, avatar + tên + ELO
   - Nút "Kết bạn" nhỏ

Output: community_screen.dart, community_feed_card.dart, leaderboard_preview.dart
```

---

## PROMPT 08 — Design System & Theme

```
Tạo design system hoàn chỉnh cho CChess:

1. FILE: lib/theme/app_colors.dart
   - Định nghĩa tất cả màu sắc dưới dạng static const

2. FILE: lib/theme/app_text_styles.dart
   - Định nghĩa tất cả TextStyle: display, headline, title, body, caption, button

3. FILE: lib/theme/app_theme.dart
   - ThemeData đầy đủ cho Material 3
   - Custom ColorScheme từ app colors
   - InputDecoration theme (khung input kiểu cổ điển)
   - ElevatedButton theme (nâu vàng, border radius 24)
   - Card theme

4. FILE: lib/widgets/common/
   - CChessButton (primary, secondary, outline variants)
   - CChessCard (với shadow và border radius)
   - CChessAvatar (tròn, có border color theo rank)
   - CChessRankBadge (icon + text cấp bậc)
   - CChessCurrencyDisplay (icon + số tiền)
   - CChessProgressBar (thanh tiến trình kiểu cổ điển)
   - CChessDialog (modal kiểu giấy cuộn)
   - LoadingOverlay (brush stroke animation)

5. CONSTANTS:
   - Spacing: 4, 8, 12, 16, 20, 24, 32, 48
   - Border radius constants
   - Piece types và ký hiệu Hán tự mapping

Chú ý: Tất cả component phải hỗ trợ cả màu sáng và tối (dark mode).

Output: toàn bộ thư mục lib/theme/ và lib/widgets/common/
```

---

## PROMPT 09 — Animations & Micro-interactions

```
Tạo hệ thống animation cho CChess:

1. CHESS PIECE MOVEMENT:
   - Class: PieceMoveAnimation
   - Curve: Curves.easeInOut, duration: 200ms
   - Di chuyển theo đường thẳng từ ô nguồn đến ô đích
   - Piece ở Z-index cao nhất trong lúc di chuyển

2. CAPTURE ANIMATION:
   - Quân bị ăn: scale 0 trong 150ms + fade out
   - Particle effect: 6–8 hạt nhỏ tỏa ra

3. CHECK (Chiếu tướng):
   - Quân Tướng: pulse glow đỏ, repeat 3 lần
   - Âm thanh: "chiếu!"

4. BOARD FLIP ANIMATION (đổi góc nhìn):
   - Rotate 180° animation, duration 400ms

5. RANK UP CELEBRATION:
   - Full-screen overlay
   - Badge mới zoom-in
   - Gold particle rain
   - Text "Thăng hạng! Kỳ Tướng 🎉"

6. SCROLL-BASED ANIMATIONS:
   - Home feed cards: fade-in slide-up khi scroll vào viewport

7. BUTTON PRESS:
   - Scale 0.95x on press, bounce back

Output: lib/animations/ (chess_animations.dart, celebration_animations.dart, ui_animations.dart)
```

---

## LƯU Ý CHO AI KHI IMPLEMENT UI:

1. **Responsive**: Thiết kế chính cho màn hình 360–420px width
2. **SafeArea**: Luôn bọc trong SafeArea
3. **Keyboard**: Dùng SingleChildScrollView khi có input để tránh overflow
4. **Image**: Dùng asset PNG cho quân cờ (nếu có) hoặc vẽ bằng CustomPainter
5. **Performance**: Dùng const constructor, tránh rebuild không cần thiết
6. **Localization**: Chuẩn bị sẵn arb file dù app hiện tại chỉ tiếng Việt
7. **Testing**: Mỗi screen cần có widget test cơ bản
