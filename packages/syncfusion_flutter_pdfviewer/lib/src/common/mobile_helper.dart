import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

/// Checks whether focus node of pdf page view has primary focus.
bool hasPrimaryFocus = false;

/// Prevents default menu.
void preventDefaultMenu() {}

/// Enabled default menu.
void enableDefaultMenu() {}

/// Gets platform type.
String getPlatformType() {
  return Platform.operatingSystem;
}

/// To check whether pdfium is loaded or not on Android platform
bool isPdfiumLoaded() {
  if (!Platform.isAndroid) {
    return false;
  }

  try {
    final ffi.DynamicLibrary library = ffi.DynamicLibrary.open('libpdfium.so');
    if (library.handle != ffi.nullptr) {
      library.close();
    }
    return true;
  } catch (e) {
    return false;
  }
}

// Pixel storage stays native until ImmutableBuffer has copied it. These calls
// run only for the OHOS handle protocol; older binaries use the byte protocol.
final ffi.DynamicLibrary _pdfPixelLibrary = ffi.DynamicLibrary.open(
  'libpdf_renderer.so',
);
final ffi.Pointer<ffi.Uint8> Function(int, int) _getPdfPixels = _pdfPixelLibrary
    .lookupFunction<
      ffi.Pointer<ffi.Uint8> Function(ffi.Int64, ffi.Int64),
      ffi.Pointer<ffi.Uint8> Function(int, int)
    >('ZotpaperPdfGetPixels');
final void Function(int) _releasePdfPixels = _pdfPixelLibrary
    .lookupFunction<ffi.Void Function(ffi.Int64), void Function(int)>(
      'ZotpaperPdfReleasePixels',
    );

Uint8List nativePdfPixels(int handle, int length) {
  final pointer = _getPdfPixels(handle, length);
  if (pointer == ffi.nullptr) {
    throw StateError('PDF pixel buffer is unavailable');
  }
  // No finalizer: the owner releases after the engine copy or stale discard.
  return pointer.asTypedList(length);
}

void releaseNativePdfPixels(int handle) => _releasePdfPixels(handle);
