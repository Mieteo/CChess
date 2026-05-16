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
];
