/// Thrown when a puzzle REST call fails (network, non-2xx, or malformed body).
/// Mirrors the backend error envelope `{ code, message }`.
class PuzzleApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const PuzzleApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// True for the cases where falling back to local/cache makes sense: the
  /// request never reached the server, timed out, or the platform can't do
  /// HTTP (web stub). 4xx/5xx responses keep their own [statusCode].
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'PuzzleApiException($code): $message';
}

/// Minimal JSON-over-HTTP transport used by [RemotePuzzleSource]. Kept as an
/// interface so tests can inject a fake and so the `dart:io` implementation
/// stays isolated from web builds (see the conditional import factory).
abstract class PuzzleApiTransport {
  /// GET [uri]; expects a JSON object response. Throws [PuzzleApiException].
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  });

  /// POST [body] as JSON to [uri]; expects a JSON object response.
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    Map<String, String> headers = const {},
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 10),
  });

  void close() {}
}
