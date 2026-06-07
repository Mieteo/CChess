import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'remote_pikafish_transport.dart';

PikafishTransport createDefaultPikafishTransport() {
  return IoPikafishTransport();
}

class IoPikafishTransport implements PikafishTransport {
  IoPikafishTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    final request = await _client.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.write(jsonEncode(body));

    final response = await request.close().timeout(timeout);
    final text = await utf8.decoder.bind(response).join().timeout(timeout);
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const PikafishTransportException(
        code: 'invalid-response',
        message: 'Engine response must be a JSON object',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PikafishTransportException(
        statusCode: response.statusCode,
        code: decoded['code'] as String? ?? 'http-error',
        message: decoded['message'] as String? ?? 'Engine request failed',
      );
    }
    return decoded;
  }

  @override
  void close() => _client.close(force: true);
}
