package com.example.pdf_editor_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.content.ContentUris
import android.database.Cursor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.content.ContentResolver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.pdf_editor_app/file_intent"
    private val PDF_SCAN_CHANNEL = "com.example.pdf_editor_app/pdf_scan"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Channel for file intent handling
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialFileIntent") {
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
            } else {
                result.notImplemented()
            }
        }
        
        // Channel for PDF scanning
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_SCAN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanPDFs" -> {
                    try {
                        val pdfList = scanAllPDFs()
                        result.success(pdfList)
                    } catch (e: Exception) {
                        result.error("SCAN_ERROR", "Failed to scan PDFs: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun scanAllPDFs(): List<Map<String, Any>> {
        val pdfList = mutableListOf<Map<String, Any>>()
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Use MediaStore for Android 10+ (API 29+)
                pdfList.addAll(scanPDFsWithMediaStore())
            } else {
                // Use directory scanning for older versions
                pdfList.addAll(scanPDFsFromDirectories())
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return pdfList
    }
    
    @Suppress("DEPRECATION")
    private fun scanPDFsWithMediaStore(): List<Map<String, Any>> {
        val pdfList = mutableListOf<Map<String, Any>>()
        val contentResolver = contentResolver
        
        // Query MediaStore for PDF files
        val uri = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.DATA
        )
        
        val selection = "${MediaStore.Files.FileColumns.MIME_TYPE} = ?"
        val selectionArgs = arrayOf("application/pdf")
        val sortOrder = "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
        
        val cursor: Cursor? = contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
        
        cursor?.use {
            val idColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            val nameColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
            val sizeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
            val dateColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
            val dataColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
            
            while (it.moveToNext()) {
                try {
                    val id = it.getLong(idColumn)
                    val name = it.getString(nameColumn)
                    val size = it.getLong(sizeColumn)
                    val dateModified = it.getLong(dateColumn) * 1000 // Convert to milliseconds
                    val data = it.getString(dataColumn)
                    
                    // Get file path - try DATA column first, fallback to URI
                    var filePath = data
                    if (filePath.isNullOrEmpty()) {
                        val contentUri = ContentUris.withAppendedId(uri, id)
                        filePath = contentUri.toString()
                    }
                    
                    // Verify file exists
                    if (!filePath.isNullOrEmpty()) {
                        val file = File(filePath)
                        if (file.exists() && file.canRead()) {
                            pdfList.add(mapOf(
                                "path" to filePath,
                                "name" to name,
                                "size" to size,
                                "dateModified" to dateModified
                            ))
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                    // Continue with next file
                }
            }
        }
        
        return pdfList
    }
    
    @Suppress("DEPRECATION")
    private fun scanPDFsFromDirectories(): List<Map<String, Any>> {
        val pdfList = mutableListOf<Map<String, Any>>()
        val directories = mutableListOf<String>()
        
        // Common directories to scan
        val externalStorage = getExternalFilesDir(null)?.parentFile?.parent
        if (externalStorage != null) {
            directories.add(File(externalStorage, "Download").absolutePath)
            directories.add(File(externalStorage, "Documents").absolutePath)
            directories.add(File(externalStorage, "DCIM").absolutePath)
            directories.add("/storage/emulated/0/Download")
            directories.add("/storage/emulated/0/Documents")
        }
        
        // Also scan app's PDF directory
        val appPdfDir = File(filesDir.parent, "PDFs")
        if (appPdfDir.exists()) {
            directories.add(appPdfDir.absolutePath)
        }
        
        for (dirPath in directories) {
            try {
                val dir = File(dirPath)
                if (dir.exists() && dir.isDirectory) {
                    scanDirectoryForPDFs(dir, pdfList)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        
        return pdfList
    }
    
    private fun scanDirectoryForPDFs(directory: File, pdfList: MutableList<Map<String, Any>>) {
        try {
            val files = directory.listFiles()
            if (files != null) {
                for (file in files) {
                    if (file.isDirectory) {
                        // Recursively scan subdirectories (limit depth to avoid performance issues)
                        if (file.name != "Android" && file.name != ".android_secure") {
                            scanDirectoryForPDFs(file, pdfList)
                        }
                    } else if (file.isFile && file.name.lowercase().endsWith(".pdf")) {
                        try {
                            pdfList.add(mapOf(
                                "path" to file.absolutePath,
                                "name" to file.name,
                                "size" to file.length(),
                                "dateModified" to file.lastModified()
                            ))
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                }
            }
        } catch (e: Exception) {
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
