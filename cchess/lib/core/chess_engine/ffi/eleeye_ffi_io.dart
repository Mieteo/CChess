import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

// ── Native function signatures (see android/app/src/main/cpp/eleeye_ffi.cpp) ──
//   void eleeye_init();
//   int  eleeye_best_move(const char* fen, int depth, char* out, int out_len);

typedef _InitC = ffi.Void Function();
typedef _InitDart = void Function();

typedef _BestMoveC = ffi.Int32 Function(
    ffi.Pointer<Utf8>, ffi.Int32, ffi.Pointer<Utf8>, ffi.Int32);
typedef _BestMoveDart = int Function(
    ffi.Pointer<Utf8>, int, ffi.Pointer<Utf8>, int);

/// Real FFI binding to the native ElephantEye Xiangqi engine.
///
/// The library (`libeleeye_engine.so`) is bundled only in the Android build, so
/// [isSupported] is true on Android and false elsewhere. Loading is lazy and
/// fault-tolerant: any failure (missing symbol, load error) leaves the engine
/// reported as unavailable so callers cleanly fall back to the Dart engine.
///
/// Note: the static handles below are per-isolate. Because searches run inside
/// `compute` (a fresh isolate per call), each isolate loads the library on first
/// use; the OS keeps a single copy in memory and the C++ side guards its global
/// init, so re-loading is cheap and safe.
class EleeyeFfi {
  EleeyeFfi._();

  static ffi.DynamicLibrary? _lib;
  static _BestMoveDart? _bestMove;
  static bool _triedLoad = false;

  /// Native engine is only built for Android.
  static bool get isSupported => Platform.isAndroid;

  /// Idempotently loads the library and resolves symbols. Returns true once the
  /// engine is ready to search; false if the platform is unsupported or load
  /// failed (the failure is remembered so we don't retry every call).
  static bool _ensureLoaded() {
    if (_lib != null) return true;
    if (_triedLoad) return false;
    _triedLoad = true;
    if (!isSupported) return false;
    try {
      final lib = ffi.DynamicLibrary.open('libeleeye_engine.so');
      final init = lib.lookupFunction<_InitC, _InitDart>('eleeye_init');
      _bestMove =
          lib.lookupFunction<_BestMoveC, _BestMoveDart>('eleeye_best_move');
      init();
      _lib = lib;
      return true;
    } catch (_) {
      _bestMove = null;
      return false;
    }
  }

  /// Runs a depth-bounded native search for [fen] and returns the best move in
  /// UCI notation (e.g. "e0e1"), or null if the engine is unavailable or the
  /// position has no legal move.
  static String? bestMoveUci(String fen, int depth) {
    if (!_ensureLoaded()) return null;
    final fenPtr = fen.toNativeUtf8();
    final outPtr = malloc.allocate<Utf8>(8); // "e0e1\0" fits in 8 bytes
    try {
      final rc = _bestMove!(fenPtr, depth, outPtr, 8);
      if (rc != 0) return null;
      return outPtr.toDartString();
    } catch (_) {
      return null;
    } finally {
      malloc.free(fenPtr);
      malloc.free(outPtr);
    }
  }
}
