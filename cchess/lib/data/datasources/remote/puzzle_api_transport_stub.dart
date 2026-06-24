import 'puzzle_api_transport.dart';

PuzzleApiTransport createDefaultPuzzleApiTransport() =>
    const UnsupportedPuzzleApiTransport();

/// Fallback used on platforms without `dart:io` (e.g. Flutter web). It always
/// reports a network error so [RemotePuzzleSource] callers fall back to the
/// local/cached catalog instead of crashing.
class UnsupportedPuzzleApiTransport implements PuzzleApiTransport {
  const UnsupportedPuzzleApiTransport();

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) {
    throw _unsupported();
  }

  @override
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    Map<String, String> headers = const {},
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    throw _unsupported();
  }

  PuzzleApiException _unsupported() => const PuzzleApiException(
        code: 'unsupported-platform',
        message: 'Puzzle REST transport is not available on this platform',
      );

  @override
  void close() {}
}
