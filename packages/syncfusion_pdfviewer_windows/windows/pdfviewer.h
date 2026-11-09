#ifndef PDFVIEWER_H_
#define PDFVIEWER_H_

#include <fpdfview.h>

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

namespace pdfviewer
{
  class PdfDocument
  {
  private:
    std::vector<uint8_t> data;
    // PDFium retains this callback and file until the document is closed.
    FILE* file = nullptr;
    FPDF_FILEACCESS fileAccess{};

  public:
    PdfDocument(std::vector<uint8_t> data, std::string password, std::string id);

    PdfDocument(std::string filePath, std::string password, std::string id);

    ~PdfDocument();

    PdfDocument(const PdfDocument&) = delete;
    PdfDocument& operator=(const PdfDocument&) = delete;

    FPDF_DOCUMENT pdfDocument = nullptr;
    std::string documentID;
  };

  std::shared_ptr<PdfDocument> initializePdfRenderer(std::vector<uint8_t> data, std::string password, std::string docID);
  std::shared_ptr<PdfDocument> loadPdfFromFile(std::string filePath, std::string password, std::string docID);
  std::shared_ptr<PdfDocument> getPdfDocument(std::string docID);
  void closePdfDocument(std::string docID);
}
#endif
