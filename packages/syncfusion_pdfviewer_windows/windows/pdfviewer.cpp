#pragma warning(disable : 4458)

#include <Windows.h>
#include <gdiplus.h>

#include <iostream>
#include <stdexcept>
#include <string>
#include <map>
#include <filesystem>
#include <limits>

#include "pdfviewer.h"

#pragma comment(lib, "gdiplus.lib")

namespace pdfviewer
{

  std::map<std::string, std::shared_ptr<PdfDocument>> documentRepo;

  std::shared_ptr<PdfDocument> getPdfDocument(std::string docID)
  {
    std::shared_ptr<PdfDocument> documentPtr = nullptr;

    std::map<std::string, std::shared_ptr<PdfDocument>>::iterator documentRepoIterator = documentRepo.find(docID);
    // Checks whether the docID is present or not in the documentRepo map
    if (documentRepoIterator != documentRepo.end())
    {
      documentPtr = documentRepoIterator->second;
    }
    else 
    {
      documentPtr = nullptr;
    }

    return documentPtr;
  }

  void closePdfDocument(std::string docID)
  {
    std::shared_ptr<PdfDocument> documentPtr = getPdfDocument(docID);
    if (documentPtr == nullptr)
        return;
    documentRepo.erase(docID);
  }

  std::shared_ptr<PdfDocument> initializePdfRenderer(std::vector<uint8_t> data, std::string password, std::string docID)
  {
    if (documentRepo.size() == 0)
    {
      FPDF_InitLibraryWithConfig(nullptr);
    }

    std::shared_ptr<PdfDocument> doc = std::make_shared<PdfDocument>(data, password, docID);
    if (doc->pdfDocument != nullptr)
      documentRepo[docID] = doc;

    return doc;
  }

  std::shared_ptr<PdfDocument> loadPdfFromFile(std::string filePath, std::string password, std::string docID)
  {
    if (documentRepo.empty())
      FPDF_InitLibraryWithConfig(nullptr);

    auto doc = std::make_shared<PdfDocument>(filePath, password, docID);
    if (doc->pdfDocument != nullptr)
      documentRepo[docID] = doc;
    return doc;
  }

  namespace
  {
    int ReadFileBlock(void* parameter, unsigned long position,
                      unsigned char* buffer, unsigned long size)
    {
      FILE* file = static_cast<FILE*>(parameter);
      return _fseeki64(file, position, SEEK_SET) == 0 &&
             fread(buffer, 1, size, file) == size;
    }
  }

  PdfDocument::PdfDocument(std::vector<uint8_t> dataRef, std::string password, std::string id) : documentID{id}
  {
    data.swap(dataRef);
    pdfDocument = FPDF_LoadMemDocument64(data.data(), data.size(), password.c_str());
  }

  PdfDocument::PdfDocument(std::string filePath, std::string password, std::string id) : documentID{id}
  {
    // MethodChannel strings are UTF-8; PDFium's narrow Windows file API uses
    // the system code page. Open with the Unicode CRT API instead, and retain
    // a random-access callback so large PDFs are not copied into memory.
    const auto path = std::filesystem::u8path(filePath);
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0)
      return;
    if (_fseeki64(file, 0, SEEK_END) != 0)
      return;
    const auto length = _ftelli64(file);
    // FPDF_FILEACCESS uses unsigned long (32 bits on Windows); do not truncate.
    if (length <= 0 || length > (std::numeric_limits<unsigned long>::max)())
      return;
    fileAccess.m_FileLen = static_cast<unsigned long>(length);
    fileAccess.m_GetBlock = ReadFileBlock;
    fileAccess.m_Param = file;
    pdfDocument = FPDF_LoadCustomDocument(&fileAccess, password.c_str());
  }

  PdfDocument::~PdfDocument()
  {
    // PDFium may still read the file while closing the document.
    if (pdfDocument != nullptr)
      FPDF_CloseDocument(pdfDocument);
    if (file != nullptr)
      fclose(file);
  }
}
