#ifndef ZOTPAPER_PDF_RASTER_PIXELS_H_
#define ZOTPAPER_PDF_RASTER_PIXELS_H_

#include <algorithm>
#include <cstdint>
#include <limits>
#include <vector>

#include "fpdfview.h"

// PDFium borrows the request's result storage. Destroy the bitmap before the
// vector is moved, resized or released; FPDFBitmap_Destroy does not free it.
inline FPDF_BITMAP CreatePdfRasterBitmap(int width, int height,
                                        std::vector<uint8_t>& pixels) {
  if (width <= 0 || height <= 0 ||
      width > std::numeric_limits<int>::max() / 4 ||
      static_cast<size_t>(height) >
          std::numeric_limits<size_t>::max() / (static_cast<size_t>(width) * 4)) {
    return nullptr;
  }
  const int stride = width * 4;
  pixels.resize(static_cast<size_t>(stride) * height);
  return FPDFBitmap_CreateEx(width, height, FPDFBitmap_BGRA, pixels.data(), stride);
}

// Preserve the existing RGBA channel/FFI contract without a second full raster.
inline void ConvertPdfRasterToRgba(std::vector<uint8_t>& pixels) {
  for (size_t offset = 0; offset + 3 < pixels.size(); offset += 4) {
    std::swap(pixels[offset], pixels[offset + 2]);
  }
}

#endif  // ZOTPAPER_PDF_RASTER_PIXELS_H_
