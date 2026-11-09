// Configure this standalone CMake project with PDF_TEST_FIXTURE_DIR, then run
// ctest -C Release --output-on-failure. Uses real PDFs without tracking them.
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
#include "pdfviewer.h"

namespace fs = std::filesystem;
void Check(bool condition, const char* message)
{
  if (!condition) throw std::runtime_error(message);
}
std::vector<uint8_t> Render(FPDF_DOCUMENT document, int index)
{
  FPDF_PAGE page = FPDF_LoadPage(document, index);
  Check(page != nullptr, "page failed to load");
  const int width = 160, height = 220;
  FPDF_BITMAP bitmap = FPDFBitmap_Create(width, height, 0);
  Check(bitmap != nullptr, "bitmap allocation failed");
  FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xffffffff);
  FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0,
                        FPDF_LCD_TEXT | FPDF_REVERSE_BYTE_ORDER);
  auto buffer = static_cast<uint8_t*>(FPDFBitmap_GetBuffer(bitmap));
  std::vector<uint8_t> result(buffer, buffer + width * height * 4);
  FPDFBitmap_Destroy(bitmap);
  FPDF_ClosePage(page);
  return result;
}
int wmain(int argc, wchar_t** argv)
{
  fs::path temporary = fs::temp_directory_path() /
      (L"zotpaper-pdf-test-" + std::to_wstring(GetCurrentProcessId()));
  try
  {
    Check(argc == 2, "expected regression PDF directory argument");
    fs::create_directories(temporary);
    int files = 0, pages = 0;
    for (const auto& entry : fs::recursive_directory_iterator(argv[1]))
    {
      if (!entry.is_regular_file() || entry.path().extension() != L".pdf") continue;
      std::ifstream input(entry.path(), std::ios::binary);
      std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
      // Includes characters unavailable in the Windows ANSI code page.
      fs::path unicodePath = temporary / L"\u4e2d\u6587-\u7b49-\U0001f4c4.pdf";
      fs::copy_file(entry.path(), unicodePath, fs::copy_options::overwrite_existing);
      auto memory = pdfviewer::initializePdfRenderer(bytes, "", "memory");
      if (memory->pdfDocument == nullptr)
        std::cerr << "baseline file=" << entry.path().parent_path().filename().u8string()
                  << "; bytes=" << bytes.size() << "; error=" << FPDF_GetLastError() << '\n';
      Check(memory->pdfDocument != nullptr, "memory baseline failed to load");
      auto file = pdfviewer::loadPdfFromFile(unicodePath.u8string(), "", "file");
      if (file->pdfDocument == nullptr)
        std::cerr << "file load error=" << FPDF_GetLastError()
                  << "; bytes=" << bytes.size() << '\n';
      Check(file->pdfDocument != nullptr, "Unicode file document failed to load");
      const int count = FPDF_GetPageCount(memory->pdfDocument);
      Check(count > 0 && FPDF_GetPageCount(file->pdfDocument) == count,
            "page counts differ");
      for (int page = 0; page < count; ++page)
      {
        Check(Render(file->pdfDocument, page) == Render(memory->pdfDocument, page),
              "file and memory page pixels differ");
        ++pages;
      }
      Check(FPDF_LoadPage(file->pdfDocument, count) == nullptr,
            "invalid page unexpectedly loaded");
      pdfviewer::closePdfDocument("file");
      file.reset();
      // Successful deletion verifies that close released the retained file.
      Check(fs::remove(unicodePath), "file handle leaked");
      Check(!Render(memory->pdfDocument, 0).empty(),
            "closing file document affected memory document");
      pdfviewer::closePdfDocument("memory");
      memory.reset();
      ++files;
    }
    Check(files > 0, "no regression PDFs found");
    auto missing = pdfviewer::loadPdfFromFile((temporary / L"missing.pdf").u8string(), "", "missing");
    Check(missing->pdfDocument == nullptr && pdfviewer::getPdfDocument("missing") == nullptr,
          "missing file registered as a valid document");
    auto corruptPath = temporary / L"corrupt.pdf";
    { std::ofstream output(corruptPath); output << "not a PDF"; }
    auto corrupt = pdfviewer::loadPdfFromFile(corruptPath.u8string(), "", "corrupt");
    Check(corrupt->pdfDocument == nullptr && pdfviewer::getPdfDocument("corrupt") == nullptr,
          "corrupt file registered as a valid document");
    corrupt.reset();
    Check(fs::remove(corruptPath), "failed-load file handle leaked");
    pdfviewer::closePdfDocument("missing");
    fs::remove_all(temporary);
    std::cout << "PASS: " << files << " PDFs, " << pages
              << " pages; Unicode/emoji paths, exact pixel parity, invalid files, handle lifetime\n";
    return 0;
  }
  catch (const std::exception& error)
  {
    std::cerr << "FAIL: " << error.what() << '\n';
    std::error_code ignored;
    fs::remove_all(temporary, ignored);
    return 1;
  }
}
