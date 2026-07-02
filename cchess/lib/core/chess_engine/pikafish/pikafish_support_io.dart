import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants/app_constants.dart';
import 'pikafish_installer.dart';
import 'pikafish_local_engine.dart';
import 'uci_client.dart';

/// Method channel served by MainActivity.kt: native library dir (where the
/// pikafish "lib" executables are extracted) and total device RAM.
const MethodChannel _channel = MethodChannel('cchess/pikafish');

/// Minimum plausible NNUE size — catches truncated downloads and HTML error
/// pages saved as .nnue.
const int _minNnueBytes = 40 * 1024 * 1024;

/// Android runs the bundled binary; desktop platforms are supported for
/// development via the PIKAFISH_PATH environment variable. iOS cannot spawn
/// child processes, so it stays on the remote/ElephantEye path.
bool get pikafishPlatformSupported =>
    Platform.isAndroid ||
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS;

String? _cachedBinaryPath;

Future<String?> _findBinary() async {
  if (_cachedBinaryPath != null && File(_cachedBinaryPath!).existsSync()) {
    return _cachedBinaryPath;
  }
  String? found;
  if (Platform.isAndroid) {
    String? dir;
    try {
      dir = await _channel.invokeMethod<String>('nativeLibraryDir');
    } catch (_) {
      return null;
    }
    if (dir == null) return null;
    final dotprod = File('$dir/libpikafish_dotprod.so');
    final base = File('$dir/libpikafish.so');
    if (dotprod.existsSync() && _cpuSupportsDotprod()) {
      found = dotprod.path;
    } else if (base.existsSync()) {
      found = base.path;
    }
  } else {
    // Desktop/dev: point PIKAFISH_PATH at a pikafish executable.
    final env = Platform.environment['PIKAFISH_PATH'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      found = env;
    }
  }
  _cachedBinaryPath = found;
  return found;
}

/// ARMv8.2 dot-product build is ~30% faster for NNUE; detect via cpuinfo.
bool _cpuSupportsDotprod() {
  try {
    return File('/proc/cpuinfo').readAsStringSync().contains('asimddp');
  } catch (_) {
    return false;
  }
}

Future<File> _nnueFile() async {
  // Desktop/dev override so tests can point at an existing network file.
  final env = Platform.environment['PIKAFISH_NNUE_PATH'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return File(env);
  }
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}pikafish.nnue');
}

Future<String?> _installedNnuePath() async {
  final file = await _nnueFile();
  if (!file.existsSync()) return null;
  if (file.lengthSync() < _minNnueBytes) return null;
  return file.path;
}

/// Half the cores, capped: enough to search fast, low enough to not cook the
/// phone or starve the UI thread.
int _threadsForDevice() =>
    (Platform.numberOfProcessors ~/ 2).clamp(1, 4);

Future<PikafishRuntime?> _resolveRuntime() async {
  if (!pikafishPlatformSupported) return null;
  final binary = await _findBinary();
  if (binary == null) return null;
  final nnue = await _installedNnuePath();
  if (nnue == null) return null;
  return PikafishRuntime(
    binaryPath: binary,
    nnuePath: nnue,
    threads: _threadsForDevice(),
  );
}

/// Quick availability probe for the router: true when a request to the
/// offline engine would actually be served (binary present + NNUE installed).
Future<bool> pikafishOfflineReady() async => (await _resolveRuntime()) != null;

/// Devices worth running offline searches on: plenty of cores and (when we
/// can read it) enough RAM that a 64MB hash table + 50MB network won't hurt.
Future<bool> isStrongDevice() async {
  final cores = Platform.numberOfProcessors;
  if (!pikafishPlatformSupported || cores < 6) return false;
  if (!Platform.isAndroid) return true;
  try {
    final mem = await _channel.invokeMethod<int>('totalMemBytes');
    if (mem != null) return mem >= 5 * 1024 * 1024 * 1024;
  } catch (_) {}
  return cores >= 8;
}

/// The offline engine, or null when this platform can't run one. The child
/// process starts lazily on first use.
PikafishLocalEngine? createPikafishLocalEngine() {
  if (!pikafishPlatformSupported) return null;
  return PikafishLocalEngine(
    resolveRuntime: _resolveRuntime,
    startTransport: (runtime) => ProcessUciTransport.start(runtime.binaryPath),
  );
}

PikafishInstaller createPikafishInstaller({
  Future<String?> Function()? tokenProvider,
}) =>
    _IoPikafishInstaller(tokenProvider: tokenProvider);

/// [UciTransport] over a real child process.
class ProcessUciTransport implements UciTransport {
  ProcessUciTransport._(this._process) {
    lines = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    // Engines log noise to stderr; drain it so the pipe can't back up.
    _process.stderr.drain<void>().catchError((_) {});
  }

  static Future<ProcessUciTransport> start(String executable) async {
    final process = await Process.start(executable, const []);
    return ProcessUciTransport._(process);
  }

  final Process _process;

  @override
  late final Stream<String> lines;

  @override
  void send(String line) {
    try {
      _process.stdin.writeln(line);
    } catch (_) {
      // Broken pipe after engine death — the exitCode path reports it.
    }
  }

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> dispose() async {
    _process.kill();
    try {
      await _process.stdin.close();
    } catch (_) {}
  }
}

class _IoPikafishInstaller implements PikafishInstaller {
  _IoPikafishInstaller({this.tokenProvider});

  /// Firebase ID token for the engine-service download route.
  final Future<String?> Function()? tokenProvider;

  @override
  Future<PikafishInstallStatus> status() async {
    if (!pikafishPlatformSupported) return PikafishInstallStatus.unsupported;
    final binary = await _findBinary();
    final nnuePath = await _installedNnuePath();
    return PikafishInstallStatus(
      platformSupported: true,
      binaryAvailable: binary != null,
      nnueInstalled: nnuePath != null,
      nnueSizeBytes: nnuePath == null ? null : File(nnuePath).lengthSync(),
    );
  }

  @override
  Stream<double> download() async* {
    if (!pikafishPlatformSupported) {
      throw PikafishUnavailableException('Platform not supported');
    }
    final target = await _nnueFile();
    final part = File('${target.path}.part');
    final client = HttpClient();
    IOSink? sink;
    try {
      final request =
          await client.getUrl(Uri.parse(AppConstants.pikafishNnueUrl));
      final token = await tokenProvider?.call();
      if (token != null && token.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $token');
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'NNUE download failed: HTTP ${response.statusCode}',
          uri: request.uri,
        );
      }

      final total = response.contentLength; // -1 when unknown
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      sink = part.openWrite();
      var received = 0;
      yield 0.0;
      await for (final chunk in response) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) yield (received / total).clamp(0.0, 0.99);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hasher.close();

      if (received < _minNnueBytes) {
        throw const FormatException('Downloaded NNUE is implausibly small');
      }
      final expected = AppConstants.pikafishNnueSha256;
      if (expected.isNotEmpty &&
          digestSink.value.toString() != expected.toLowerCase()) {
        throw const FormatException('NNUE checksum mismatch');
      }
      if (target.existsSync()) target.deleteSync();
      part.renameSync(target.path);
      yield 1.0;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> delete() async {
    final file = await _nnueFile();
    if (file.existsSync()) await file.delete();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
