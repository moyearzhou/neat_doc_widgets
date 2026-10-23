export interface PdfiumRenderRequest {
  execute: () => Promise<Uint8Array | null>;
  isCurrent: () => boolean;
  // Evaluated at dispatch: a queued neighbor may enter or leave the viewport.
  priority: () => number;
  label: string;
}

interface PendingRender {
  request: PdfiumRenderRequest;
  resolve: (value: Uint8Array | null) => void;
  reject: (reason: Error) => void;
  queuedAt: number;
}

/** Serial PDFium execution with dynamic viewport priority and stale pruning. */
export class PdfiumRenderQueue {
  private pending: PendingRender[] = [];
  private active: boolean = false;

  private onDispatch: (label: string, queueMs: number,
    foregroundPending: number, thumbnailPending: number) => void;

  constructor(onDispatch: (label: string, queueMs: number,
    foregroundPending: number, thumbnailPending: number) => void) {
    this.onDispatch = onDispatch;
  }

  render(request: PdfiumRenderRequest): Promise<Uint8Array | null> {
    return new Promise<Uint8Array | null>((resolve, reject) => {
      const task: PendingRender = { request: request, resolve: resolve,
        reject: reject, queuedAt: Date.now() };
      this.pending.push(task);
      this.refresh();
    });
  }

  refresh(): void {
    // Resolve skipped requests now, so Dart can release its pending slot even
    // while another page still owns the one real native execution slot.
    this.pending = this.pending.filter((task: PendingRender): boolean => {
      if (task.request.isCurrent()) {
        return true;
      }
      task.resolve(null);
      return false;
    });
    if (!this.active) {
      this.drain();
    }
  }

  private async drain(): Promise<void> {
    if (this.active || this.pending.length === 0) {
      return;
    }
    let next = 0;
    for (let i = 1; i < this.pending.length; i++) {
      if (this.pending[i].request.priority() < this.pending[next].request.priority()) {
        next = i;
      }
    }
    const task = this.pending.splice(next, 1)[0];
    this.active = true;
    const foreground = this.pending.filter((item: PendingRender): boolean =>
      item.request.priority() < 2).length;
    this.onDispatch(task.request.label, Date.now() - task.queuedAt,
      foreground, this.pending.length - foreground);
    try {
      const pixels = await task.request.execute();
      task.resolve(task.request.isCurrent() ? pixels : null);
    } catch (error) {
      task.reject(error as Error);
    } finally {
      // Never release early on viewport cancellation: the native promise must
      // settle before any other request may use the shared PDFium document.
      this.active = false;
      this.refresh();
    }
  }
}
