import '../../models/chess_puzzle.dart';

/// Built-in starter puzzles. Each FEN + solution pair has been hand-checked
/// against the engine; the [puzzle_seed_test.dart] test verifies the
/// solution moves are legal and (where claimed) deliver checkmate.
///
/// More puzzles will be loaded from JSON in a future sprint — keeping the
/// seed in code for MVP avoids one more asset registration step.
const List<ChessPuzzle> seedPuzzles = [
  ChessPuzzle(
    id: 'p001',
    titleVi: 'Bắt Pháo Hớ',
    descriptionVi:
        'Pháo đen lang thang qua sông không có quân yểm trợ. Đưa Xe sang '
        'ăn pháo — và sau khi ăn, Xe còn chiếu Tướng đối phương.',
    // Red R at (4,0), Black c at (4,4), generals on col 4. Cannon at (4,4)
    // blocks the file so generals don't face, and the cannon attacks Red
    // king only via empty squares (no capture possible without a carriage).
    fen: '4k4/9/9/9/R3c4/9/9/9/9/4K4 w - - 0 1',
    solution: ['a5e5'],
    tags: ['Tàn cục', 'Tactic'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p002',
    titleVi: 'Bắt Mã Lẻ',
    descriptionVi: 'Mã đen lạc đường — đưa Xe sang ăn ngay.',
    fen: '3k5/9/9/9/n3R4/9/9/9/9/4K4 w - - 0 1',
    solution: ['e5a5'],
    tags: ['Tàn cục', 'Tactic'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p003',
    titleVi: 'Chiếu Hết Trong 1 Nước',
    descriptionVi:
        'Tướng đen bị kẹt trong cung. Xe đỏ chỉ cần một nước là kết liễu.',
    fen: '4k4/3a1a3/4P4/9/9/9/9/9/9/4K3R w - - 0 1',
    solution: ['i0i9'],
    tags: ['Chiếu hết', 'Xe'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p004',
    titleVi: 'Bắt Xe Vô Phòng',
    descriptionVi:
        'Xe đen lao sâu sang trận địa đỏ mà không có ai hỗ trợ. Tịch thu nó!',
    // Red R(6,4), Black r(3,4) on the same file with no piece between.
    // Generals on different files (Black k at col 3).
    fen: '3k5/9/9/4r4/9/9/4R4/9/9/4K4 w - - 0 1',
    solution: ['e3e6'],
    tags: ['Tàn cục', 'Tactic'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p005',
    titleVi: 'Khai Môn Xe',
    descriptionVi:
        'Đẩy tốt sang một bên để mở đường cho Xe — phát hiện chiếu Tướng đối '
        'phương từ xa.',
    // Red P(2,4) blocks Red R(4,4) from attacking Black K(0,4). Moving the
    // soldier sideways reveals the chariot's line of attack.
    fen: '4k4/9/4P4/9/4R4/9/9/9/9/4K4 w - - 0 1',
    solution: ['e7d7'],
    tags: ['Khai môn', 'Chiến thuật'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p006',
    titleVi: 'Bắt Pháo Bên Sông',
    descriptionVi:
        'Pháo đen liều mạng vượt sông tấn công nhưng bị Xe đỏ đoạt trước.',
    // Red R(4,8), Black c(4,6), Red P(4,4) blocks the kings on col 4.
    fen: '4k4/9/9/9/4P1c1R/9/9/9/9/4K4 w - - 0 1',
    solution: ['i5g5'],
    tags: ['Tàn cục', 'Xe Pháo'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p007',
    titleVi: 'Bắt Mã Mất Phòng',
    descriptionVi: 'Mã đen bị dồn vào góc bàn. Xe đỏ ra tay nhanh gọn.',
    // Red R(7,8), Black n(7,1) on row 7. Generals not facing (different files).
    fen: '3k5/9/9/9/9/9/9/1n6R/9/4K4 w - - 0 1',
    solution: ['i2b2'],
    tags: ['Tàn cục', 'Tactic'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p008',
    titleVi: 'Xe Bắt Mã Dọc',
    descriptionVi:
        'Mã đen đứng cùng cột với Xe đỏ và không có quân nào chắn giữa.',
    fen: '3k5/9/9/1n7/9/9/1R7/9/9/4K4 w - - 0 1',
    solution: ['b3b6'],
    tags: ['Tàn cục', 'Xe', 'Tactic'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p009',
    titleVi: 'Pháo Ăn Xe Có Ngòi',
    descriptionVi:
        'Đếm đúng một quân ngòi giữa Pháo đỏ và Xe đen rồi mới ăn quân.',
    fen: '3k5/9/r8/9/P8/9/9/C8/9/4K4 w - - 0 1',
    solution: ['a2a7'],
    tags: ['Tàn cục', 'Pháo', 'Xe Pháo'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p010',
    titleVi: 'Mã Nhảy Bắt Pháo',
    descriptionVi: 'Chân Mã thông thoáng, Mã đỏ có thể nhảy lên bắt Pháo đen.',
    fen: '3k5/9/9/9/9/3c5/9/2N6/9/4K4 w - - 0 1',
    solution: ['c2d4'],
    tags: ['Tàn cục', 'Mã'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p011',
    titleVi: 'Tốt Qua Sông Bắt Mã',
    descriptionVi: 'Tốt đỏ đã qua sông nên được đi ngang để ăn quân bên cạnh.',
    fen: '3k5/9/9/9/4Pn3/9/9/9/9/4K4 w - - 0 1',
    solution: ['e5f5'],
    tags: ['Tàn cục', 'Tốt'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p012',
    titleVi: 'Xe Ép Tuyến Ngang',
    descriptionVi:
        'Xe đỏ đang chiếm hàng ngang mở. Hãy lấy quân Pháo đen treo bên cánh.',
    fen: '3k5/9/9/9/9/2R4c1/9/9/9/4K4 w - - 0 1',
    solution: ['c4h4'],
    tags: ['Tàn cục', 'Xe', 'Tactic'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p013',
    titleVi: 'Xe Bắt Tốt Xa',
    descriptionVi: 'Đường dọc đã sạch, Xe đỏ có thể tiến sâu để thu Tốt đen.',
    fen: '3k5/9/7p1/9/9/9/9/7R1/9/4K4 w - - 0 1',
    solution: ['h2h7'],
    tags: ['Tàn cục', 'Xe', 'Tốt'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p014',
    titleVi: 'Pháo Ven Biên',
    descriptionVi:
        'Một quân Tốt làm ngòi trên cột biên, mở đường cho Pháo bắt Mã.',
    fen: '3k5/9/9/8n/9/8P/9/9/8C/4K4 w - - 0 1',
    solution: ['i1i6'],
    tags: ['Tàn cục', 'Pháo', 'Mã'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p015',
    titleVi: 'Mã Lệch Vai Bắt Xe',
    descriptionVi: 'Chân Mã không bị chặn, Mã đỏ nhảy chéo để bắt Xe đen.',
    fen: '3k5/9/9/9/9/9/3r5/5N3/9/4K4 w - - 0 1',
    solution: ['f2d3'],
    tags: ['Tàn cục', 'Mã', 'Tactic'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p016',
    titleVi: 'Xe Bắt Pháo Ven Biên',
    descriptionVi:
        'Pháo đen đứng lẻ trên cùng cột. Xe đỏ đi thẳng lên để bắt gọn.',
    fen: '3k5/9/8c/9/9/9/8R/9/9/4K4 w - - 0 1',
    solution: ['i3i7'],
    tags: ['Tàn cục', 'Xe', 'Pháo'],
    difficulty: 1,
  ),
  ChessPuzzle(
    id: 'p017',
    titleVi: 'Pháo Qua Ngòi Bắt Tượng',
    descriptionVi:
        'Tốt đỏ nằm đúng giữa đường, giúp Pháo ăn Tượng đen ở phía trên.',
    fen: '3k5/9/9/1b7/9/1P7/9/1C7/9/4K4 w - - 0 1',
    solution: ['b2b6'],
    tags: ['Tàn cục', 'Pháo', 'Tượng'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p018',
    titleVi: 'Mã Bắt Pháo Sâu',
    descriptionVi: 'Mã đỏ có đường nhảy sạch lên f4 để bắt Pháo đen.',
    fen: '3k5/9/9/9/9/5c3/9/4N4/9/4K4 w - - 0 1',
    solution: ['e2f4'],
    tags: ['Tàn cục', 'Mã', 'Pháo'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p019',
    titleVi: 'Xe Đen Ăn Pháo Hở',
    descriptionVi: 'Bên đen đi trước: Xe đen có đường dọc sạch để bắt Pháo đỏ.',
    fen: '3k5/9/9/r8/9/9/C8/9/9/4K4 b - - 0 1',
    solution: ['a6a3'],
    tags: ['Tàn cục', 'Bên đen', 'Xe'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p020',
    titleVi: 'Pháo Đen Qua Ngòi',
    descriptionVi: 'Bên đen dùng quân ngòi trên cột i để Pháo bắt Xe đỏ.',
    fen: '3k5/9/8c/9/9/8p/9/8R/9/4K4 b - - 0 1',
    solution: ['i7i2'],
    tags: ['Tàn cục', 'Bên đen', 'Pháo'],
    difficulty: 3,
  ),
  ChessPuzzle(
    id: 'p021',
    titleVi: 'Mã Đen Bắt Xe',
    descriptionVi:
        'Bên đen đi trước, chân Mã không bị chặn và có thể bắt Xe đỏ.',
    fen: '3k5/9/7n1/5R3/9/9/9/9/9/4K4 b - - 0 1',
    solution: ['h7f6'],
    tags: ['Tàn cục', 'Bên đen', 'Mã'],
    difficulty: 3,
  ),
  ChessPuzzle(
    id: 'p022',
    titleVi: 'Pháo Trung Lộ Có Ngòi',
    descriptionVi: 'Pháo đỏ dùng Tốt làm ngòi để bắt Xe đen ở nửa bàn trên.',
    fen: '5k3/9/3r5/9/3P5/9/9/3C5/9/4K4 w - - 0 1',
    solution: ['d2d7'],
    tags: ['Tàn cục', 'Pháo', 'Xe Pháo'],
    difficulty: 3,
  ),
  ChessPuzzle(
    id: 'p023',
    titleVi: 'Mã Đỏ Bắt Xe Cánh Trái',
    descriptionVi: 'Mã đỏ ở b2 có chân Mã trống, đủ nhảy lên bắt Xe đen.',
    fen: '3k5/9/9/9/9/2r6/9/1N7/9/4K4 w - - 0 1',
    solution: ['b2c4'],
    tags: ['Tàn cục', 'Mã', 'Xe'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p024',
    titleVi: 'Tốt Sang Ngang Bắt Pháo',
    descriptionVi:
        'Tốt đỏ đã qua sông, vì vậy nước sang trái bắt Pháo là hợp lệ.',
    fen: '3k5/9/9/9/4cP3/9/9/9/9/4K4 w - - 0 1',
    solution: ['f5e5'],
    tags: ['Tàn cục', 'Tốt', 'Pháo'],
    difficulty: 2,
  ),
  ChessPuzzle(
    id: 'p025',
    titleVi: 'Xe Quét Ngang Bắt Mã',
    descriptionVi: 'Xe đỏ đứng ở hàng mở, chỉ cần đi ngang là lấy được Mã đen.',
    fen: '3k5/9/9/9/9/R3n4/9/9/9/4K4 w - - 0 1',
    solution: ['a4e4'],
    tags: ['Tàn cục', 'Xe', 'Mã'],
    difficulty: 1,
  ),
];
