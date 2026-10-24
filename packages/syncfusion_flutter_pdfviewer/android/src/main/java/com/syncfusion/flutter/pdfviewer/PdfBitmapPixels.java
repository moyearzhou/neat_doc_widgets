package com.syncfusion.flutter.pdfviewer;

import android.graphics.Bitmap;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.IOException;

/** Copies software bitmap pixels to the existing transport without a Java raster. */
final class PdfBitmapPixels {
    private static final boolean AVAILABLE;

    static {
        boolean loaded;
        try {
            System.loadLibrary("syncfusion_pdf_bitmap");
            loaded = true;
        } catch (UnsatisfiedLinkError error) {
            // Keep the byte-array transport usable with older native packages.
            loaded = false;
        }
        AVAILABLE = loaded;
    }

    static void write(Bitmap bitmap, File file) throws IOException {
        if (!AVAILABLE) {
            throw new IOException("PDF bitmap writer is unavailable");
        }
        try (ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(file,
                ParcelFileDescriptor.MODE_CREATE | ParcelFileDescriptor.MODE_TRUNCATE
                        | ParcelFileDescriptor.MODE_WRITE_ONLY)) {
            if (!writePixels(bitmap, descriptor.getFd())) {
                throw new IOException("Cannot write PDF bitmap pixels");
            }
        }
    }

    private static native boolean writePixels(Bitmap bitmap, int descriptor);
}
