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
    descriptionVi:
        'Mã đen bị dồn vào góc bàn. Xe đỏ ra tay nhanh gọn.',
    // Red R(7,8), Black n(7,1) on row 7. Generals not facing (different files).
    fen: '3k5/9/9/9/9/9/9/1n6R/9/4K4 w - - 0 1',
    solution: ['i2b2'],
    tags: ['Tàn cục', 'Tactic'],
    difficulty: 1,
  ),
];
