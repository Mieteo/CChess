import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'puzzle_api_transport.dart';

PuzzleApiTransport createDefaultPuzzleApiTransport() => IoPuzzleApiTransport();

/// `dart:io` implementation backing native (mobile/desktop) builds. Web builds
/// get the stub via the conditional import in the factory.
class IoPuzzleApiTransport implements PuzzleApiTransport {
  IoPuzzleApiTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _send('GET', uri, headers: headers, body: null, timeout: timeout);
  }

  @override
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    Map<String, String> headers = const {},
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _send('POST', uri, headers: headers, body: body, timeout: timeout);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic>? body,
    required Duration timeout,
  }) async {
    try {
      final request = await _client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(timeout);
      final text =
          await utf8.decoder.bind(response).join().timeout(timeout);
      final decoded = text.isEmpty ? const <String, dynamic>{} : jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw PuzzleApiException(
          statusCode: response.statusCode,
          code: 'invalid-response',
          message: 'Puzzle API response must be a JSON object',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PuzzleApiException(
          statusCode: response.statusCode,
          code: decoded['code'] as String? ?? 'http-error',
          message: decoded['message'] as String? ?? 'Puzzle request failed',
        );
      }
      return decoded;
    } on PuzzleApiException {
      rethrow;
    } on TimeoutException {
      throw const PuzzleApiException(
        code: 'timeout',
        message: 'Puzzle request timed out',
      );
    } on SocketException catch (e) {
      throw PuzzleApiException(code: 'network', message: e.message);
    } on HttpException catch (e) {
      throw PuzzleApiException(code: 'network', message: e.message);
    } on FormatException catch (e) {
      throw PuzzleApiException(code: 'invalid-json', message: e.message);
    }
  }

  @override
  void close() => _client.close(force: true);
}
