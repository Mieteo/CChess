import 'remote_pikafish_transport.dart';
import 'remote_pikafish_transport_stub.dart'
    if (dart.library.io) 'remote_pikafish_transport_io.dart'
    as platform;

PikafishTransport createDefaultPikafishTransport() {
  return platform.createDefaultPikafishTransport();
}
