import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows Data Protection API: encrypts data so only the current Windows
/// user on this PC can decrypt it. Used for the Google sign-in token.
class Dpapi {
  static bool get available => Platform.isWindows;

  static List<int> protect(List<int> data) => _run(data, protect: true);
  static List<int> unprotect(List<int> data) => _run(data, protect: false);

  static List<int> _run(List<int> data, {required bool protect}) {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final localFree = kernel32.lookupFunction<IntPtr Function(Pointer<Void>), int Function(Pointer<Void>)>('LocalFree');
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buf.asTypedList(data.length).setAll(0, data);
      input.ref.cbData = data.length;
      input.ref.pbData = buf;
      const uiForbidden = 0x1;
      final int ok;
      if (protect) {
        final f = crypt32.lookupFunction<_ProtectNative, _ProtectDart>('CryptProtectData');
        ok = f(input, nullptr, nullptr, nullptr, nullptr, uiForbidden, output);
      } else {
        final f = crypt32.lookupFunction<_UnprotectNative, _UnprotectDart>('CryptUnprotectData');
        ok = f(input, nullptr, nullptr, nullptr, nullptr, uiForbidden, output);
      }
      if (ok == 0) throw StateError('Windows could not ${protect ? 'protect' : 'read'} the saved sign-in.');
      final result = List<int>.of(output.ref.pbData.asTypedList(output.ref.cbData));
      localFree(output.ref.pbData.cast());
      return result;
    } finally {
      calloc.free(buf);
      calloc.free(input);
      calloc.free(output);
    }
  }
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _ProtectNative = Int32 Function(
    Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>);
typedef _ProtectDart = int Function(
    Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>);
typedef _UnprotectNative = Int32 Function(Pointer<_DataBlob>, Pointer<Pointer<Utf16>>, Pointer<_DataBlob>,
    Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>);
typedef _UnprotectDart = int Function(Pointer<_DataBlob>, Pointer<Pointer<Utf16>>, Pointer<_DataBlob>, Pointer<Void>,
    Pointer<Void>, int, Pointer<_DataBlob>);
