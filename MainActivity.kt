package com.example.saf_test  // change to your app's package

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "saf_test")
            .setMethodCallHandler { call, result ->
                if (call.method == "pick") {
                    pending = result
                    val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*" // some providers tag mkv/avi oddly, so don't filter
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                 Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                    startActivityForResult(i, 42)
                } else result.notImplemented()
            }
    }

    override fun onActivityResult(req: Int, code: Int, data: Intent?) {
        super.onActivityResult(req, code, data)
        if (req != 42) return
        val result = pending ?: return
        pending = null
        val uri: Uri? = data?.data
        if (code != Activity.RESULT_OK || uri == null) { result.success(null); return }
        try {
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val fd = contentResolver.openFileDescriptor(uri, "r")!!.detachFd()
            var name = uri.lastPathSegment ?: "video"
            contentResolver.query(uri, null, null, null, null)?.use {
                if (it.moveToFirst()) {
                    val c = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (c >= 0) name = it.getString(c)
                }
            }
            result.success(mapOf("fd" to fd, "name" to name, "uri" to uri.toString()))
        } catch (e: Exception) {
            result.error("open_failed", e.toString(), null)
        }
    }
}
