import 'puzzle_api_transport.dart';
import 'puzzle_api_transport_stub.dart'
    if (dart.library.io) 'puzzle_api_transport_io.dart' as platform;

/// Returns the `dart:io`-backed transport on native builds, or the web stub
/// when `dart:io` is unavailable.
PuzzleApiTransport createDefaultPuzzleApiTransport() =>
    platform.createDefaultPuzzleApiTransport();
