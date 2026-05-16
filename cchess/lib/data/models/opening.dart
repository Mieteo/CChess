import 'package:equatable/equatable.dart';

import '../../core/chess_engine/chess_engine.dart';

/// A classical Xiangqi opening with its main line and strategic key ideas.
///
/// For MVP each opening carries a single main line — variation trees can be
/// layered on later by extending [variations].
class Opening extends Equatable {
  /// Stable id used in routes.
  final String id;

  /// Vietnamese name shown in the UI (e.g. "Trung Pháo Đối Bình Phong Mã").
  final String nameVi;

  /// Han / Pinyin label printed underneath for cultural flavor.
  final String nameHan;

  /// Short marketing tagline.
  final String tagline;

  /// Longer description (1-3 sentences) shown in the detail screen.
  final String descriptionVi;

  /// Sequence of moves (UCI notation) starting from the standard initial
  /// position. Odd indexes are Black, even indexes are Red.
  final List<String> mainLine;

  /// Strategic bullets explaining the ideas behind the opening.
  final List<String> keyIdeasVi;

  /// 1 (easy / classical) .. 5 (advanced / theoretical).
  final int difficulty;

  /// 1 (rare) .. 5 (extremely common in tournament practice).
  final int popularity;

  const Opening({
    required this.id,
    required this.nameVi,
    required this.nameHan,
    required this.tagline,
    required this.descriptionVi,
    required this.mainLine,
    required this.keyIdeasVi,
    required this.difficulty,
    required this.popularity,
  });

  /// Whose move it is after the first [ply] moves have been played from the
  /// initial position. Always returns Red at ply 0.
  PieceColor turnAtPly(int ply) =>
      ply.isEven ? PieceColor.red : PieceColor.black;

  /// Total number of moves in the main line.
  int get moveCount => mainLine.length;

  @override
  List<Object?> get props => [
        id,
        nameVi,
        nameHan,
        tagline,
        descriptionVi,
        mainLine,
        keyIdeasVi,
        difficulty,
        popularity,
      ];
}
