class PikafishTransportException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const PikafishTransportException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'PikafishTransportException($code): $message';
}

abstract class PikafishTransport {
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration timeout,
  });

  void close() {}
}
