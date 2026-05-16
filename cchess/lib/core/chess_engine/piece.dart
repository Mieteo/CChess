import 'package:equatable/equatable.dart';

import '../constants/piece_constants.dart';

/// Immutable Xiangqi piece: a type + color pair.
class Piece extends Equatable {
  final PieceType type;
  final PieceColor color;

  const Piece(this.type, this.color);

  // Convenient factories.
  static const Piece redGeneral = Piece(PieceType.general, PieceColor.red);
  static const Piece redAdvisor = Piece(PieceType.advisor, PieceColor.red);
  static const Piece redElephant = Piece(PieceType.elephant, PieceColor.red);
  static const Piece redHorse = Piece(PieceType.horse, PieceColor.red);
  static const Piece redChariot = Piece(PieceType.chariot, PieceColor.red);
  static const Piece redCannon = Piece(PieceType.cannon, PieceColor.red);
  static const Piece redSoldier = Piece(PieceType.soldier, PieceColor.red);

  static const Piece blackGeneral = Piece(PieceType.general, PieceColor.black);
  static const Piece blackAdvisor = Piece(PieceType.advisor, PieceColor.black);
  static const Piece blackElephant = Piece(PieceType.elephant, PieceColor.black);
  static const Piece blackHorse = Piece(PieceType.horse, PieceColor.black);
  static const Piece blackChariot = Piece(PieceType.chariot, PieceColor.black);
  static const Piece blackCannon = Piece(PieceType.cannon, PieceColor.black);
  static const Piece blackSoldier = Piece(PieceType.soldier, PieceColor.black);

  bool get isRed => color == PieceColor.red;
  bool get isBlack => color == PieceColor.black;

  String get fenChar => type.fenLetter(color);
  String get hanChar => type.hanChar(color);

  @override
  String toString() => fenChar;

  @override
  List<Object?> get props => [type, color];
}
