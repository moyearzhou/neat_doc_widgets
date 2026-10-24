package com.syncfusion.flutter.pdfviewer;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Debug;
import android.graphics.pdf.PdfDocument;
import android.graphics.pdf.PdfRenderer;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.util.Arrays;

/** Run as a dex main with app_process and the built JNI library on an Android device. */
public final class PdfBitmapPixelsDeviceTest {
    public static void main(String[] args) throws Exception {
        File file = new File(args[0], "pixels.rgba");
        File pdf = new File(args[0], "synthetic.pdf");
        PdfDocument document = new PdfDocument();
        try {
            PdfDocument.Page page = document.startPage(new PdfDocument.PageInfo.Builder(240, 320, 1).create());
            Paint paint = new Paint();
            paint.setColor(Color.argb(177, 218, 43, 87));
            page.getCanvas().drawRect(13, 27, 178, 293, paint);
            document.finishPage(page);
            try (FileOutputStream output = new FileOutputStream(pdf)) { document.writeTo(output); }
        } finally { document.close(); }
        try (ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY);
                PdfRenderer renderer = new PdfRenderer(descriptor);
                PdfRenderer.Page page = renderer.openPage(0)) {
            Bitmap bitmap = Bitmap.createBitmap(513, 709, Bitmap.Config.ARGB_8888);
            bitmap.eraseColor(Color.WHITE);
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
            ByteBuffer expected = ByteBuffer.allocate(bitmap.getByteCount());
            bitmap.copyPixelsToBuffer(expected);
            PdfBitmapPixels.write(bitmap, file);
            if (!Arrays.equals(expected.array(), Files.readAllBytes(file.toPath()))) {
                throw new AssertionError("PdfRenderer pixel mismatch");
            }
            bitmap.recycle();
        }
        if (!pdf.delete()) throw new AssertionError("Cannot remove synthetic PDF");
        for (int width : new int[] {1, 17, 513, 2573}) {
            Bitmap bitmap = Bitmap.createBitmap(width, 709, Bitmap.Config.ARGB_8888);
            bitmap.eraseColor(Color.WHITE);
            Canvas canvas = new Canvas(bitmap);
            Paint paint = new Paint();
            paint.setColor(Color.argb(123, 218, 43, 87));
            canvas.drawRect(0, 3, width, 407, paint);
            bitmap.setPixel(0, 0, Color.argb(77, 12, 89, 234));
            ByteBuffer expected = ByteBuffer.allocate(bitmap.getByteCount());
            bitmap.copyPixelsToBuffer(expected);
            PdfBitmapPixels.write(bitmap, file);
            if (!Arrays.equals(expected.array(), Files.readAllBytes(file.toPath()))) {
                throw new AssertionError("Pixel mismatch at width " + width);
            }
            // Unlock must have happened: Java can still modify and recycle it.
            bitmap.eraseColor(Color.BLACK);
            bitmap.recycle();
        }
        Bitmap bitmap = Bitmap.createBitmap(2573, 3324, Bitmap.Config.ARGB_8888);
        bitmap.eraseColor(Color.WHITE);
        try {
            PdfBitmapPixels.write(bitmap, new File("/dev/full"));
            throw new AssertionError("Full output device must fail");
        } catch (java.io.IOException expected) {
            // Even a failed write must unlock, allowing reuse and later recycle.
            bitmap.eraseColor(Color.WHITE);
        }
        long before = Debug.getNativeHeapAllocatedSize();
        PdfBitmapPixels.write(bitmap, file);
        long direct = Debug.getNativeHeapAllocatedSize() - before;
        long javaBefore = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory();
        before = Debug.getNativeHeapAllocatedSize();
        ByteBuffer legacy = ByteBuffer.allocate(bitmap.getByteCount());
        bitmap.copyPixelsToBuffer(legacy);
        long copied = Debug.getNativeHeapAllocatedSize() - before;
        long javaCopied = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory() - javaBefore;
        if (legacy.get(0) != (byte) 255) throw new AssertionError("Legacy pixel mismatch");
        System.out.println("PASS: exact pixels, alpha, odd widths and unlock; rasterBytes="
                + bitmap.getByteCount() + " directNativeDelta=" + direct + " legacyNativeDelta=" + copied
                + " legacyJavaDelta=" + javaCopied);
        bitmap.recycle();
        if (!file.delete()) throw new AssertionError("Cannot remove test output");
    }
}
