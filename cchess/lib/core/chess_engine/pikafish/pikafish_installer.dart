/// Platform-neutral surface for installing/uninstalling the offline Pikafish
/// NNUE network. The real work happens in `pikafish_support_io.dart`; web
/// gets a stub that reports the feature as unsupported.
library;

/// Install state shown in Settings and used by the router availability probe.
class PikafishInstallStatus {
  /// This platform can spawn a UCI child process at all (Android + desktop).
  final bool platformSupported;

  /// The engine binary shipped with the app was found (e.g. libpikafish.so
  /// extracted for this ABI). False on unsupported CPUs.
  final bool binaryAvailable;

  /// The NNUE network file is downloaded and verified.
  final bool nnueInstalled;

  /// Size of the installed NNUE in bytes, when installed.
  final int? nnueSizeBytes;

  const PikafishInstallStatus({
    required this.platformSupported,
    required this.binaryAvailable,
    required this.nnueInstalled,
    this.nnueSizeBytes,
  });

  /// Offline engine can actually serve requests.
  bool get ready => platformSupported && binaryAvailable && nnueInstalled;

  static const unsupported = PikafishInstallStatus(
    platformSupported: false,
    binaryAvailable: false,
    nnueInstalled: false,
  );
}

/// Manages the on-device NNUE file (the ~50MB download that turns the bundled
/// binary into a working engine).
abstract class PikafishInstaller {
  Future<PikafishInstallStatus> status();

  /// Download + verify the NNUE. Emits progress in [0, 1]; completes when the
  /// file is installed, errors on network/checksum failure (partial files are
  /// cleaned up).
  Stream<double> download();

  /// Remove the installed NNUE (frees ~50MB; offline engine becomes
  /// unavailable until re-downloaded).
  Future<void> delete();
}
