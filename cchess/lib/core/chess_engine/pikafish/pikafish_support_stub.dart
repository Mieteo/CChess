import 'pikafish_installer.dart';
import 'pikafish_local_engine.dart';

/// Web build: no child processes, offline Pikafish is unsupported.
bool get pikafishPlatformSupported => false;

Future<bool> pikafishOfflineReady() async => false;

Future<bool> isStrongDevice() async => false;

PikafishLocalEngine? createPikafishLocalEngine() => null;

PikafishInstaller createPikafishInstaller({
  Future<String?> Function()? tokenProvider,
}) =>
    const _StubPikafishInstaller();

class _StubPikafishInstaller implements PikafishInstaller {
  const _StubPikafishInstaller();

  @override
  Future<PikafishInstallStatus> status() async =>
      PikafishInstallStatus.unsupported;

  @override
  Stream<double> download() =>
      Stream.error(PikafishUnavailableException('Platform not supported'));

  @override
  Future<void> delete() async {}
}
