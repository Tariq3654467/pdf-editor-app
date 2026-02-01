package com.example.pdf_editor_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.content.ContentUris
import android.database.Cursor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.content.ContentResolver
import android.content.SharedPreferences
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.pdf_editor_app/file_intent"
    private val PDF_SCAN_CHANNEL = "com.example.pdf_editor_app/pdf_scan"
    private val SAF_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Channel for file intent handling
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFileIntent" -> {
                val intent = intent
                if (intent?.action == Intent.ACTION_VIEW && intent.data != null) {
                    val uri = intent.data
                    if (uri != null) {
                        // Handle content:// URIs by copying to app cache
                        if (uri.scheme == "content") {
                            try {
                                val filePath = copyContentUriToCache(uri)
                                if (filePath != null) {
                                    result.success(filePath)
                                } else {
                                    result.success(uri.toString())
                                }
                            } catch (e: Exception) {
                                result.success(uri.toString())
                            }
                        } else {
                            result.success(uri.toString())
                        }
                    } else {
                        result.success(null)
                    }
                } else {
                    result.success(null)
                }
                }
                "copyContentUriToCache" -> {
                    try {
                        val contentUriString = call.arguments as? String
                        if (contentUriString != null) {
                            val uri = Uri.parse(contentUriString)
                            val filePath = copyContentUriToCache(uri)
                            result.success(filePath)
            } else {
                            result.error("INVALID_ARGUMENT", "Content URI string is null", null)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("PDFScan", "Error copying content URI", e)
                        result.error("COPY_ERROR", e.message, null)
                    }
                }
                else -> {
                result.notImplemented()
                }
            }
        }
        
        // Channel for PDF scanning and SAF access
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_SCAN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanPDFs" -> {
                    // Scan PDFs from stored SAF URIs (app-managed index)
                    Thread {
                        try {
                            val pdfList = scanPDFsFromSAFIndex()
                            // Post result back on main thread
                            runOnUiThread {
                                try {
                                    result.success(pdfList)
                                } catch (e: Exception) {
                                    android.util.Log.e("PDFScan", "Error delivering scan result", e)
                                }
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("PDFScan", "Scan error", e)
                            runOnUiThread {
                                try {
                                    result.error("SCAN_ERROR", "Failed to scan PDFs: ${e.message}", null)
                                } catch (inner: Exception) {
                                    android.util.Log.e("PDFScan", "Error delivering scan error", inner)
                                }
                            }
                        }
                    }.start()
                }
                "requestSAFAccess" -> {
                    // Request SAF access - user selects PDF or folder
                    pendingResult = result
                    requestSAFAccess()
                }
                "hasSAFAccess" -> {
                    // Check if we have any stored SAF URIs
                    val hasAccess = hasSAFAccess()
                    result.success(hasAccess)
                }
                "addSAFUri" -> {
                    // Add a SAF URI to the index (from user selection)
                    try {
                        val uriString = call.arguments as? String
                        if (uriString != null) {
                            val uri = Uri.parse(uriString)
                            addSAFUriToIndex(uri)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "URI string is null", null)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("PDFScan", "Error adding SAF URI", e)
                        result.error("ADD_ERROR", e.message, null)
                    }
                }
                "getStoredSAFUriCount" -> {
                    // Get count of stored SAF URIs
                    val count = getStoredSAFUriCount()
                    result.success(count)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun scanAllPDFs(): List<Map<String, Any>> {
        val pdfList = mutableListOf<Map<String, Any>>()
        val seenPaths = mutableSetOf<String>()
        
        android.util.Log.d("PDFScan", "Starting PDF scan (permission-less MediaStore only)...")
        
        try {
            // ONLY use MediaStore - no permissions required
            // This works on all Android versions without any storage permissions
            android.util.Log.d("PDFScan", "Scanning with MediaStore (Android ${Build.VERSION.SDK_INT})")
            val mediaStorePDFs = scanPDFsWithMediaStore()
            android.util.Log.d("PDFScan", "MediaStore found ${mediaStorePDFs.size} PDFs")
            
            for (pdf in mediaStorePDFs) {
                val path = pdf["path"] as? String
                if (path != null && !seenPaths.contains(path)) {
                    seenPaths.add(path)
                    pdfList.add(pdf)
                }
            }
        } catch (e: OutOfMemoryError) {
            android.util.Log.e("PDFScan", "Out of memory during scan", e)
            e.printStackTrace()
            // Return what we have so far
            android.util.Log.d("PDFScan", "Returning ${pdfList.size} PDFs before OOM")
        } catch (e: Exception) {
            android.util.Log.e("PDFScan", "MediaStore scan error", e)
            e.printStackTrace()
        } catch (e: Throwable) {
            android.util.Log.e("PDFScan", "Unexpected error during scan", e)
            e.printStackTrace()
        }
        
        android.util.Log.d("PDFScan", "Total PDFs found: ${pdfList.size}")
        return pdfList
    }
    
    @Suppress("DEPRECATION")
    private fun scanPDFsWithMediaStore(): List<Map<String, Any>> {
        val pdfList = mutableListOf<Map<String, Any>>()
        val contentResolver = contentResolver
        val seenUris = mutableSetOf<String>()
        val collectionCounts = mutableMapOf<String, Int>()
        
        android.util.Log.d("PDFScan", "=== Starting comprehensive MediaStore scan (Android ${Build.VERSION.SDK_INT}) ===")
        
        try {
            // Define all MediaStore collections to query
            val collectionsToQuery = mutableListOf<Triple<Uri, String, Array<String>>>()
            
            // 1. MediaStore.Downloads (Android 10+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    val downloadsUri = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                    val downloadsProjection = arrayOf(
                        MediaStore.Downloads._ID,
                        MediaStore.Downloads.DISPLAY_NAME,
                        MediaStore.Downloads.SIZE,
                        MediaStore.Downloads.DATE_MODIFIED,
                        MediaStore.Downloads.RELATIVE_PATH
                    )
                    collectionsToQuery.add(Triple(downloadsUri, "Downloads", downloadsProjection))
                } catch (e: Exception) {
                    android.util.Log.w("PDFScan", "Downloads collection not available: ${e.message}")
                }
            }
            
            // 2. MediaStore.Files (covers all files)
            try {
                val filesUri = MediaStore.Files.getContentUri("external")
                val filesProjection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    arrayOf(
                        MediaStore.Files.FileColumns._ID,
                        MediaStore.Files.FileColumns.DISPLAY_NAME,
                        MediaStore.Files.FileColumns.SIZE,
                        MediaStore.Files.FileColumns.DATE_MODIFIED,
                        MediaStore.Files.FileColumns.RELATIVE_PATH,
                        MediaStore.Files.FileColumns.MIME_TYPE
                    )
                } else {
                    arrayOf(
                        MediaStore.Files.FileColumns._ID,
                        MediaStore.Files.FileColumns.DISPLAY_NAME,
                        MediaStore.Files.FileColumns.SIZE,
                        MediaStore.Files.FileColumns.DATE_MODIFIED,
                        MediaStore.Files.FileColumns.MIME_TYPE
                    )
                }
                collectionsToQuery.add(Triple(filesUri, "Files", filesProjection))
            } catch (e: Exception) {
                android.util.Log.w("PDFScan", "Files collection not available: ${e.message}")
            }
            
            // 3. MediaStore.Documents (if available)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    // Documents collection might not be directly accessible, but try via Files
                    // For now, we'll rely on Files collection which should include documents
                } catch (e: Exception) {
                    android.util.Log.w("PDFScan", "Documents collection not directly accessible")
                }
            }
            
            // Query each collection
            for ((uri, collectionName, projection) in collectionsToQuery) {
                try {
                    android.util.Log.d("PDFScan", "Querying $collectionName collection...")
                    var collectionCount = 0
                    
                    // Use combined filter: MIME type OR file extension
                    // Note: Downloads collection may not have MIME_TYPE column on all devices
                    val selection = when {
                        collectionName == "Downloads" -> {
                            // Downloads: Use file extension only (more reliable)
                            "${MediaStore.Downloads.DISPLAY_NAME} LIKE ? OR LOWER(${MediaStore.Downloads.DISPLAY_NAME}) LIKE ?"
                        }
                        else -> {
                            // Files: Use MIME type OR extension
                            "${MediaStore.Files.FileColumns.MIME_TYPE} = ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?"
                        }
                    }
                    val selectionArgs = when {
                        collectionName == "Downloads" -> arrayOf("%.pdf", "%.pdf")
                        else -> arrayOf("application/pdf", "%.pdf")
                    }
                    val sortOrder = when {
                        collectionName == "Downloads" -> "${MediaStore.Downloads.DATE_MODIFIED} DESC"
                        else -> "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
                    }
                    
                    val cursor: Cursor? = contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
                    
                    cursor?.use {
                        try {
                            val totalCount = it.count
                            android.util.Log.d("PDFScan", "$collectionName: Cursor returned $totalCount total rows")
                            
                            // Get column indices based on collection type
                            val idColumn = if (collectionName == "Downloads") {
                                it.getColumnIndexOrThrow(MediaStore.Downloads._ID)
                            } else {
                                it.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                            }
                            
                            val nameColumn = if (collectionName == "Downloads") {
                                it.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
                            } else {
                                it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                            }
                            
                            val sizeColumn = if (collectionName == "Downloads") {
                                it.getColumnIndexOrThrow(MediaStore.Downloads.SIZE)
                            } else {
                                it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                            }
                            
                            val dateColumn = if (collectionName == "Downloads") {
                                it.getColumnIndexOrThrow(MediaStore.Downloads.DATE_MODIFIED)
                            } else {
                                it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                            }
                            
                            // RELATIVE_PATH column (Android 10+)
                            var relativePathColumn = -1
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                relativePathColumn = if (collectionName == "Downloads") {
                                    it.getColumnIndex(MediaStore.Downloads.RELATIVE_PATH)
                                } else {
                                    it.getColumnIndex(MediaStore.Files.FileColumns.RELATIVE_PATH)
                                }
                            }
                            
                            // Process all results
                            var duplicatesSkipped = 0
                            while (it.moveToNext()) {
                                try {
                                    val id = it.getLong(idColumn)
                                    val name = it.getString(nameColumn) ?: "Unknown.pdf"
                                    val size = it.getLong(sizeColumn)
                                    val dateModified = it.getLong(dateColumn) * 1000 // Convert to milliseconds
                                    
                                    // Double-check it's a PDF (filter by extension if MIME type wasn't set)
                                    val nameLower = name.lowercase()
                                    if (!nameLower.endsWith(".pdf")) {
                                        continue // Skip non-PDF files
                                    }
                                    
                                    // Create content URI
                                    val contentUri = ContentUris.withAppendedId(uri, id)
                                    val filePath = contentUri.toString()
                                    
                                    // Deduplicate by URI
                                    if (seenUris.contains(filePath)) {
                                        duplicatesSkipped++
                                        continue
                                    }
                                    seenUris.add(filePath)
                                    
                                    // Extract folder info
                                    val folderPath: String
                                    val folderName: String
                                    
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && relativePathColumn >= 0) {
                                        val relativePath = it.getString(relativePathColumn) ?: ""
                                        if (relativePath.isNotEmpty()) {
                                            folderPath = relativePath.trimEnd('/')
                                            folderName = when {
                                                relativePath.contains("Download", ignoreCase = true) -> "Downloads"
                                                relativePath.contains("Document", ignoreCase = true) -> "Documents"
                                                else -> {
                                                    val parts = relativePath.split("/")
                                                    parts.lastOrNull()?.takeIf { it.isNotEmpty() } ?: "Unknown"
                                                }
                                            }
                                        } else {
                                            folderPath = collectionName
                                            folderName = collectionName
                                        }
                                    } else {
                                        folderPath = collectionName
                                        folderName = collectionName
                                    }
                                    
                                    // Add PDF
                                    pdfList.add(mapOf(
                                        "path" to filePath,
                                        "name" to name,
                                        "size" to size,
                                        "dateModified" to dateModified,
                                        "isContentUri" to true,
                                        "folderPath" to folderPath,
                                        "folderName" to folderName
                                    ))
                                    collectionCount++
                                    
                                    // Log progress every 100 PDFs
                                    if (collectionCount % 100 == 0) {
                                        android.util.Log.d("PDFScan", "$collectionName: Processed $collectionCount PDFs...")
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("PDFScan", "Error processing $collectionName row", e)
                                }
                            }
                            
                            collectionCounts[collectionName] = collectionCount
                            android.util.Log.d("PDFScan", "$collectionName: Found $collectionCount PDFs (duplicates skipped: $duplicatesSkipped)")
                            
                        } catch (e: Exception) {
                            android.util.Log.e("PDFScan", "Error processing $collectionName cursor", e)
                            e.printStackTrace()
                        }
                    } ?: android.util.Log.w("PDFScan", "$collectionName: Cursor is null")
                    
                } catch (e: Exception) {
                    android.util.Log.e("PDFScan", "Error querying $collectionName collection", e)
                    e.printStackTrace()
                }
            }
            
            // Sort by date modified (newest first)
            pdfList.sortByDescending { it["dateModified"] as Long }
            
            // Log summary
            android.util.Log.d("PDFScan", "=== MediaStore Scan Summary ===")
            for ((collectionName, count) in collectionCounts) {
                android.util.Log.d("PDFScan", "$collectionName: $count PDFs")
            }
            android.util.Log.d("PDFScan", "Merged total: ${pdfList.size} PDFs")
            android.util.Log.d("PDFScan", "Deduplication: ${collectionCounts.values.sum() - pdfList.size} duplicates removed")
            
        } catch (e: Exception) {
            android.util.Log.e("PDFScan", "MediaStore scan error", e)
            e.printStackTrace()
        }
        
        android.util.Log.d("PDFScan", "=== MediaStore scan complete: ${pdfList.size} PDFs ===")
        return pdfList
    }
    
    @Suppress("DEPRECATION")
    private fun scanPDFsFromDirectories(): List<Map<String, Any>> {
        val pdfList = mutableListOf<Map<String, Any>>()
        val directories = mutableListOf<String>()
        
        // Check if we have MANAGE_EXTERNAL_STORAGE permission (root-level access)
        val hasManageStorage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            false
        }
        
        android.util.Log.d("PDFScan", "MANAGE_EXTERNAL_STORAGE granted: $hasManageStorage")
        
        // Get external storage root using Environment (works on all Android versions)
        val externalStorageDir = Environment.getExternalStorageDirectory()
        if (externalStorageDir != null && externalStorageDir.exists()) {
            android.util.Log.d("PDFScan", "External storage: ${externalStorageDir.absolutePath}")
            
            if (hasManageStorage) {
                // With MANAGE_EXTERNAL_STORAGE, we can scan the root directory directly
                android.util.Log.d("PDFScan", "Root-level access enabled - scanning entire storage")
                directories.add(externalStorageDir.absolutePath)
            } else {
                // Without root access, scan common directories only
                directories.add(File(externalStorageDir, "Download").absolutePath)
                directories.add(File(externalStorageDir, "Downloads").absolutePath) // Some devices use plural
                directories.add(File(externalStorageDir, "Documents").absolutePath)
                directories.add(File(externalStorageDir, "Document").absolutePath) // Some devices use singular
                directories.add(File(externalStorageDir, "DCIM").absolutePath)
                directories.add(File(externalStorageDir, "Pictures").absolutePath)
                directories.add(File(externalStorageDir, "Books").absolutePath) // Some devices have Books folder
            }
        }
        
        // Also try getExternalFilesDir approach - get the parent directory as File
        val externalFilesDir = getExternalFilesDir(null)?.parentFile
        if (externalFilesDir != null && externalFilesDir.exists()) {
            val parentPath = externalFilesDir.parent
            if (parentPath != null) {
                android.util.Log.d("PDFScan", "External files dir parent: $parentPath")
                val parentDir = File(parentPath)
                if (parentDir.exists()) {
                    directories.add(File(parentDir, "Download").absolutePath)
                    directories.add(File(parentDir, "Downloads").absolutePath)
                    directories.add(File(parentDir, "Documents").absolutePath)
                }
            }
        }
        
        // Standard storage paths (for devices that use emulated storage)
        directories.add("/storage/emulated/0/Download")
        directories.add("/storage/emulated/0/Downloads")
        directories.add("/storage/emulated/0/Documents")
        directories.add("/storage/emulated/0/Document")
        directories.add("/storage/emulated/0/DCIM")
        directories.add("/storage/emulated/0/Pictures")
        directories.add("/storage/emulated/0/Books")
        
        // Try alternative storage paths (for devices with SD cards or multiple storage)
        try {
            val storageDir = File("/storage")
            if (storageDir.exists() && storageDir.isDirectory) {
                val storageFiles = storageDir.listFiles()
                storageFiles?.forEach { storage ->
                    if (storage.isDirectory && storage.name != "emulated") {
                        directories.add(File(storage, "Download").absolutePath)
                        directories.add(File(storage, "Downloads").absolutePath)
                        directories.add(File(storage, "Documents").absolutePath)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        // Also scan app's PDF directory
        try {
            val appPdfDir = File(filesDir.parent, "PDFs")
            if (appPdfDir.exists()) {
                directories.add(appPdfDir.absolutePath)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        // Also try app documents directory
        try {
            val appDocDir = getExternalFilesDir(null)?.parentFile
            if (appDocDir != null) {
                val pdfDir = File(appDocDir, "PDFs")
                if (pdfDir.exists()) {
                    directories.add(pdfDir.absolutePath)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        // Scan all directories
        android.util.Log.d("PDFScan", "Scanning ${directories.size} directories...")
        for (dirPath in directories) {
            try {
                val dir = File(dirPath)
                if (dir.exists() && dir.isDirectory) {
                    android.util.Log.d("PDFScan", "Scanning directory: $dirPath")
                    if (dir.canRead()) {
                        // With MANAGE_EXTERNAL_STORAGE, scan with unlimited depth
                        // Without it, use depth 10 to scan deeper subfolders
                        val maxDepth = if (hasManageStorage) Int.MAX_VALUE else 10
                        scanDirectoryForPDFs(dir, pdfList, maxDepth = maxDepth)
                    } else {
                        android.util.Log.w("PDFScan", "Cannot read directory: $dirPath")
                    }
                } else {
                    android.util.Log.d("PDFScan", "Directory does not exist: $dirPath")
                }
            } catch (e: Exception) {
                android.util.Log.e("PDFScan", "Error scanning directory $dirPath", e)
                e.printStackTrace()
            }
        }
        
        android.util.Log.d("PDFScan", "Directory scan completed, found ${pdfList.size} PDFs")
        return pdfList
    }
    
    private fun scanDirectoryForPDFs(
        directory: File, 
        pdfList: MutableList<Map<String, Any>>, 
        currentDepth: Int = 0,
        maxDepth: Int = 10
    ) {
        // Limit recursion depth to avoid performance issues
        // With MANAGE_EXTERNAL_STORAGE, use unlimited depth (Int.MAX_VALUE)
        // Without it, use depth 10 to scan deeper subfolders
        if (maxDepth != Int.MAX_VALUE && currentDepth >= maxDepth) {
            android.util.Log.d("PDFScan", "Max depth reached at: ${directory.absolutePath} (depth: $currentDepth)")
            return
        }
        
        try {
            if (!directory.exists()) {
                android.util.Log.w("PDFScan", "Directory does not exist: ${directory.absolutePath}")
                return
            }
            
            if (!directory.canRead()) {
                android.util.Log.w("PDFScan", "Cannot read directory: ${directory.absolutePath} - permission denied, but will try alternative method")
                // Don't return early - let the code below try list() method as it might work even if canRead() returns false
            }
            
            val files = directory.listFiles()
            
            // If listFiles() returns null or empty array, try alternative method
            // This handles permission issues on Android 13+ where listFiles() may return empty
            if (files == null || files.isEmpty()) {
                android.util.Log.w("PDFScan", "listFiles() returned ${if (files == null) "null" else "empty array"} for: ${directory.absolutePath} - trying alternative method")
                // Try alternative method: list() and create File objects manually
                try {
                    val fileNames = directory.list()
                    if (fileNames != null && fileNames.isNotEmpty()) {
                        android.util.Log.d("PDFScan", "Using list() method, found ${fileNames.size} items")
                        var pdfCount = 0
                        var dirCount = 0
                        var fileCount = 0
                        
                        for (fileName in fileNames) {
                            try {
                                val file = File(directory, fileName)
                                if (file.exists() && file.isFile) {
                                    fileCount++
                                    if (fileName.lowercase().endsWith(".pdf")) {
                                        val fileSize = file.length()
                                        if (fileSize > 0) {
                                            pdfCount++
                        val folderPath = file.parent
                        val folderName = file.parentFile?.name ?: "Unknown"
                        
                        pdfList.add(mapOf(
                            "path" to file.absolutePath,
                            "name" to file.name,
                            "size" to fileSize,
                            "dateModified" to file.lastModified(),
                            "isContentUri" to false,
                            "folderPath" to folderPath,
                            "folderName" to folderName
                        ))
                                            android.util.Log.d("PDFScan", "✓ Found PDF (via list()): ${file.name} (${fileSize} bytes) at ${file.absolutePath}")
                                        }
                                    }
                                } else if (file.exists() && file.isDirectory) {
                                    dirCount++
                                    if (file.name != "Android" && 
                                        file.name != ".android_secure" && 
                                        !file.name.startsWith(".")) {
                                        // Recursively scan subdirectories
                                        scanDirectoryForPDFs(file, pdfList, currentDepth + 1, maxDepth)
                                    }
                                }
                            } catch (e: Exception) {
                                android.util.Log.w("PDFScan", "Error processing file from list(): $fileName", e)
                            }
                        }
                        
                        android.util.Log.d("PDFScan", "Directory ${directory.absolutePath} (via list()): found $pdfCount PDFs, $fileCount files total, $dirCount subdirectories")
                    } else {
                        android.util.Log.w("PDFScan", "list() also returned null or empty for: ${directory.absolutePath}")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("PDFScan", "Error using list() method: ${directory.absolutePath}", e)
                }
                return
            }
            
            android.util.Log.d("PDFScan", "Scanning ${files.size} items in: ${directory.absolutePath} (depth: $currentDepth)")
            
            var pdfCount = 0
            var dirCount = 0
            var fileCount = 0
            for (file in files) {
                try {
                    if (file.isDirectory) {
                        dirCount++
                        // Recursively scan subdirectories (skip system directories)
                        if (file.name != "Android" && 
                            file.name != ".android_secure" && 
                            !file.name.startsWith(".")) {
                            scanDirectoryForPDFs(file, pdfList, currentDepth + 1, maxDepth)
                        }
                    } else if (file.isFile) {
                        fileCount++
                        val fileName = file.name.lowercase()
                        // Check both .pdf extension and also check MIME type if possible
                        val isPDF = fileName.endsWith(".pdf") || 
                                   fileName.endsWith(".pdf ") || // Some files might have trailing space
                                   (file.name.contains("pdf", ignoreCase = true) && file.length() > 100) // PDFs are usually > 100 bytes
                        
                        if (isPDF) {
                            pdfCount++
                            try {
                                // Double-check it's actually a PDF by checking file size and name
                                val fileSize = file.length()
                                if (fileSize > 0) { // Valid PDF should have some content
                                    // Optional: Verify PDF header (first 4 bytes should be "%PDF")
                                    var isValidPDF = true
                                    try {
                                        if (fileSize >= 4) {
                                            val fis = java.io.FileInputStream(file)
                                            val header = ByteArray(4)
                                            val bytesRead = fis.read(header)
                                            fis.close()
                                            if (bytesRead == 4) {
                                                val headerStr = String(header)
                                                if (!headerStr.startsWith("%PDF")) {
                                                    android.util.Log.d("PDFScan", "File ${file.name} has .pdf extension but doesn't start with %PDF header (header: $headerStr)")
                                                    isValidPDF = false
                                                }
                                            }
                                        }
                                    } catch (e: Exception) {
                                        // If we can't read header, assume it's valid based on extension
                                        android.util.Log.d("PDFScan", "Could not verify PDF header for ${file.name}, assuming valid: ${e.message}")
                                    }
                                    
                                    if (isValidPDF) {
                        val folderPath = file.parent
                        val folderName = file.parentFile?.name ?: "Unknown"
                        
                        pdfList.add(mapOf(
                            "path" to file.absolutePath,
                            "name" to file.name,
                            "size" to fileSize,
                            "dateModified" to file.lastModified(),
                            "isContentUri" to false,
                            "folderPath" to folderPath,
                            "folderName" to folderName
                        ))
                                        android.util.Log.d("PDFScan", "✓ Found PDF: ${file.name} (${fileSize} bytes) at ${file.absolutePath}")
                                    }
                                } else {
                                    android.util.Log.w("PDFScan", "Skipping empty file: ${file.absolutePath}")
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("PDFScan", "Error adding PDF: ${file.absolutePath}", e)
                                e.printStackTrace()
                            }
                        }
                    }
                } catch (e: SecurityException) {
                    android.util.Log.w("PDFScan", "SecurityException accessing file: ${file.absolutePath}", e)
                } catch (e: Exception) {
                    android.util.Log.e("PDFScan", "Error processing file: ${file.absolutePath}", e)
                    // Continue with next file
                }
            }
            
            // Log summary for this directory
            if (fileCount > 0 || dirCount > 0) {
                android.util.Log.d("PDFScan", "Directory ${directory.absolutePath}: found $pdfCount PDFs, $fileCount files total, $dirCount subdirectories")
            }
            
            if (pdfCount > 0 || dirCount > 0) {
                android.util.Log.d("PDFScan", "Directory ${directory.absolutePath}: found $pdfCount PDFs, $dirCount subdirectories")
            }
        } catch (e: SecurityException) {
            android.util.Log.w("PDFScan", "SecurityException (permission denied) for: ${directory.absolutePath}")
        } catch (e: Exception) {
            android.util.Log.e("PDFScan", "Exception scanning directory: ${directory.absolutePath}", e)
            e.printStackTrace()
        }
    }

    private fun copyContentUriToCache(uri: Uri): String? {
        return try {
            val contentResolver = contentResolver
            val inputStream: InputStream? = contentResolver.openInputStream(uri)
            
            if (inputStream == null) return null
            
            // Get file name from URI
            var fileName = getFileName(uri)
            if (fileName == null || !fileName.endsWith(".pdf", ignoreCase = true)) {
                fileName = "document_${System.currentTimeMillis()}.pdf"
            }
            
            // Create cache directory
            val cacheDir = cacheDir
            val file = File(cacheDir, fileName)
            
            // Copy file to cache
            FileOutputStream(file).use { output ->
                inputStream.copyTo(output)
            }
            inputStream.close()
            
            file.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getFileName(uri: Uri): String? {
        var result: String? = null
        if (uri.scheme == "content") {
            val cursor: Cursor? = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        result = it.getString(nameIndex)
                    }
                }
            }
        }
        if (result == null) {
            result = uri.path
            val cut = result?.lastIndexOf('/')
            if (cut != -1) {
                result = result?.substring(cut!! + 1)
            }
        }
        return result
    }

    private fun requestStorageAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                // Request access to storage directory
                // Note: Some devices don't allow root folder access, so we'll let user choose
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    
                    // Try to set initial URI to Downloads folder (more likely to work than root)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            // Try Downloads folder first (most common location for PDFs)
                            val downloadsUri = Uri.parse("content://com.android.externalstorage.documents/tree/primary%3ADownload")
                            putExtra(DocumentsContract.EXTRA_INITIAL_URI, downloadsUri)
                            android.util.Log.d("PDFScan", "Setting initial URI to Downloads folder")
                        } catch (e: Exception) {
                            android.util.Log.d("PDFScan", "Could not set initial URI, user will select manually")
                        }
                    }
                }
                startActivityForResult(intent, SAF_REQUEST_CODE)
            } catch (e: Exception) {
                android.util.Log.e("PDFScan", "Error requesting storage access", e)
                pendingResult?.error("REQUEST_ERROR", "Failed to request storage access: ${e.message}", null)
                pendingResult = null
            }
        } else {
            pendingResult?.success(false)
            pendingResult = null
        }
    }
    
    private fun hasStorageAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val prefs = getSharedPreferences("pdf_editor_prefs", MODE_PRIVATE)
            val treeUri = prefs.getString("storage_tree_uri", null)
            if (treeUri != null) {
                try {
                    val uri = Uri.parse(treeUri)
                    contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    return true
                } catch (e: Exception) {
                    android.util.Log.w("PDFScan", "Stored URI no longer valid", e)
                    prefs.edit().remove("storage_tree_uri").apply()
                }
            }
        }
        return false
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == SAF_REQUEST_CODE) {
            if (resultCode == RESULT_OK && data != null) {
                val treeUri = data.data
                if (treeUri != null) {
                    try {
                        // Take persistent permission
                        contentResolver.takePersistableUriPermission(
                            treeUri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        )
                        
                        // Save URI for future use
                        val prefs = getSharedPreferences("pdf_editor_prefs", MODE_PRIVATE)
                        prefs.edit().putString("storage_tree_uri", treeUri.toString()).apply()
                        
                        android.util.Log.d("PDFScan", "Storage access granted: $treeUri")
                        pendingResult?.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("PDFScan", "Error taking persistent permission", e)
                        pendingResult?.error("PERMISSION_ERROR", "Failed to take permission: ${e.message}", null)
                    }
                } else {
                    pendingResult?.success(false)
                }
            } else {
                pendingResult?.success(false)
            }
            pendingResult = null
        }
    }
    
    private fun scanPDFsFromSAFUri(treeUri: Uri): List<Map<String, Any>> {
        val pdfList = mutableListOf<Map<String, Any>>()
        val rootTreeId = DocumentsContract.getTreeDocumentId(treeUri)
        
        // Get root folder name
        val rootFolderName = try {
            val treeDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootTreeId)
            val cursor = contentResolver.query(
                treeDocUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameCol = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    it.getString(nameCol) ?: "Unknown"
                } else {
                    "Unknown"
                }
            } ?: "Unknown"
        } catch (e: Exception) {
            "Unknown"
        }
        
        android.util.Log.d("PDFScan", "SAF: Scanning root folder: $rootFolderName (treeId: $rootTreeId)")
        
        // Recursively scan the folder with increased depth for root-level access
        scanSAFDirectoryRecursive(treeUri, rootTreeId, rootFolderName, pdfList, 0, 20)
        
        android.util.Log.d("PDFScan", "SAF: Total PDFs found: ${pdfList.size}")
        return pdfList
    }
    
    private fun scanSAFDirectoryRecursive(
        treeUri: Uri,
        documentId: String,
        folderName: String,
        pdfList: MutableList<Map<String, Any>>,
        currentDepth: Int,
        maxDepth: Int
    ) {
        if (currentDepth >= maxDepth) {
            android.util.Log.d("PDFScan", "SAF: Max depth reached at: $folderName")
            return
        }
        
        try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
            
            val cursor = contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_FLAGS
                ),
                null,
                null,
                null
            )
            
            cursor?.use {
                val idColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val sizeColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
                val dateColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                val mimeColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val flagsColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_FLAGS)
                
                var fileCount = 0
                var dirCount = 0
                
                while (it.moveToNext()) {
                    val childDocumentId = it.getString(idColumn)
                    val name = it.getString(nameColumn) ?: "Unknown"
                    val size = it.getLong(sizeColumn)
                    val dateModified = it.getLong(dateColumn)
                    val mimeType = it.getString(mimeColumn) ?: ""
                    val flags = it.getLong(flagsColumn)
                    
                    // Check if it's a directory - use multiple methods for better detection
                    val isDirectory = try {
                        // Method 1: Check flags
                        val hasDirFlags = (flags and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE.toLong()) != 0L ||
                                        (flags and DocumentsContract.Document.FLAG_DIR_PREFERS_GRID.toLong()) != 0L
                        
                        // Method 2: Check MIME type
                        val isDirMime = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                        
                        // Method 3: If size is 0 and no extension, likely a directory
                        val isLikelyDir = size == 0L && !name.contains(".")
                        
                        hasDirFlags || isDirMime || isLikelyDir
                    } catch (e: Exception) {
                        // Fallback: assume directory if MIME type is dir
                        mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                    }
                    
                    if (isDirectory) {
                        dirCount++
                        // Skip system directories that are unlikely to have PDFs
                        val skipDirs = listOf("Android", ".android_secure", ".thumbnails", "LOST.DIR", "cache", "Cache")
                        if (!skipDirs.contains(name) && !name.startsWith(".")) {
                            // Recursively scan subdirectories
                            android.util.Log.d("PDFScan", "SAF: Scanning subdirectory: $name (depth: ${currentDepth + 1})")
                            scanSAFDirectoryRecursive(treeUri, childDocumentId, name, pdfList, currentDepth + 1, maxDepth)
                        }
                    } else if (name.lowercase().endsWith(".pdf") || mimeType == "application/pdf") {
                        fileCount++
                        // Found a PDF file
                        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childDocumentId)
                        
                        pdfList.add(mapOf(
                            "path" to documentUri.toString(),
                            "name" to name,
                            "size" to size,
                            "dateModified" to dateModified,
                            "isContentUri" to true,
                            "folderPath" to folderName,
                            "folderName" to folderName
                        ))
                        android.util.Log.d("PDFScan", "SAF: Found PDF: $name in $folderName (${size} bytes)")
                    }
                }
                
                if (fileCount > 0 || dirCount > 0) {
                    android.util.Log.d("PDFScan", "SAF: Scanned $folderName - found $fileCount PDFs, $dirCount subdirectories")
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("PDFScan", "SAF: Error scanning directory $folderName", e)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
