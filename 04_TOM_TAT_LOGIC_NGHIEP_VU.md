# Tóm tắt logic nghiệp vụ sản phẩm CChess

## 1. Mục đích tài liệu

Tài liệu này mô tả **sản phẩm đang phục vụ người dùng như thế nào**: người dùng vào app để làm gì, có những tính năng nào, được khuyến khích quay lại ra sao, và trải nghiệm tổng thể được thiết kế theo hướng nào.

Tài liệu này **không mô tả logic kỹ thuật hoặc cấu trúc code**. Phần tổng hợp được rút ra từ:

- Bộ tài liệu định hướng sản phẩm: `01_FEATURE_SPECIFICATION.md`, `02_PROMPT_UI_UX.md`, `03_PROMPT_FEATURES_ROADMAP.md`
- Các màn hình, luồng và dữ liệu nghiệp vụ đang có trong ứng dụng Flutter hiện tại
- Tài liệu thiết kế giao diện trong thư mục `stitch_document_to_ui_designer`

Lưu ý tên gọi:

- Tài liệu dự án gọi sản phẩm là **CChess**
- Giao diện hiện tại hiển thị thương hiệu **Kỳ Vương Việt**

## 2. Bức tranh sản phẩm

CChess là một ứng dụng cờ tướng tiếng Việt, hướng đến ba nhu cầu chính:

1. **Chơi cờ**
2. **Học và luyện cờ**
3. **Theo dõi tiến bộ cá nhân**

Định hướng dài hạn của sản phẩm rộng hơn: thi đấu online, bảng xếp hạng, bạn bè, câu lạc bộ, giải đấu, livestream, cửa hàng vật phẩm, VIP và các công cụ AI. Tuy nhiên, **bản hiện tại đang vận hành như một MVP thiên về trải nghiệm offline/local**, tập trung vào:

- Chơi 2 người trên cùng máy
- Chơi với bot AI nhiều cấp độ
- Giải bài tập tàn cục
- Học các thế khai cuộc
- Lưu kỳ phổ, phục bàn và xem phân tích AI
- Theo dõi hồ sơ, nhiệm vụ hằng ngày và huy chương

## 3. Trải nghiệm tổng thể của người dùng

### 3.1. Lần đầu mở ứng dụng

Người dùng đi qua màn hình giới thiệu rồi tạo hồ sơ ban đầu:

- Nhập tên hiển thị
- Chọn khu vực tại Việt Nam
- Sau khi hoàn tất, app ghi nhớ hồ sơ và đưa người dùng vào trang chính

Ứng dụng tạo sẵn một hồ sơ cơ bản cho người mới:

- ELO khởi điểm
- Số dư tiền game ban đầu
- Thống kê ván đấu bằng 0
- Trạng thái VIP mặc định là chưa kích hoạt

### 3.2. Điều hướng chính

Ứng dụng dùng 5 khu vực lớn:

1. **Trang Chủ**: vào nhanh các hoạt động chính
2. **Học Tập**: bài tập, khai cuộc, nội dung học
3. **Đối Đầu**: chọn chế độ thi đấu
4. **Cộng Đồng**: khám phá bảng xếp hạng, kỳ thủ, giải đấu
5. **Hồ Sơ**: thành tích cá nhân, kỳ phổ, nhiệm vụ, cài đặt

### 3.3. Phong cách trải nghiệm

Trải nghiệm được định hình theo phong cách:

- Tiếng Việt là ngôn ngữ chính
- Mỹ thuật Á Đông, tông gỗ, vàng đồng, đỏ son
- Tập trung vào cảm giác cổ điển nhưng vẫn có gamification hiện đại
- Nhiều điểm nhấn quay lại hằng ngày: nhiệm vụ, phần thưởng, thử thách, huy chương

## 4. Các nhóm tính năng nghiệp vụ đang có

### 4.1. Chơi cờ

#### a. Đấu tại chỗ

Người dùng có thể mở một ván cờ cho 2 người chơi trên cùng thiết bị.

Trong ván có:

- Bàn cờ đầy đủ
- Hiển thị lượt đi
- Đồng hồ cho hai bên
- Số quân đã ăn
- Lật góc nhìn bàn cờ
- Hoàn tác nước đi
- Xin hòa
- Xin thua
- Rời ván

Khi ván kết thúc, hệ thống:

- Lưu lại kỳ phổ
- Ghi nhận vào lịch sử
- Cập nhật tổng số ván đã chơi
- Cập nhật tiến độ nhiệm vụ hằng ngày

#### b. Đấu với bot AI

Người dùng có thể chơi với bot offline theo 5 cấp độ:

- Tập Sự
- Sơ Cấp
- Trung Cấp
- Cao Thủ
- Đại Sư

Mỗi cấp có cảm nhận sức mạnh khác nhau, kèm mô tả và ELO ước lượng. Trải nghiệm này phục vụ:

- Người mới muốn luyện an toàn
- Người chơi muốn nâng dần độ khó
- Người dùng không cần mạng vẫn có thể chơi

Khi chơi với bot:

- Người dùng luôn thấy trạng thái "bot đang suy nghĩ"
- Ván đấu vẫn được lưu vào lịch sử
- Kết quả thắng/thua/hòa được cộng vào hồ sơ cá nhân

#### c. Các chế độ đang được giới thiệu nhưng chưa hoạt động đầy đủ

Giao diện đã có chỗ cho:

- Xếp hạng online
- Cờ Úp
- Mời bạn đấu
- Giải đấu

Hiện tại các mục này mới là định hướng hoặc placeholder giao diện, chưa phải luồng nghiệp vụ hoàn chỉnh.

### 4.2. Học và luyện cờ

#### a. Bài tập tàn cục

Người dùng có danh sách bài tập dựng sẵn, mỗi bài có:

- Tên bài
- Độ khó
- Số nước cần giải
- Nhãn chủ đề
- Trạng thái đã hoàn thành hay chưa

Trong quá trình làm bài:

- Người dùng tự đi nước
- Hệ thống phản hồi đúng/sai ngay lập tức
- Nếu đi sai 3 lần, app hiển thị đáp án
- Có cơ chế gợi ý
- Hoàn thành bài cho cảm giác nhận thưởng và được ghi nhận tiến độ

Hiện tại người dùng có thể:

- Xem tổng số bài đã hoàn thành
- Làm lại bài
- Chuyển sang bài tiếp theo
- Dùng bài tập để hoàn thành nhiệm vụ hằng ngày

#### b. Khai cuộc đại sư

Ứng dụng có thư viện khai cuộc mẫu, cho phép người dùng:

- Xem danh sách khai cuộc phổ biến
- Hiểu mức độ phổ biến, độ khó và số nước chính
- Xem từng nước đi trên bàn cờ
- Kéo thanh tiến trình hoặc nhảy theo từng nước
- Đọc phần mô tả chiến lược và các ý đồ trọng tâm

Đây là phần học theo dạng “xem, hiểu, ghi nhớ”, khác với bài tập tàn cục là “tự giải”.

#### c. Trung tâm học tập

Màn hình Học Tập đang gom nhiều hướng phát triển:

- Khóa học vỡ lòng
- Bài tập tàn cục
- Kỳ phổ và phục bàn
- AI tư vấn
- Khai cuộc đại sư
- Chụp nhận diện bàn cờ

Trong bản hiện tại:

- `Bài Tập Tàn Cục` và `Khai Cuộc Đại Sư` là hai luồng có thể dùng thực sự
- Các mục còn lại chủ yếu là điểm đặt cho các tính năng tương lai

### 4.3. Kỳ phổ, phục bàn và học lại từ chính ván cờ của mình

Sau khi một ván cờ hoàn tất, người dùng có thể vào **Kỳ Phổ Của Tôi** để:

- Xem danh sách các ván đã chơi
- Phân biệt ván đấu tại chỗ và ván đấu với bot
- Xem kết quả, thời lượng, số nước đi, thời điểm kết thúc
- Mở lại một ván để phục bàn

Trong màn hình phục bàn, người dùng có thể:

- Đi tới đầu hoặc cuối ván
- Xem từng nước một
- Tự động phát lại
- Đổi tốc độ phát
- Chọn trực tiếp nước cần xem trên timeline

Ngoài ra, app hiện đã có **AI Coach trong phục bàn**:

- Đánh giá chất lượng từng nước
- Phân loại nước đi: hay nhất, xuất sắc, tốt, thiếu chính xác, sai lầm, sai lầm lớn
- Đưa ra gợi ý nước thay thế
- Tính độ chính xác tương đối cho hai bên
- Đếm số sai lầm lớn trong ván

Về mặt nghiệp vụ, đây là cầu nối quan trọng giữa:

- **Chơi**
- **Tự đánh giá**
- **Học lại từ lỗi của bản thân**

### 4.4. Hồ sơ và tiến bộ cá nhân

Người dùng có một trang hồ sơ gồm:

- Tên hiển thị
- ID
- Khu vực
- Cấp bậc theo ELO
- Số dư tiền game
- Tổng số ván
- Tỷ lệ thắng
- Biểu diễn thắng / hòa / thua

Người dùng cũng có thể:

- Sửa tên hiển thị
- Đổi khu vực
- Xem ngày tham gia
- Truy cập kỳ phổ, huy chương, nhiệm vụ, cài đặt

Ứng dụng có hệ thống **cấp bậc theo ELO** để phản ánh trình độ:

- Tập Sự
- Kỳ Sinh
- Kỳ Sĩ
- Kỳ Tướng
- Kỳ Soái
- Kỳ Vương
- Kỳ Thánh

Trong bản hiện tại:

- Hệ cấp bậc đã xuất hiện trên hồ sơ và giao diện
- Nhưng ELO chưa thực sự biến động qua các ván local/bot vì chưa có luồng đấu xếp hạng online hoàn chỉnh

### 4.5. Nhiệm vụ hằng ngày và phần thưởng

Ứng dụng có bộ nhiệm vụ hằng ngày, hiện gồm:

- Điểm danh
- Chơi 1 ván
- Thắng 1 ván
- Giải 2 bài tập

Người dùng có thể:

- Theo dõi tiến độ từng nhiệm vụ
- Nhận thưởng khi hoàn thành
- Nhận tiền game và một số nhiệm vụ có thêm ngọc

Vai trò nghiệp vụ của hệ thống này:

- Tạo lý do quay lại mỗi ngày
- Dẫn người dùng trải qua cả chơi lẫn học
- Gắn việc sử dụng sản phẩm với phần thưởng cụ thể

Màn hình Trang Chủ cũng có khối “phần thưởng hôm nay”, nhưng luồng điểm danh trực tiếp tại đó hiện vẫn mang tính trình bày nhiều hơn là một flow hoàn chỉnh.

### 4.6. Huy chương và gamification

Ứng dụng có hệ thống huy chương chia theo nhóm:

- Tham gia
- Chiến thắng
- Học cờ
- Cột mốc
- Xã hội

Người dùng được mở khóa huy chương theo:

- Số ván đã chơi
- Số trận thắng
- Chuỗi thắng
- Số bài tập đã giải
- Mốc ELO
- Chuỗi đăng nhập

Khi mở khóa thành tích mới:

- Ứng dụng thông báo ngay trong trải nghiệm
- Người dùng có thể vào màn hình huy chương để xem tiến độ tổng thể và chi tiết từng huy chương

Đây là lớp động lực dài hạn, bổ sung cho nhiệm vụ hằng ngày là động lực ngắn hạn.

### 4.7. Cài đặt và cá nhân hóa trải nghiệm

Người dùng có thể cấu hình:

- Âm hiệu
- Nhạc nền
- Rung khi đi quân
- Hiển thị chấm gợi ý nước đi
- Mặc định lật bàn cờ
- Giới hạn số lượt gợi ý
- Giới hạn thời gian chơi mỗi ngày

Ứng dụng cũng có các mục:

- Chính sách dữ liệu
- Điều khoản sử dụng
- Phiên bản ứng dụng

Về trải nghiệm, đây là phần cho thấy sản phẩm không chỉ tập trung vào ván cờ mà còn quan tâm đến:

- Cách người dùng muốn chơi
- Mức độ hỗ trợ khi luyện tập
- Quản lý thời gian sử dụng lành mạnh

### 4.8. Cộng đồng

Màn hình Cộng Đồng hiện đã có lớp trải nghiệm khám phá:

- Top kỳ thủ tuần này
- Tàn cục thách đấu
- Kỳ thủ gần bạn
- Lối tắt tới bạn bè, bảng xếp hạng, kỳ xã, giải đấu và livestream

Tuy nhiên ở bản hiện tại, đây chủ yếu là **màn hình giới thiệu định hướng cộng đồng**, chưa phải là hệ thống xã hội vận hành thực sự.

## 5. Các quy tắc nghiệp vụ nổi bật đang thể hiện trong sản phẩm

### 5.1. Hồ sơ người dùng

- Mỗi người dùng có hồ sơ riêng được tạo khi bắt đầu
- Hồ sơ lưu tên, khu vực, số dư, thống kê, ELO, trạng thái VIP và lịch sử hoạt động
- Người dùng có thể chỉnh sửa tên và khu vực sau onboarding

### 5.2. Kết quả ván cờ

- Ván hoàn thành được lưu vào kỳ phổ
- Ván với bot cập nhật thắng / thua / hòa cho hồ sơ
- Ván local chỉ tăng tổng số ván, không quy đổi thành kết quả cá nhân cho một người chơi cụ thể
- Kết quả ván kéo theo cập nhật nhiệm vụ và kiểm tra huy chương

### 5.3. Nhiệm vụ ngày

- Nhiệm vụ được tính theo ngày hiện tại
- Sang ngày mới thì tiến độ cũ được làm mới
- Phần thưởng chỉ nhận được khi đạt đủ điều kiện và chưa nhận trước đó

### 5.4. Bài tập

- Mỗi bài có lời giải chính thức
- Nước đúng mới được chấp nhận để tiếp tục chuỗi lời giải
- Sau ba lần sai, app bật mí đáp án
- Tiến độ bài được lưu để người dùng thấy mình đã hoàn thành những gì

### 5.5. Huy chương

- Huy chương chỉ mở khi đạt ngưỡng mục tiêu
- Mỗi huy chương gắn với một loại tiến bộ cụ thể
- Hệ thống dùng cả mục tiêu ngắn hạn và dài hạn để giữ chân người dùng

### 5.6a. Đồng bộ local ↔ cloud (Sprint 8b)

- Splash khởi động → tự động đăng nhập anonymous nếu chưa có session → đọc `users/{uid}` trên cloud.
- Nếu cloud chưa có: tạo mới từ profile local. Các field nhạy cảm (ELO, coin, gem, ...) bị **rules ép về giá trị mặc định** — client không thể tự gán giá trị cao hơn.
- Nếu cloud đã có: pull **chỉ whitelist** (displayName, region, avatarUrl, onboardingCompleted, createdAt, lastActiveAt) xuống local, sensitive fields giữ nguyên local.
- Khi user sửa profile (rename, change region, complete onboarding): `ProfileController` lưu local rồi tự push whitelist lên cloud, fire-and-forget.
- Khi local lưu kỳ phổ (game_records): cũng tự push lên `users/{uid}/game_records/{gameId}` subcollection.
- Sensitive (ELO update sau ván ranked) chỉ server có quyền ghi qua Cloud Function `recordRankedGame` — đảm bảo chống gian lận.

### 5.6. Kỳ phổ và phân tích

- Mọi ván đã hoàn tất đều có thể được dựng lại từ đầu
- Người dùng có thể học từ ván cũ bằng cách xem lại từng nước và bật phân tích AI

## 6. Tính năng đang có, đang dang dở và định hướng tương lai

### 6.1. Đang dùng được trong bản hiện tại

- Onboarding và hồ sơ cá nhân
- **Đăng nhập ẩn danh tự động + liên kết Google (giữ uid)** — Sprint 8a
- **Đồng bộ hồ sơ và kỳ phổ lên cloud Firestore** — Sprint 8b
- Đấu tại chỗ
- Đấu với bot AI 5 cấp
- Danh sách bài tập tàn cục và màn hình giải bài
- Danh sách khai cuộc và màn hình học khai cuộc
- Lưu kỳ phổ, xem lịch sử và phục bàn
- AI Coach trong phục bàn
- Nhiệm vụ hằng ngày
- Huy chương
- Cài đặt cá nhân, có section Tài khoản (liên kết Google, đăng xuất)

### 6.2. Có mặt trong giao diện nhưng chưa thành flow hoàn chỉnh

- Cờ Úp
- Mời bạn
- Xếp hạng online
- Giải đấu
- VIP
- Trang phục cá nhân
- Trợ giúp / phản hồi
- Khóa học vỡ lòng
- AI tư vấn ở hub học tập
- Chụp nhận diện bàn cờ
- Phần lớn khu vực cộng đồng

### 6.3. Định hướng lớn trong tài liệu sản phẩm

- Đấu online có ELO
- Bạn bè, câu lạc bộ, bảng xếp hạng
- Xem cờ, livestream, tin tức, diễn đàn
- Cửa hàng, balo vật phẩm, mỹ phẩm, sự kiện
- VIP và monetization
- AI coach cá nhân hóa sâu hơn
- OCR nhận diện bàn cờ thật
- Các biến thể cờ khác và hệ sinh thái giải đấu

## 7. Hành trình người dùng tiêu biểu

### Hành trình 1: Người mới bắt đầu

1. Mở app
2. Tạo hồ sơ
3. Chọn bot Tập Sự hoặc Sơ Cấp
4. Chơi một ván
5. Vào bài tập tàn cục để luyện thêm
6. Nhận nhiệm vụ và huy chương đầu tiên

### Hành trình 2: Người muốn tiến bộ

1. Vào Học Tập
2. Giải bài tập tàn cục
3. Học một khai cuộc
4. Chơi với bot khó hơn
5. Mở kỳ phổ vừa chơi
6. Bật AI Coach để xem mình sai ở đâu

### Hành trình 3: Người dùng quay lại hằng ngày

1. Mở app
2. Kiểm tra nhiệm vụ hôm nay
3. Chơi ít nhất một ván
4. Giải thêm bài tập
5. Nhận thưởng
6. Theo dõi tiến độ huy chương và thống kê

## 8. Nhận định sản phẩm ở thời điểm hiện tại

Bản hiện tại đã hình thành một vòng lặp sản phẩm khá rõ:

1. **Chơi**
2. **Nhận phản hồi**
3. **Học thêm**
4. **Theo dõi tiến bộ**
5. **Quay lại để hoàn thành mục tiêu mới**

Điểm mạnh hiện tại:

- Đã có trải nghiệm người dùng mạch lạc cho người chơi offline
- Có sự kết nối tốt giữa chơi, học và tiến bộ cá nhân
- Có nền móng gamification đủ rõ để giữ chân người dùng
- AI Coach trong phục bàn là tính năng có giá trị thực tế, không chỉ trang trí

Điểm còn chưa hoàn chỉnh:

- Nhiều tính năng định hướng lớn vẫn mới ở mức placeholder
- Cộng đồng và online play chưa thực sự hoạt động
- Monetization / VIP mới có dấu vết, chưa thành sản phẩm hoàn chỉnh
- Một số khối giao diện trình bày nhiều hơn là nghiệp vụ đang chạy thật

## 9. Tóm tắt ngắn gọn

CChess hiện là một ứng dụng cờ tướng tiếng Việt tập trung vào **chơi offline, luyện tập, xem lại ván đấu và phát triển hồ sơ cá nhân**. Người dùng có thể bắt đầu nhanh, chơi với bot hoặc người bên cạnh, giải bài tập, học khai cuộc, xem lại ván cũ bằng phục bàn có AI phân tích, rồi tiếp tục quay lại nhờ nhiệm vụ ngày và hệ thống huy chương.

Tài liệu roadmap cho thấy sản phẩm được định hướng trở thành một hệ sinh thái cờ tướng đầy đủ hơn trong tương lai, nhưng **giá trị sử dụng thực tế ở bản hiện tại nằm ở vòng lặp “chơi - học - theo dõi tiến bộ”**.
