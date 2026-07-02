/// Platform-conditional entry point for offline Pikafish.
///
/// On platforms with `dart:io` (Android/desktop) this resolves to the real
/// implementation that spawns the bundled Pikafish binary as a UCI child
/// process; on web it resolves to a stub that reports the feature as
/// unsupported. Callers (providers, settings UI, router) interact with the
/// same surface regardless of platform:
///
///   * [pikafishPlatformSupported] — can this platform run it at all;
///   * [createPikafishInstaller]   — NNUE download/verify/delete manager;
///   * [createPikafishLocalEngine] — the [MoveEngine], or null if unsupported;
///   * [pikafishOfflineReady]      — quick probe: binary + NNUE both present;
///   * [isStrongDevice]            — capability gate (cores/RAM) so weak
///     phones aren't asked to grind engine searches.
library;

export 'pikafish_support_stub.dart'
    if (dart.library.io) 'pikafish_support_io.dart';
