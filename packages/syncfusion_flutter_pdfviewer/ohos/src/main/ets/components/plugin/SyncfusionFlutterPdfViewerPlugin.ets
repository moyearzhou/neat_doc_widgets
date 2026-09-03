/*
* Copyright (C) 2026 Huawei Device Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  StandardMessageCodec,
  StandardMethodCodec,
  MethodResult,
} from '@ohos/flutter_ohos';
import { pdfService } from '@kit.PDFKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { HashMap } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { LogUtil } from './utils/LogUtil';
import pdfRenderer from 'libpdf_renderer.so';

const STANDARD_CODEC_UINT8_ARRAY: number = 8;

class PdfPixelMethodCodec extends StandardMethodCodec {
  constructor() {
    super(StandardMessageCodec.INSTANCE);
  }

  encodeSuccessEnvelope(value: ESObject): ArrayBuffer {
    if (!(value instanceof Uint8Array)) {
      return super.encodeSuccessEnvelope(value);
    }

    const byteLength = value.byteLength;
    const headerLength = byteLength < 254 ? 3 : byteLength <= 0xffff ? 5 : 7;
    let buffer: ArrayBuffer;
    let reusedPrefixedBuffer = false;
    if (value.byteOffset === headerLength &&
      value.byteOffset + byteLength === value.buffer.byteLength) {
      buffer = value.buffer as ArrayBuffer;
      reusedPrefixedBuffer = true;
    } else {
      buffer = new ArrayBuffer(headerLength + byteLength);
      new Uint8Array(buffer, headerLength, byteLength).set(value);
    }

    const header = new DataView(buffer);
    header.setUint8(0, 0);
    header.setUint8(1, STANDARD_CODEC_UINT8_ARRAY);
    if (byteLength < 254) {
      header.setUint8(2, byteLength);
    } else if (byteLength <= 0xffff) {
      header.setUint8(2, 254);
      header.setUint16(3, byteLength, true);
    } else {
      header.setUint8(2, 255);
      header.setUint32(3, byteLength, true);
    }
    LogUtil.info(`[Syncfusion PDF][arktsCodec] bytes=${byteLength}, ` +
      `reusedPrefixedBuffer=${reusedPrefixedBuffer}`);
    return buffer;
  }
}

// 定义文档信息接口
interface DocumentInfo {
  filePath: string;
  ownsFile: boolean;
  pageCount: number;
  pdfDocument: pdfService.PdfDocument;
  pdfiumDocumentId?: number;
  pageRequestGeneration: number[];
  tileRequestGeneration: number[];
}

interface PdfiumRenderTask {
  execute: () => Promise<Uint8Array | null>;
  resolve: (value: Uint8Array | null) => void;
  reject: (reason: Error) => void;
  queuedAt: number;
  label: string;
}

/** SyncfusionFlutterPdfViewerPlugin  **/
export default class SyncfusionFlutterPdfViewerPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private pathDir: string | null = '';
  // Width collections of rendered pages
  private pageWidth: number[] = [];
  // Height collections of rendered pages
  private pageHeight: number[] = [];
  // Document repository.
  private documentRepo: HashMap<String, DocumentInfo> = new HashMap<String, DocumentInfo>();
  private foregroundRenderQueue: PdfiumRenderTask[] = [];
  private thumbnailRenderQueue: PdfiumRenderTask[] = [];
  private isPdfiumRenderActive: boolean = false;

  getUniqueClassName(): string {
    return 'SyncfusionFlutterPdfViewerPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      'syncfusion_flutter_pdfviewer',
      new PdfPixelMethodCodec()
    );
    this.pathDir = binding.getApplicationContext().filesDir;
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'initializePdfRenderer':
        await this.initializePdfRenderer(call, result);
        break;
      case 'initializePdfRendererFromFile':
        this.initializePdfRendererFromFile(call, result, 'filePath');
        break;
      case 'loadPdfFromFile':
        this.initializePdfRendererFromFile(call, result, 'path');
        break;
      case 'getPagesWidth':
        // 返回页面宽度数组
        this.getPagesWidth(call, result);
        break;
      case 'getPagesHeight':
        // 返回页面高度数组
        this.getPagesHeight(call, result);
        break;
      case 'getPage':
        await this.getPage(call, result, false);
        break;
      case 'getPageAsBgra':
        await this.getPage(call, result, true);
        break;
      case 'getTileImage':
        // 实现瓦片图像渲染逻辑
        this.getTileImage(call, result);
        break;
      case 'closeDocument':
        this.closeDocument(call, result);
        break;
      case 'getPlatformVersion':
        result.success('OpenHarmony');
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private async initializePdfRenderer(call: MethodCall, result: MethodResult) {
    try {
      let buffer: Uint8Array = call.argument('documentBytes');
      let documentID: string = call.argument('documentID');

      // 验证参数
      if (!buffer || !documentID) {
        LogUtil.error('Syncfusion PDF Missing required parameters for initializePdfRenderer');
        result.error('initializePdfRenderer error',
          'Syncfusion PDF Missing required parameters for initializePdfRenderer', '');
        return;
      }

      // 将数据写入应用内的文件中
      let filePath = this.pathDir + '/temp_' + documentID + '.pdf';

      let file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      let writeLen: number = await fs.write(file.fd, buffer.buffer)
      await fs.close(file);

      const pageCount = this.openDocument(filePath, documentID, true, 'bytes');
      if (pageCount !== null) {
        result.success(pageCount + '');
        return;
      }
      result.success(null);
    } catch (error) {
      LogUtil.error('Syncfusion PDF initializePdfRenderer failed with error : ' + error);
      result.error(error.code, error.message, error);
    }
  }

  private initializePdfRendererFromFile(
    call: MethodCall,
    result: MethodResult,
    pathArgument: string
  ) {
    try {
      const filePath: string = call.argument(pathArgument);
      const documentID: string = call.argument('documentID');
      if (!filePath || !documentID) {
        result.error(`${call.method} error`,
          'Syncfusion PDF Missing required file initialization parameters', '');
        return;
      }

      const startedAt = Date.now();
      const pageCount = this.openDocument(filePath, documentID, false, 'file');
      if (pageCount === null) {
        result.error(`${call.method} error`,
          'Syncfusion PDF Unable to open the supplied PDF file', '');
        return;
      }
      LogUtil.info(`Syncfusion PDF direct file initialized: pages=${pageCount}, ` +
        `durationMs=${Date.now() - startedAt}, path=${filePath}`);
      result.success(pageCount + '');
    } catch (error) {
      LogUtil.error(`Syncfusion PDF ${call.method} failed with error: ` + error);
      result.error(error.code, error.message, error);
    }
  }

  private openDocument(
    filePath: string,
    documentID: string,
    ownsFile: boolean,
    source: string
  ): number | null {
    const pdfDocument: pdfService.PdfDocument = new pdfService.PdfDocument();
    const loadResult: pdfService.ParseResult = pdfDocument.loadDocument(filePath);
    if (pdfService.ParseResult.PARSE_SUCCESS !== loadResult) {
      pdfDocument.releaseDocument();
      LogUtil.error(`Syncfusion PDF PDF Kit open failed: source=${source}, result=${loadResult}`);
      return null;
    }

    const pageCount: number = pdfDocument.getPageCount();
    let pdfiumDocumentId: number | undefined;
    try {
      pdfiumDocumentId = pdfRenderer.openDocument(filePath);
    } catch (error) {
      // PDF Kit remains the recovery path if PDFium cannot load a document.
      LogUtil.error('Syncfusion PDF PDFium openDocument failed with error: ' + error);
    }
    this.documentRepo.set(documentID, {
      filePath: filePath,
      ownsFile: ownsFile,
      pageCount: pageCount,
      pdfDocument: pdfDocument,
      pdfiumDocumentId: pdfiumDocumentId,
      pageRequestGeneration: [],
      tileRequestGeneration: []
    });
    LogUtil.info(`Syncfusion PDF renderer initialized: source=${source}, pages=${pageCount}, ` +
      `pdfium=${pdfiumDocumentId !== undefined}`);
    return pageCount;
  }

  private getPagesWidth(call: MethodCall, result: MethodResult) {
    try {
      let documentID: string = call.args;

      // 从文档仓库中获取文档信息
      if (this.documentRepo.hasKey(documentID)) {
        const docInfo = this.documentRepo.get(documentID);
        if (docInfo && docInfo.pageCount && docInfo.pdfDocument) {
          // 创建默认宽度数组
          for (let i = 0; i < docInfo.pageCount; i++) {
            let pdfPage: pdfService.PdfPage = docInfo.pdfDocument.getPage(i);
            this.pageWidth[i] = pdfPage.getWidth();
            pdfPage.release();
          }
          result.success(this.pageWidth);
          return;
        }
      }

      result.success(null);
    } catch (error) {
      LogUtil.error('Syncfusion PDF getPagesWidth failed with error : ' + error);
      result.error(error.code, error.message, error);
    }
  }

  private getPagesHeight(call: MethodCall, result: MethodResult) {
    try {
      let documentID: string = call.args;

      // 从文档仓库中获取文档信息
      if (this.documentRepo.hasKey(documentID)) {
        const docInfo = this.documentRepo.get(documentID);
        if (docInfo && docInfo.pageCount && docInfo.pdfDocument) {
          // 创建默认高度数组
          for (let i = 0; i < docInfo.pageCount; i++) {
            let pdfPage: pdfService.PdfPage = docInfo.pdfDocument.getPage(i);
            this.pageWidth[i] = pdfPage.getWidth();
            this.pageHeight[i] = pdfPage.getHeight();
            pdfPage.release();
          }
          result.success(this.pageHeight);
        }
      }

      result.success(null);
    } catch (error) {
      LogUtil.error('Syncfusion PDF getPagesHeight failed with error message: ' + error);
      result.error(error.code, error.message, error);
    }
  }

  private async getPage(call: MethodCall, result: MethodResult, outputBgra: boolean) {
    try {
      // 记录传入的参数
      const index: number = call.argument('index');
      const width: number = call.argument('width');
      const height: number = call.argument('height');
      const documentID: string = call.argument('documentID');

      // 验证参数
      if (index === undefined || width === undefined || height === undefined) {
        LogUtil.error('Syncfusion PDF getPage missing required parameters');
        result.success(null);
        return;
      }

      const docInfo = this.documentRepo.get(documentID);
      if (!docInfo || index < 1 || index > docInfo.pageCount) {
        result.success(null);
        return;
      }

      const pageIndex = index - 1;
      const outputWidth = Math.floor(width);
      const outputHeight = Math.floor(height);
      const requestGeneration = (docInfo.pageRequestGeneration[pageIndex] ?? 0) + 1;
      docInfo.pageRequestGeneration[pageIndex] = requestGeneration;
      const startedAt = Date.now();
      LogUtil.info(`[Syncfusion PDF][arktsPageRequest] document=${documentID}, page=${index}, ` +
        `size=${outputWidth}x${outputHeight}, generation=${requestGeneration}`);

      try {
        if (docInfo.pdfiumDocumentId === undefined) {
          docInfo.pdfiumDocumentId = pdfRenderer.openDocument(docInfo.filePath);
        }
        const page = await this.schedulePdfiumRender(
          () => pdfRenderer.renderPage(
            docInfo.pdfiumDocumentId as number,
            pageIndex,
            outputWidth,
            outputHeight,
            requestGeneration,
            outputBgra
          ),
          outputBgra,
          `document=${documentID} page=${index} generation=${requestGeneration} ` +
            `size=${outputWidth}x${outputHeight} format=${outputBgra ? 'bgra' : 'rgba'}`
        );
        if (page === null) {
          LogUtil.info(`Syncfusion PDF PDFium page superseded: page=${index}, ` +
            `generation=${requestGeneration}, durationMs=${Date.now() - startedAt}`);
          result.success(null);
          return;
        }
        LogUtil.info(`[Syncfusion PDF][arktsPageResult] document=${documentID}, page=${index}, ` +
          `generation=${requestGeneration}, durationMs=${Date.now() - startedAt}, bytes=${page.length}`);
        const replyStartedAt = Date.now();
        result.success(page);
        LogUtil.info(`[Syncfusion PDF][arktsPageReply] document=${documentID}, page=${index}, ` +
          `bytes=${page.length}, replyMs=${Date.now() - replyStartedAt}`);
        return;
      } catch (error) {
        // Keep PDF Kit as a recovery path and preserve the requested pixel contract.
        LogUtil.error(`Syncfusion PDF PDFium page failed, using PDF Kit: page=${index}, error=${error}`);
      }

      const fallbackPage = await this.getPageWithPdfKit(
        docInfo,
        pageIndex,
        outputWidth,
        outputHeight,
        outputBgra
      );
      LogUtil.info(`Syncfusion PDF PDF Kit fallback rendered: page=${index}, width=${outputWidth}, ` +
        `height=${outputHeight}, generation=${requestGeneration}, durationMs=${Date.now() - startedAt}, ` +
        `bytes=${fallbackPage.length}`);
      result.success(fallbackPage);
    } catch (error) {
      LogUtil.error('Syncfusion PDF getPage failed with error : ' + error);
      result.error(error.code, error.message, error);
    }
  }

  private async getTileImage(call: MethodCall, result: MethodResult) {
    try {
      // 记录传入的参数
      const pageNumber: number = call.argument('pageNumber');
      const scale: number = call.argument('scale'); // zoomLevel * _dpr * ratio (缩放后的比例)
      const x: number = call.argument('x'); // exposed.left / zoomLevel (PDF原始坐标系中的x)
      const y: number = call.argument('y'); // exposed.top / zoomLevel (PDF原始坐标系中的y)
      const width: number = call.argument('width'); // tileImageSize.width (输出图像的像素宽度)
      const height: number = call.argument('height'); // tileImageSize.height (输出图像的像素高度)
      const documentID: string = call.argument('documentID');

      if (pageNumber === undefined || scale === undefined || x === undefined || y === undefined ||
        width === undefined || height === undefined || !documentID) {
        LogUtil.error('Syncfusion PDF getTileImage missing required parameters');
        result.success(null);
        return;
      }

      const docInfo = this.documentRepo.get(documentID);
      if (!docInfo || pageNumber < 1 || pageNumber > docInfo.pageCount) {
        result.success(null);
        return;
      }

      if (docInfo.pdfiumDocumentId === undefined) {
        docInfo.pdfiumDocumentId = pdfRenderer.openDocument(docInfo.filePath);
      }

      // Syncfusion supplies x/y in unscaled page coordinates and scale already includes DPR.
      const pageIndex = pageNumber - 1;
      const requestGeneration = (docInfo.tileRequestGeneration[pageIndex] ?? 0) + 1;
      docInfo.tileRequestGeneration[pageIndex] = requestGeneration;
      const startedAt = Date.now();
      LogUtil.info(`Syncfusion PDF PDFium tile request: page=${pageNumber}, width=${Math.floor(width)}, ` +
        `height=${Math.floor(height)}, scale=${scale}, generation=${requestGeneration}`);
      const tile = await this.schedulePdfiumRender(
        () => pdfRenderer.renderTile(
          docInfo.pdfiumDocumentId as number,
          pageIndex,
          x,
          y,
          Math.floor(width),
          Math.floor(height),
          scale,
          requestGeneration
        ),
        true,
        `document=${documentID} tile page=${pageNumber} generation=${requestGeneration} ` +
          `size=${Math.floor(width)}x${Math.floor(height)}`
      );
      if (tile === null) {
        LogUtil.info(`Syncfusion PDF PDFium tile superseded: page=${pageNumber}, ` +
          `generation=${requestGeneration}, durationMs=${Date.now() - startedAt}`);
        result.success(null);
        return;
      }
      LogUtil.info(`Syncfusion PDF PDFium tile rendered: page=${pageNumber}, width=${Math.floor(width)}, ` +
        `height=${Math.floor(height)}, scale=${scale}, generation=${requestGeneration}, ` +
        `durationMs=${Date.now() - startedAt}, bytes=${tile.length}`);
      const replyStartedAt = Date.now();
      result.success(tile);
      LogUtil.info(`[Syncfusion PDF][arktsTileReply] document=${documentID}, page=${pageNumber}, ` +
        `bytes=${tile.length}, replyMs=${Date.now() - replyStartedAt}`);
    } catch (error) {
      LogUtil.error('Syncfusion PDF getTileImage failed with error : ' + error);
      result.error(error.code, error.message, error);
    }
  }

  private schedulePdfiumRender(
    execute: () => Promise<Uint8Array | null>,
    foreground: boolean,
    label: string
  ): Promise<Uint8Array | null> {
    return new Promise<Uint8Array | null>((resolve, reject) => {
      const task: PdfiumRenderTask = {
        execute: execute,
        resolve: resolve,
        reject: reject,
        queuedAt: Date.now(),
        label: label
      };
      if (foreground) {
        this.foregroundRenderQueue.push(task);
      } else {
        this.thumbnailRenderQueue.push(task);
      }
      this.drainPdfiumRenderQueue();
    });
  }

  private async drainPdfiumRenderQueue(): Promise<void> {
    if (this.isPdfiumRenderActive) {
      return;
    }
    const task = this.foregroundRenderQueue.shift() ?? this.thumbnailRenderQueue.shift();
    if (!task) {
      return;
    }

    this.isPdfiumRenderActive = true;
    const queueDuration = Date.now() - task.queuedAt;
    LogUtil.info(`[Syncfusion PDF][arktsDispatch] ${task.label}, ` +
      `queueMs=${queueDuration}, foregroundPending=${this.foregroundRenderQueue.length}, ` +
      `thumbnailPending=${this.thumbnailRenderQueue.length}`);
    try {
      task.resolve(await task.execute());
    } catch (error) {
      task.reject(error as Error);
    } finally {
      this.isPdfiumRenderActive = false;
      this.drainPdfiumRenderQueue();
    }
  }

  // 将 pixelMap 转成图片格式  低版本
  private async pixelMap2Buffer(pixelMap: image.PixelMap): Promise<Uint8Array> {
    const byteCount = pixelMap.getPixelBytesNumber();
    const arrayBuffer = new ArrayBuffer(byteCount);
    await pixelMap.readPixelsToBuffer(arrayBuffer);
    return new Uint8Array(arrayBuffer);
  }

  private async getPageWithPdfKit(
    docInfo: DocumentInfo,
    pageIndex: number,
    width: number,
    height: number,
    outputBgra: boolean
  ): Promise<Uint8Array> {
    const pdfPage: pdfService.PdfPage = docInfo.pdfDocument.getPage(pageIndex);
    const pdfMatrix: pdfService.PdfMatrix = new pdfService.PdfMatrix();
    pdfMatrix.x = 0;
    pdfMatrix.y = 0;
    pdfMatrix.width = width;
    pdfMatrix.height = height;
    pdfMatrix.rotate = 0;

    const pixelMap: image.PixelMap = pdfPage.getAreaPixelMap(pdfMatrix, width, height, false, true);
    const bgraBytes = await this.pixelMap2Buffer(pixelMap);
    pdfPage.release();
    await pixelMap.release();
    if (!outputBgra) {
      for (let offset = 0; offset < bgraBytes.length; offset += 4) {
        const blue = bgraBytes[offset];
        bgraBytes[offset] = bgraBytes[offset + 2];
        bgraBytes[offset + 2] = blue;
      }
    }
    return bgraBytes;
  }

  private closeDocument(call: MethodCall, result: MethodResult) {
    try {
      let documentID: string = call.args;
      // 从文档仓库中获取文档信息
      if (this.documentRepo.hasKey(documentID)) {
        const docInfo = this.documentRepo.get(documentID);
        if (docInfo && docInfo.filePath) {
          if (docInfo.pdfiumDocumentId !== undefined) {
            pdfRenderer.closeDocument(docInfo.pdfiumDocumentId);
          }
          if (docInfo.ownsFile) {
            fs.unlinkSync(docInfo.filePath);
          }
          // 释放pdf 重置宽度高度集合
          docInfo.pdfDocument.releaseDocument();
          this.pageWidth = [];
          this.pageHeight = [];
          // 从仓库中移除文档信息
          this.documentRepo.remove(documentID);
        }
      }

      result.success(true);
    } catch (error) {
      LogUtil.error('Syncfusion PDF closeDocument failed with error : ' + error);
      result.error(error.code, error.message, error);
    }
  }
}
