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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
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
