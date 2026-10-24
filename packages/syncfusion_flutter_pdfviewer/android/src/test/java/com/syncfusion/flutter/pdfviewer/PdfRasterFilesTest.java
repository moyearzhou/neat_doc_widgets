package com.syncfusion.flutter.pdfviewer;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.nio.file.Files;
import java.util.Map;

import static org.junit.Assert.*;

public class PdfRasterFilesTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();

    @Test public void releaseDeletesOnlyTheOwnedFile() throws Exception {
        PdfRasterFiles store = new PdfRasterFiles(temporary.getRoot());
        try {
            byte[] bytes = new byte[] {1, 2, 3, 4};
            Map<String, Object> reply = store.write(bytes);
            File file = new File((String) reply.get("path"));
            assertArrayEquals(bytes, Files.readAllBytes(file.toPath()));
            assertEquals(4, reply.get("byteLength"));
            store.release(file.getAbsolutePath());
            assertTrue(file.exists()); // Paths are never accepted as release tokens.
            store.release((String) reply.get("token"));
            store.release((String) reply.get("token"));
            assertFalse(file.exists());
        } finally {
            store.close();
        }
    }

    @Test public void closeRemovesOutstandingReplies() throws Exception {
        PdfRasterFiles store = new PdfRasterFiles(temporary.getRoot());
        Map<String, Object> first = store.write(new byte[4]);
        Map<String, Object> second = store.write(new byte[8]);
        store.close();
        assertFalse(new File((String) first.get("path")).exists());
        assertFalse(new File((String) second.get("path")).exists());
    }

    @Test public void directWriterPublishesExactPixelsAndCleansPartialFailures() throws Exception {
        PdfRasterFiles store = new PdfRasterFiles(temporary.getRoot());
        try {
            byte[] bytes = {1, 2, 3, 4};
            Map<String, Object> reply = store.write(4,
                    file -> Files.write(file.toPath(), bytes));
            File complete = new File((String) reply.get("path"));
            assertArrayEquals(bytes, Files.readAllBytes(complete.toPath()));
            for (boolean fail : new boolean[] {false, true}) {
                try {
                    store.write(8, file -> {
                        Files.write(file.toPath(), bytes);
                        if (fail) throw new java.io.IOException("partial write");
                    });
                    fail("Incomplete pixels must not be published");
                } catch (java.io.IOException expected) {
                    assertEquals(1, complete.getParentFile().listFiles().length);
                }
            }
            store.release((String) reply.get("token"));
            assertEquals(0, complete.getParentFile().listFiles().length);
        } finally {
            store.close();
        }
    }

    @Test public void newEngineCleansAbandonedFilesAndPreservesLiveEngines() throws Exception {
        File root = new File(temporary.getRoot(), "syncfusion_pdf_rasters");
        File abandoned = new File(root, "abandoned");
        assertTrue(abandoned.mkdirs());
        File orphan = new File(abandoned, "1.rgba");
        Files.write(orphan.toPath(), new byte[4]);
        PdfRasterFiles first = new PdfRasterFiles(temporary.getRoot());
        Map<String, Object> reply = first.write(new byte[4]);
        PdfRasterFiles second = new PdfRasterFiles(temporary.getRoot());
        try {
            assertFalse(abandoned.exists());
            assertTrue(new File((String) reply.get("path")).exists());
        } finally {
            first.close();
            second.close();
        }
    }
}
