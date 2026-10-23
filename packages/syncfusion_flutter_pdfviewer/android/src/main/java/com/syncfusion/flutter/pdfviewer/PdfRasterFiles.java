package com.syncfusion.flutter.pdfviewer;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/** Worker-owned, app-private transport files, never a persistent page cache. */
final class PdfRasterFiles {
    private static final Set<File> ACTIVE = new HashSet<>();
    private final Map<String, File> files = new HashMap<>();
    private final File directory;
    private long nextToken;

    PdfRasterFiles(File cacheDirectory) throws IOException {
        File root = new File(cacheDirectory, "syncfusion_pdf_rasters");
        synchronized (ACTIVE) {
            if (!root.isDirectory() && !root.mkdirs()) {
                throw new IOException("Cannot create PDF raster directory");
            }
            // A process crash cannot send release messages. Remove abandoned
            // engine directories on the next attach, keeping live engines safe.
            File[] old = root.listFiles();
            if (old != null) {
                for (File entry : old) {
                    if (!ACTIVE.contains(entry)) {
                        deleteDirectory(entry);
                    }
                }
            }
            directory = File.createTempFile("engine-", "", root);
            if (!directory.delete() || !directory.mkdir()) {
                throw new IOException("Cannot create engine raster directory");
            }
            ACTIVE.add(directory);
        }
    }

    Map<String, Object> write(byte[] pixels) throws IOException {
        String token = Long.toString(++nextToken);
        File file = new File(directory, token + ".rgba");
        try {
            try (FileOutputStream output = new FileOutputStream(file)) {
                output.write(pixels);
            }
            files.put(token, file);
            Map<String, Object> reply = new HashMap<>();
            reply.put("token", token);
            reply.put("path", file.getAbsolutePath());
            reply.put("byteLength", pixels.length);
            return reply;
        } catch (IOException error) {
            file.delete();
            throw error;
        }
    }

    void release(String token) {
        File file = files.get(token);
        if (file != null && (!file.exists() || file.delete())) {
            files.remove(token);
        }
    }

    void close() {
        synchronized (ACTIVE) {
            deleteDirectory(directory);
            files.clear();
            ACTIVE.remove(directory);
        }
    }

    private static void deleteDirectory(File directory) {
        File[] children = directory.listFiles();
        if (children != null) {
            for (File child : children) {
                child.delete();
            }
        }
        directory.delete();
    }
}
