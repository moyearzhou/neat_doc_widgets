interface PdfRenderer {
  openDocument(path: string): number;
  closeDocument(documentId: number): boolean;
  renderPage(
    documentId: number,
    pageIndex: number,
    width: number,
    height: number,
    requestGeneration: number,
    outputBgra: boolean
  ): Promise<Uint8Array | null>;
  renderTile(
    documentId: number,
    pageIndex: number,
    x: number,
    y: number,
    width: number,
    height: number,
    scale: number,
    requestGeneration: number
  ): Promise<Uint8Array | null>;
}

declare const pdfRenderer: PdfRenderer;
export default pdfRenderer;
