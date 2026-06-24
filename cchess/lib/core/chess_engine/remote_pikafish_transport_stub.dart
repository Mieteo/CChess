import 'remote_pikafish_transport.dart';

PikafishTransport createDefaultPikafishTransport() {
  return const UnsupportedPikafishTransport();
}

class UnsupportedPikafishTransport implements PikafishTransport {
  const UnsupportedPikafishTransport();

  @override
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) {
    throw const PikafishTransportException(
      code: 'unsupported-platform',
      message: 'Remote Pikafish transport is not available on this platform',
    );
  }

  @override
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
  }) {
    throw const PikafishTransportException(
      code: 'unsupported-platform',
      message: 'Remote Pikafish transport is not available on this platform',
    );
  }

  @override
  void close() {}
}
