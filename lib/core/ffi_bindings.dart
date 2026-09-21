import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// FFI bindings to native `libsensio_ppg_core`
class SensioNativeBindings {
  SensioNativeBindings._(DynamicLibrary lib)
      : _getVersion = lib.lookupFunction<
          Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>(
          'sensio_get_version',
        ),
        _processFile = lib.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Double),
          Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, double)>(
          'sensio_process_file',
        ),
        _freeString = lib.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>(
          'sensio_free_string',
        );

  final Pointer<Utf8> Function() _getVersion;
  final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, double) _processFile;
  final void Function(Pointer<Utf8>) _freeString;

  static SensioNativeBindings? tryLoad() {
    try {
      if (Platform.isAndroid) {
        final lib = DynamicLibrary.open('libsensio_ppg_core.so');
        return SensioNativeBindings._(lib);
      }
      if (Platform.isIOS) {
        return SensioNativeBindings._(DynamicLibrary.process());
      }
      if (Platform.isMacOS) {
        final bundleFrameworksPath =
            '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libsensio_ppg_core.dylib';
        final paths = [
          bundleFrameworksPath,
          'bin/libsensio_ppg_core.dylib',
          'libsensio_ppg_core.dylib',
          'rust/target/release/libsensio_ppg_core.dylib',
          '../rust/target/release/libsensio_ppg_core.dylib',
          'macos/Frameworks/libsensio_ppg_core.dylib',
        ];
        for (final p in paths) {
          if (File(p).existsSync()) {
            return SensioNativeBindings._(DynamicLibrary.open(p));
          }
        }
        return SensioNativeBindings._(DynamicLibrary.process());
      }
      if (Platform.isLinux) {
        final paths = [
          'libsensio_ppg_core.so',
          'rust/target/release/libsensio_ppg_core.so',
          '../rust/target/release/libsensio_ppg_core.so',
        ];
        for (final p in paths) {
          if (File(p).existsSync()) {
            return SensioNativeBindings._(DynamicLibrary.open(p));
          }
        }
        return SensioNativeBindings._(DynamicLibrary.open('libsensio_ppg_core.so'));
      }
      if (Platform.isWindows) {
        final paths = [
          'sensio_ppg_core.dll',
          'rust/target/release/sensio_ppg_core.dll',
          '../rust/target/release/sensio_ppg_core.dll',
        ];
        for (final p in paths) {
          if (File(p).existsSync()) {
            return SensioNativeBindings._(DynamicLibrary.open(p));
          }
        }
        return SensioNativeBindings._(DynamicLibrary.open('sensio_ppg_core.dll'));
      }
    } catch (_) {
      // Failed to load library
    }
    return null;
  }

  String getVersion() {
    final ptr = _getVersion();
    if (ptr == nullptr) return 'unknown';
    return ptr.toDartString();
  }

  String processFile(String ppgPath, {String? sigmotPath, double sampleRate = 50.0}) {
    final ppgPtr = ppgPath.toNativeUtf8();
    final sigmotPtr = sigmotPath != null ? sigmotPath.toNativeUtf8() : nullptr;

    try {
      final resPtr = _processFile(ppgPtr, sigmotPtr, sampleRate);
      if (resPtr == nullptr) {
        throw Exception('Native process_file returned null pointer');
      }
      try {
        return resPtr.toDartString();
      } finally {
        _freeString(resPtr);
      }
    } finally {
      calloc.free(ppgPtr);
      if (sigmotPtr != nullptr) {
        calloc.free(sigmotPtr);
      }
    }
  }
}
