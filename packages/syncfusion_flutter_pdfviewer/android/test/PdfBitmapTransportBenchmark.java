package com.syncfusion.flutter.pdfviewer;

import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.pdf.PdfDocument;
import android.graphics.pdf.PdfRenderer;
import android.os.Debug;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.util.Map;

/** Isolated dex main: run each mode in a fresh process, never inside the app. */
public final class PdfBitmapTransportBenchmark {
    private static final int WIDTH = 2573;
    private static final int HEIGHT = 3324;

    public static void main(String[] args) throws Exception {
        if (args.length != 2 || !(args[1].equals("direct") || args[1].equals("legacy"))) {
            throw new IllegalArgumentException("Expected output directory and direct|legacy");
        }
        File root = new File(args[0]);
        File pdf = new File(root, "benchmark.pdf");
        createPdf(pdf);
        PdfRasterFiles files = new PdfRasterFiles(root);
        try (ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY);
                PdfRenderer renderer = new PdfRenderer(descriptor)) {
            // Initialize JNI, framework and measurement code before the baseline.
            Bitmap warmup = Bitmap.createBitmap(17, 17, Bitmap.Config.ARGB_8888);
            PdfBitmapPixels.write(warmup, new File(root, "warmup.rgba"));
            warmup.recycle();
            sample(args[1], -1, "warmup", 0);
            // Normalize only this synthetic test process, not the running app.
            System.gc();
            System.runFinalization();
            Thread.sleep(100);
            sample(args[1], -1, "baseline", 0);
            for (int index = 0; index < 3; index++) {
                try (PdfRenderer.Page page = renderer.openPage(index)) {
                    Bitmap bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888);
                    try {
                        bitmap.eraseColor(Color.WHITE);
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
                        sample(args[1], index, "rendered", 0);
                        ByteBuffer legacy = null;
                        long start = SystemClock.elapsedRealtimeNanos();
                        Map<String, Object> reply;
                        if (args[1].equals("legacy")) {
                            legacy = ByteBuffer.allocate(bitmap.getByteCount());
                            bitmap.copyPixelsToBuffer(legacy);
                            reply = files.write(legacy.array());
                        } else {
                            reply = files.write(WIDTH * HEIGHT * 4, file -> PdfBitmapPixels.write(bitmap, file));
                        }
                        long elapsed = SystemClock.elapsedRealtimeNanos() - start;
                        if (((Number) reply.get("byteLength")).intValue() != WIDTH * HEIGHT * 4) {
                            throw new AssertionError("Raster length mismatch");
                        }
                        sample(args[1], index, "transport", elapsed);
                        // Keep the old array alive through the measured overlap.
                        if (legacy != null && legacy.get(0) != (byte) 255) {
                            throw new AssertionError("Raster pixel mismatch");
                        }
                        files.release((String) reply.get("token"));
                    } finally {
                        bitmap.recycle();
                    }
                }
                sample(args[1], index, "released", 0);
            }
        } finally {
            files.close();
            new File(root, "warmup.rgba").delete();
            pdf.delete();
        }
    }

    private static void createPdf(File file) throws Exception {
        PdfDocument document = new PdfDocument();
        try {
            Paint paint = new Paint();
            for (int index = 0; index < 3; index++) {
                PdfDocument.Page page = document.startPage(new PdfDocument.PageInfo.Builder(240, 320, index + 1).create());
                paint.setColor(Color.argb(177, 218 - index * 20, 43 + index * 20, 87));
                page.getCanvas().drawRect(13, 27, 178, 293, paint);
                document.finishPage(page);
            }
            try (FileOutputStream stream = new FileOutputStream(file)) {
                document.writeTo(stream);
            }
        } finally {
            document.close();
        }
    }

    private static void sample(String mode, int page, String phase, long nanos) {
        Debug.MemoryInfo memory = new Debug.MemoryInfo();
        Debug.getMemoryInfo(memory);
        long javaUsed = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory();
        System.out.println("{\"mode\":\"" + mode + "\",\"page\":" + page
                + ",\"phase\":\"" + phase + "\",\"pssKiB\":" + memory.getTotalPss()
                + ",\"privateDirtyKiB\":" + memory.getTotalPrivateDirty()
                + ",\"javaBytes\":" + javaUsed
                + ",\"nativeBytes\":" + Debug.getNativeHeapAllocatedSize()
                + ",\"transportNanos\":" + nanos + "}");
    }
}
