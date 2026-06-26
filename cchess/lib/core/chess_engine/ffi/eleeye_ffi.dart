/// Platform-conditional entry point for the native ElephantEye engine.
///
/// On platforms with `dart:io` (Android/iOS/desktop) this resolves to the real
/// FFI implementation; everywhere else (web) it resolves to a stub that simply
/// reports the engine as unsupported. Callers always interact with the same
/// [EleeyeFfi] surface regardless of platform.
library;

export 'eleeye_ffi_stub.dart' if (dart.library.io) 'eleeye_ffi_io.dart';
