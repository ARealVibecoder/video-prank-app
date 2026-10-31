package com.example.saf_test

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val exts = setOf("mp4", "mkv", "mov", "avi", "webm", "m4v", "wmv", "flv", "mpg", "mpeg", "3gp", "ts")

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "saf_test")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> {
                        pending = result
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                            )
                        }
                        startActivityForResult(i, 43)
                    }
                    "scan" -> {
                        val uri = Uri.parse(call.argument<String>("uri")!!)
                        Thread {
                            try {
                                val out = ArrayList<Map<String, Any>>()
                                walk(uri, DocumentsContract.getTreeDocumentId(uri), out, 0)
                                runOnUiThread { result.success(out) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("scan_failed", e.toString(), null) }
                            }
                        }.start()
                    }
                    "openFd" -> {
                        try {
                            val u = Uri.parse(call.argument<String>("uri")!!)
                            val fd = contentResolver.openFileDescriptor(u, "r")!!.detachFd()
                            result.success(fd)
                        } catch (e: Exception) {
                            result.error("open_failed", e.toString(), null)
                        }
                    }
                    "dataDir" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }

    private fun walk(tree: Uri, docId: String, out: MutableList<Map<String, Any>>, depth: Int) {
        if (depth > 6) return
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
        val cols = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE
        )
        contentResolver.query(children, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0)
                val name = c.getString(1) ?: ""
                val mime = c.getString(2) ?: ""
                val size = if (c.isNull(3)) 0L else c.getLong(3)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    walk(tree, id, out, depth + 1)
                } else {
                    val ext = name.substringAfterLast('.', "").lowercase()
                    if (mime.startsWith("video/") || ext in exts) {
                        out.add(
                            mapOf(
                                "name" to name,
                                "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                                "size" to size
                            )
                        )
                    }
                }
            }
        }
    }

    override fun onActivityResult(req: Int, code: Int, data: Intent?) {
        super.onActivityResult(req, code, data)
        if (req != 43) return
        val result = pending ?: return
        pending = null
        val uri: Uri? = data?.data
        if (code != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("pick_failed", e.toString(), null)
        }
    }
}
