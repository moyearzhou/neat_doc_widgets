#include <android/bitmap.h>
#include <jni.h>
#include <cerrno>
#include <cstdint>
#include <unistd.h>

extern "C" JNIEXPORT jboolean JNICALL
Java_com_syncfusion_flutter_pdfviewer_PdfBitmapPixels_writePixels(
    JNIEnv* env, jclass, jobject bitmap, jint descriptor) {
  AndroidBitmapInfo info{};
  if (descriptor < 0 || AndroidBitmap_getInfo(env, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS ||
      info.format != ANDROID_BITMAP_FORMAT_RGBA_8888 || info.width == 0 || info.height == 0 ||
      static_cast<uint64_t>(info.width) * 4 > info.stride) {
    return JNI_FALSE;
  }
  void* pixels = nullptr;
  if (AndroidBitmap_lockPixels(env, bitmap, &pixels) != ANDROID_BITMAP_RESULT_SUCCESS) {
    return JNI_FALSE;
  }
  // PdfRenderer owns this software bitmap on its serial worker. Borrow it only
  // during the write, and always unlock before Java recycles it. Preserve raw
  // RGBA/premultiplied bytes; omit row padding from Flutter's packed raster.
  bool success = pixels != nullptr;
  const bool packed = static_cast<uint64_t>(info.width) * 4 == info.stride;
  const uint32_t rows = packed ? 1 : info.height;
  for (uint32_t row = 0; success && row < rows; ++row) {
    const auto* source = static_cast<const uint8_t*>(pixels) + static_cast<size_t>(row) * info.stride;
    size_t remaining = static_cast<size_t>(info.width) * 4 * (packed ? info.height : 1);
    while (remaining > 0) {
      const ssize_t count = write(descriptor, source, remaining);
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0) {
        success = false;
        break;
      }
      source += count;
      remaining -= count;
    }
  }
  if (AndroidBitmap_unlockPixels(env, bitmap) != ANDROID_BITMAP_RESULT_SUCCESS) success = false;
  return success ? JNI_TRUE : JNI_FALSE;
}
