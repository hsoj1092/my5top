package com.my5top.commute

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val safChannelName = "com.my5top.commute/saf_backup"
    private val notifChannelName = "com.my5top.commute/notifications"

    private var safChannel: MethodChannel? = null
    private var notifChannel: MethodChannel? = null
    private var pendingSafResult: MethodChannel.Result? = null
    private var pendingBackupBytes: ByteArray? = null
    private var pendingBackupFilePath: String? = null
    private var requestedNotifOnResume = false

    companion object {
        private const val REQUEST_CREATE_BACKUP = 9001
        private const val REQUEST_OPEN_BACKUP = 9002
        private const val REQUEST_PICK_DIRECTORY = 9003
        private const val REQUEST_NOTIF_PERMISSION = 9004
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            CommuteAlertHelper.ensureNotificationChannels(this)
        } catch (_: Throwable) {}
        try {
            CommuteForegroundService.onUiAttached(applicationContext)
        } catch (_: Throwable) {}

        val backupChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannelName)
        safChannel = backupChannel
        backupChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "createBackupDocument" -> {
                    val fileName = call.argument<String>("fileName") ?: "my5top_backup.json"
                    val sourceFilePath = call.argument<String>("sourceFilePath")
                    val content = call.argument<String>("content")
                    launchCreateBackupDocument(fileName, sourceFilePath, content, result)
                }
                "openBackupDocument" -> {
                    launchOpenBackupDocument(result)
                }
                "pickBackupDirectory" -> {
                    launchPickBackupDirectory(result)
                }
                "saveToDirectoryUri" -> {
                    val treeUriStr = call.argument<String>("treeUri") ?: ""
                    val fileName = call.argument<String>("fileName") ?: "my5top_backup.json"
                    val sourceFilePath = call.argument<String>("sourceFilePath")
                    val content = call.argument<String>("content")
                    saveToDirectoryUri(treeUriStr, fileName, sourceFilePath, content, result)
                }
                "getBackupDirectoryStats" -> {
                    val treeUriStr = call.argument<String>("treeUri") ?: ""
                    getBackupDirectoryStats(treeUriStr, result)
                }
                else -> result.notImplemented()
            }
        }

        val notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notifChannelName)
        notifChannel = notificationChannel
        notificationChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestPermission" -> {
                        requestNotificationPermission(result)
                    }
                    "showRideProgress" -> {
                        val title = call.argument<String>("title") ?: "Active Commute"
                        val body = call.argument<String>("body") ?: ""
                        val subText = call.argument<String>("subText") ?: "my5top"
                        val passedStops = call.argument<Int>("passedStops") ?: 0
                        val totalStops = call.argument<Int>("totalStops") ?: 1
                        CommuteAlertHelper.showRideProgressNotification(
                            this,
                            title,
                            body,
                            subText,
                            passedStops,
                            totalStops
                        )
                        result.success(true)
                    }
                    "cancelRideProgress" -> {
                        CommuteAlertHelper.cancelRideProgressNotification(this)
                        result.success(true)
                    }
                    "showAlert" -> {
                        val id = call.argument<Int>("id") ?: (System.currentTimeMillis() % 100000).toInt()
                        val type = call.argument<String>("type") ?: "stop"
                        val title = call.argument<String>("title") ?: "my5top Alert"
                        val body = call.argument<String>("body") ?: ""
                        val vibrate = call.argument<Boolean>("vibrate") ?: true
                        val headphoneAudioBypass = call.argument<Boolean>("headphoneAudioBypass") ?: true
                        CommuteAlertHelper.showCommuteAlertNotification(
                            this,
                            id,
                            type,
                            title,
                            body,
                            vibrate,
                            headphoneAudioBypass
                        )
                        result.success(true)
                    }
                    "startBackgroundGuard" -> {
                        val payloadJson = call.argument<String>("payloadJson") ?: ""
                        if (payloadJson.isNotBlank()) {
                            CommuteForegroundService.startOrUpdate(applicationContext, payloadJson)
                        }
                        result.success(true)
                    }
                    "stopBackgroundGuard" -> {
                        CommuteForegroundService.stopService(applicationContext)
                        result.success(true)
                    }
                    "syncBackgroundState" -> {
                        CommuteForegroundService.onUiAttached(applicationContext)
                        val updates = CommuteForegroundService.consumeBackgroundUpdates(applicationContext)
                        result.success(updates)
                    }
                    "moveToBackground" -> {
                        val moved = moveTaskToBack(true)
                        result.success(moved)
                    }
                    "isHeadphonesConnected" -> {
                        result.success(CommuteAlertHelper.isHeadphonesConnected(this))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                try {
                    result.error("NOTIF_CHANNEL_ERROR", e.message, null)
                } catch (_: Throwable) {}
            }
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        try {
            CommuteForegroundService.onUiAttached(applicationContext)
        } catch (_: Throwable) {}
        if (!requestedNotifOnResume) {
            requestedNotifOnResume = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val perm = "android.permission.POST_NOTIFICATIONS"
                if (checkSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) {
                    window?.decorView?.postDelayed({
                        try {
                            if (checkSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(perm), REQUEST_NOTIF_PERMISSION)
                            }
                        } catch (_: Throwable) {}
                    }, 500)
                }
            }
        }
    }

    override fun onStop() {
        try {
            CommuteForegroundService.onUiDetached(applicationContext)
        } catch (_: Throwable) {}
        super.onStop()
    }

    override fun onDestroy() {
        try {
            CommuteForegroundService.onUiDetached(applicationContext)
        } catch (_: Throwable) {}
        super.onDestroy()
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val perm = "android.permission.POST_NOTIFICATIONS"
            if (checkSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(perm), REQUEST_NOTIF_PERMISSION)
            }
        }
        result.success(true)
    }


    private fun launchCreateBackupDocument(
        fileName: String,
        sourceFilePath: String?,
        content: String?,
        result: MethodChannel.Result
    ) {
        try {
            pendingSafResult = result
            pendingBackupFilePath = sourceFilePath
            pendingBackupBytes = content?.toByteArray(Charsets.UTF_8)
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            startActivityForResult(intent, REQUEST_CREATE_BACKUP)
        } catch (e: Throwable) {
            pendingSafResult = null
            pendingBackupFilePath = null
            pendingBackupBytes = null
            result.error("SAF_CREATE_ERROR", e.message, null)
        }
    }

    private fun launchOpenBackupDocument(result: MethodChannel.Result) {
        try {
            pendingSafResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("application/json", "text/plain", "application/octet-stream")
                )
            }
            startActivityForResult(intent, REQUEST_OPEN_BACKUP)
        } catch (e: Throwable) {
            pendingSafResult = null
            result.error("SAF_OPEN_ERROR", e.message, null)
        }
    }

    private fun launchPickBackupDirectory(result: MethodChannel.Result) {
        try {
            pendingSafResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                )
            }
            startActivityForResult(intent, REQUEST_PICK_DIRECTORY)
        } catch (e: Throwable) {
            pendingSafResult = null
            result.error("SAF_DIR_ERROR", e.message, null)
        }
    }

    private fun saveToDirectoryUri(
        treeUriStr: String,
        fileName: String,
        sourceFilePath: String?,
        content: String?,
        result: MethodChannel.Result
    ) {
        try {
            val treeUri = Uri.parse(treeUriStr)
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val parentDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
            val newDocUri = DocumentsContract.createDocument(
                contentResolver,
                parentDocUri,
                "application/json",
                fileName
            ) ?: throw Exception("Failed to create document in selected folder")

            contentResolver.openOutputStream(newDocUri)?.use { out ->
                val srcFile = if (!sourceFilePath.isNullOrBlank()) File(sourceFilePath) else null
                if (srcFile != null && srcFile.exists()) {
                    srcFile.inputStream().use { input ->
                        input.copyTo(out)
                    }
                } else if (content != null) {
                    out.write(content.toByteArray(Charsets.UTF_8))
                }
                out.flush()
            }
            result.success(
                mapOf(
                    "success" to true,
                    "uri" to newDocUri.toString(),
                    "displayName" to fileName
                )
            )
        } catch (e: Throwable) {
            result.error("SAF_WRITE_DIR_ERROR", e.message, null)
        }
    }

    private fun getBackupDirectoryStats(treeUriStr: String, result: MethodChannel.Result) {
        if (treeUriStr.isBlank()) {
            result.success(mapOf("success" to false, "fileCount" to 0, "totalBytes" to 0L))
            return
        }
        try {
            val treeUri = Uri.parse(treeUriStr)
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
            var fileCount = 0
            var totalBytes = 0L

            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            )

            contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val sizeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                val mimeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

                while (cursor.moveToNext()) {
                    val name = if (nameIdx >= 0) cursor.getString(nameIdx) ?: "" else ""
                    val mime = if (mimeIdx >= 0) cursor.getString(mimeIdx) ?: "" else ""
                    val size = if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) cursor.getLong(sizeIdx) else 0L

                    if (mime != DocumentsContract.Document.MIME_TYPE_DIR &&
                        (name.endsWith(".json", ignoreCase = true) || name.contains("my5top", ignoreCase = true))
                    ) {
                        fileCount++
                        if (size > 0L) {
                            totalBytes += size
                        }
                    }
                }
            }

            result.success(
                mapOf(
                    "success" to true,
                    "fileCount" to fileCount,
                    "totalBytes" to totalBytes
                )
            )
        } catch (e: Throwable) {
            result.success(
                mapOf(
                    "success" to false,
                    "fileCount" to 0,
                    "totalBytes" to 0L,
                    "error" to (e.message ?: "")
                )
            )
        }
    }

    private fun resolveDisplayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val name = cursor.getString(idx)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
        } catch (_: Throwable) {}
        return uri.lastPathSegment ?: uri.toString()
    }

    private fun formatTreeUriDisplay(uri: Uri): String {
        val raw = Uri.decode(uri.toString())
        return when {
            raw.contains("primary:") -> "Internal Storage / " + raw.substringAfter("primary:")
            raw.contains("com.google.android.apps.docs") -> "Google Drive / Selected Folder"
            raw.contains("document/") -> raw.substringAfter("document/").replace(":", " / ")
            raw.contains("tree/") -> raw.substringAfter("tree/").replace(":", " / ")
            else -> raw
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_CREATE_BACKUP) {
            val callback = pendingSafResult
            val srcPath = pendingBackupFilePath
            val bytes = pendingBackupBytes
            pendingSafResult = null
            pendingBackupFilePath = null
            pendingBackupBytes = null
            if (callback == null) return

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    val uri = data.data!!
                    val stream = contentResolver.openOutputStream(uri, "wt")
                        ?: contentResolver.openOutputStream(uri)
                        ?: throw Exception("Unable to open destination output stream")
                    stream.use { out ->
                        val srcFile = if (!srcPath.isNullOrBlank()) File(srcPath) else null
                        if (srcFile != null && srcFile.exists()) {
                            srcFile.inputStream().use { input ->
                                input.copyTo(out)
                            }
                        } else if (bytes != null) {
                            out.write(bytes)
                        }
                        out.flush()
                    }
                    val displayName = resolveDisplayName(uri)
                    callback.success(
                        mapOf(
                            "success" to true,
                            "uri" to uri.toString(),
                            "displayName" to displayName
                        )
                    )
                } catch (e: Throwable) {
                    callback.error("SAF_WRITE_ERROR", e.message, null)
                }
            } else {
                callback.success(mapOf("cancelled" to true))
            }
        } else if (requestCode == REQUEST_OPEN_BACKUP) {
            val callback = pendingSafResult
            pendingSafResult = null
            if (callback == null) return

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    val uri = data.data!!
                    val tempFile = File(cacheDir, "saf_restored_backup.json")
                    contentResolver.openInputStream(uri)?.use { input ->
                        tempFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    } ?: throw Exception("Unable to read selected backup file")
                    val displayName = resolveDisplayName(uri)
                    callback.success(
                        mapOf(
                            "success" to true,
                            "tempFilePath" to tempFile.absolutePath,
                            "uri" to uri.toString(),
                            "displayName" to displayName
                        )
                    )
                } catch (e: Throwable) {
                    callback.error("SAF_READ_ERROR", e.message, null)
                }
            } else {
                callback.success(mapOf("cancelled" to true))
            }
        } else if (requestCode == REQUEST_PICK_DIRECTORY) {
            val callback = pendingSafResult
            pendingSafResult = null
            if (callback == null) return

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    val treeUri = data.data!!
                    val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    try {
                        contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                    } catch (_: Throwable) {}
                    val display = formatTreeUriDisplay(treeUri)
                    callback.success(
                        mapOf(
                            "success" to true,
                            "uri" to treeUri.toString(),
                            "displayName" to display
                        )
                    )
                } catch (e: Throwable) {
                    callback.error("SAF_TREE_ERROR", e.message, null)
                }
            } else {
                callback.success(mapOf("cancelled" to true))
            }
        }
    }
}
