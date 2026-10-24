// Run against PDFium: clang++ -std=c++17 -I../src/main/cpp/include
// pdf_raster_pixels_test.cpp <path-to-pdfium-library> -o /tmp/pdf-raster-test
#include <cassert>
#include <cstring>
#include <iostream>

#include "../src/main/cpp/pdf_raster_pixels.h"
#include "fpdf_edit.h"

int main() {
  FPDF_InitLibrary();
  FPDF_DOCUMENT document = FPDF_CreateNewDocument();
  FPDF_PAGE page = FPDFPage_New(document, 0, 240, 320);
  for (int i = 0; i < 4; ++i) {
    FPDF_PAGEOBJECT rectangle = FPDFPageObj_CreateNewRect(
        15 + i * 35, 30 + i * 45, 90, 100);
    FPDFPageObj_SetFillColor(rectangle, 230 - i * 45, 30 + i * 50,
                            70 + i * 30, 100 + i * 40);
    FPDFPath_SetDrawMode(rectangle, FPDF_FILLMODE_WINDING, 0);
    FPDFPage_InsertObject(page, rectangle);
  }
  assert(FPDFPage_GenerateContent(page));

  for (int rotation = 0; rotation < 4; ++rotation) {
    const int width = 513;
    const int height = 709;
    FPDF_BITMAP original = FPDFBitmap_Create(width, height, 1);
    std::vector<uint8_t> pixels;
    FPDF_BITMAP direct = CreatePdfRasterBitmap(width, height, pixels);
    assert(original && direct);
    assert(FPDFBitmap_GetBuffer(direct) == pixels.data());
    assert(FPDFBitmap_GetStride(direct) == width * 4);
    for (FPDF_BITMAP bitmap : {original, direct}) {
      FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
      // Include a cropped/offset render, as used by viewport detail tiles.
      FPDF_RenderPageBitmap(bitmap, page, -31, -43, width + 101,
                            height + 123, rotation, FPDF_ANNOT | FPDF_LCD_TEXT);
    }
    const auto* source = static_cast<const uint8_t*>(FPDFBitmap_GetBuffer(original));
    const int stride = FPDFBitmap_GetStride(original);
    for (int y = 0; y < height; ++y) {
      assert(std::memcmp(source + y * stride, pixels.data() + y * width * 4,
                         width * 4) == 0);
    }
    std::vector<uint8_t> expected(pixels);
    for (size_t i = 0; i < expected.size(); i += 4) {
      std::swap(expected[i], expected[i + 2]);
    }
    FPDFBitmap_Destroy(original);
    FPDFBitmap_Destroy(direct);
    // Destroying PDFium's borrowed bitmap must leave result storage intact.
    ConvertPdfRasterToRgba(pixels);
    assert(pixels == expected);
    std::vector<uint8_t> ownedResult(std::move(pixels));
    assert(ownedResult == expected);
  }
  std::vector<uint8_t> invalid;
  assert(!CreatePdfRasterBitmap(0, 10, invalid));
  assert(!CreatePdfRasterBitmap(-1, 10, invalid));
  assert(!CreatePdfRasterBitmap(std::numeric_limits<int>::max(), 10, invalid));
  FPDF_ClosePage(page);
  FPDF_CloseDocument(document);
  FPDF_DestroyLibrary();
  std::cout << "PASS: direct BGRA storage, rotations/crops, RGBA parity and ownership\n";
}
