/// Stub ElephantEye binding for platforms without `dart:io` (i.e. web).
///
/// The native engine ships only as an Android `.so`, so on these platforms the
/// engine is always unsupported and every search defers to the pure-Dart
/// minimax fallback.
class EleeyeFfi {
  EleeyeFfi._();

  /// Whether the native engine could exist on this platform. Always false here.
  static bool get isSupported => false;

  /// No-op on unsupported platforms — always returns null so callers fall back.
  static String? bestMoveUci(String fen, int depth) => null;
}
