import '../../models/opening.dart';

/// Curated catalog of well-known Xiangqi openings.
///
/// All move sequences are UCI strings starting from the standard initial
/// position. Legality is verified by [opening_seed_test.dart] which replays
/// every line through the engine.
const List<Opening> kOpenings = [
  // ─── 1. Trung Pháo (Central Cannon) vs Bình Phong Mã (Screen Horses) ───
  Opening(
    id: 'op_trung_phao_binh_phong_ma',
    nameVi: 'Trung Pháo Đối Bình Phong Mã',
    nameHan: '中炮对屏风马',
    tagline: 'Khai cuộc cổ điển bậc nhất',
    descriptionVi:
        'Đỏ đưa Pháo về trung lộ tấn công Tốt 5 đối phương, đen phòng thủ '
        'bằng cách đưa cả hai Mã ra "che chắn" cho Tướng. Đây là thế khai '
        'cuộc phổ biến nhất ở Việt Nam và Trung Quốc.',
    mainLine: [
      'b2e2', // 1. Red: Pháo 2 bình 5 (中炮)
      'h9g7', // 1...Black: Mã 8 tiến 7 (start of 屏风马)
      'b0c2', // 2. Red: Mã 2 tiến 3
      'b9c7', // 2...Black: Mã 2 tiến 3 (screen horses complete)
      'h2g2', // 3. Red: Pháo 8 bình 7 (hậu pháo)
      'h7i7', // 3...Black: Pháo 8 bình 9
    ],
    keyIdeasVi: [
      'Đỏ giành tiên thủ bằng cách đe doạ Tốt trung lộ ngay nước đầu.',
      'Đen dùng "bình phong" hai Mã để bảo vệ Tướng và hỗ trợ lẫn nhau.',
      'Tiếp theo Đỏ thường khai Xe (xa) để mở mặt trận tấn công cánh phải.',
      'Trận đấu thường đi vào trung cuộc đầy biến hoá quanh hai bên Mã.',
    ],
    difficulty: 2,
    popularity: 5,
  ),

  // ─── 2. Phi Tượng Cuộc (Flying Elephant) ───
  Opening(
    id: 'op_phi_tuong',
    nameVi: 'Phi Tượng Cuộc',
    nameHan: '飞相局',
    tagline: 'Chậm rãi, vững chắc',
    descriptionVi:
        'Đỏ mở đầu bằng cách "bay Tượng" lên trung lộ, ưu tiên phòng thủ '
        'thay vì tấn công sớm. Một lựa chọn an toàn cho người chơi thiên về '
        'thế thủ.',
    mainLine: [
      'c0e2', // 1. Red: Tượng 3 tiến 5 (Phi Tượng)
      'h9g7', // 1...Black: Mã 8 tiến 7
      'b0c2', // 2. Red: Mã 2 tiến 3
      'b9c7', // 2...Black: Mã 2 tiến 3
      'h0g2', // 3. Red: Mã 8 tiến 7
      'h7i7', // 3...Black: Pháo 8 bình 9 (xếp Pháo về cánh)
    ],
    keyIdeasVi: [
      'Tượng lên trung lộ kết nối hai cánh, giảm thiểu sai sót sớm.',
      'Đỏ chấp nhận nhường tiên thủ để chuẩn bị thế trận chắc chắn.',
      'Đen thường lùi Pháo sang cánh để chuẩn bị đôi Xe.',
      'Phù hợp với người chơi thích phòng thủ và trận đấu dài.',
    ],
    difficulty: 2,
    popularity: 4,
  ),

  // ─── 3. Khởi Mã Cuộc (Horse Opening) ───
  Opening(
    id: 'op_khoi_ma',
    nameVi: 'Khởi Mã Cuộc',
    nameHan: '起马局',
    tagline: 'Linh hoạt, đa hướng phát triển',
    descriptionVi:
        'Đỏ mở đầu bằng nước Mã tiến — chưa định hình tấn công trung lộ hay '
        'hai cánh. Khai cuộc rất linh hoạt, có thể chuyển sang nhiều thế '
        'trận khác nhau ở trung cuộc.',
    mainLine: [
      'b0c2', // 1. Red: Mã 2 tiến 3 (Khởi mã)
      'h9g7', // 1...Black: Mã 8 tiến 7
      'h0g2', // 2. Red: Mã 8 tiến 7
      'b9c7', // 2...Black: Mã 2 tiến 3
      'c0e2', // 3. Red: Tượng 3 tiến 5 (chuyển sang Phi Tượng)
      'c9e7', // 3...Black: Tượng 7 tiến 5 (đối xứng)
    ],
    keyIdeasVi: [
      'Mã phát triển trước giúp Đỏ giữ nhiều lựa chọn về kế hoạch tấn công.',
      'Đỏ có thể chuyển sang Phi Tượng hoặc Trung Pháo về sau.',
      'Đen thường đáp lại đối xứng, tạo thế trận cân bằng.',
      'Khai cuộc này rèn cho người chơi cảm giác về timing và linh hoạt.',
    ],
    difficulty: 3,
    popularity: 3,
  ),

  // ─── 4. Tiến Binh Cuộc (Pawn Opening) ───
  Opening(
    id: 'op_tien_binh',
    nameVi: 'Tiến Binh Cuộc',
    nameHan: '仙人指路',
    tagline: 'Thử thăm dò — "Tiên Nhân Chỉ Lộ"',
    descriptionVi:
        'Đỏ tiến Tốt trung lộ ngay nước đầu để chiếm điểm chiến lược ngoài '
        'sông. Khai cuộc này còn gọi là "Tiên Nhân Chỉ Lộ" — chậm rãi, '
        'thăm dò ý đồ của đối phương trước khi tung quân chính.',
    mainLine: [
      'e3e4', // 1. Red: Tốt 5 tiến 1
      'e6e5', // 1...Black: Tốt 5 tiến 1
      'b0c2', // 2. Red: Mã 2 tiến 3
      'b9c7', // 2...Black: Mã 2 tiến 3
      'h2e2', // 3. Red: Pháo 8 bình 5 (chuyển trung pháo từ cánh phải)
      'h7e7', // 3...Black: Pháo 8 bình 5 (đối pháo phản công)
    ],
    keyIdeasVi: [
      'Tốt trung lộ tiến để khống chế điểm chiến lược ô (4,4).',
      'Đỏ giữ kín ý đồ — Pháo và Mã chưa lộ vị trí.',
      'Khi đối phương đáp đối xứng, Đỏ thường chuyển sang Trung Pháo.',
      'Thích hợp khi muốn tránh các biến hoá lý thuyết phức tạp.',
    ],
    difficulty: 3,
    popularity: 2,
  ),

  // ─── 5. Đối Pháo (Cannon-vs-Cannon / 顺手炮) ───
  Opening(
    id: 'op_doi_phao',
    nameVi: 'Thuận Tay Pháo',
    nameHan: '顺手炮',
    tagline: 'Cả hai bên đều dùng Trung Pháo',
    descriptionVi:
        'Cả Đỏ và Đen đều đặt Pháo trung lộ ngay đầu ván. Đây là khai cuộc '
        'đối xứng, dẫn đến những trận đấu sôi nổi với hàng loạt va chạm '
        'ngay trung lộ.',
    mainLine: [
      'b2e2', // 1. Red: Pháo 2 bình 5
      'h7e7', // 1...Black: Pháo 8 bình 5 (đối pháo)
      'b0c2', // 2. Red: Mã 2 tiến 3
      'h9g7', // 2...Black: Mã 8 tiến 7
      'h0g2', // 3. Red: Mã 8 tiến 7
      'b9c7', // 3...Black: Mã 2 tiến 3
    ],
    keyIdeasVi: [
      'Hai Pháo đối diện sẵn sàng đổi để mở mặt trận.',
      'Bên nào ra Mã / Xe nhanh hơn thường giành lợi thế thế trận.',
      'Tốt 5 hai bên bị áp lực — phải cân nhắc khi đẩy lên.',
      'Thường dẫn tới trung cuộc đầy chiến thuật, ít thế trận yên tĩnh.',
    ],
    difficulty: 3,
    popularity: 4,
  ),
];
