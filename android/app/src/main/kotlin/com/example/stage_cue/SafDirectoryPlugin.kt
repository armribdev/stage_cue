package com.example.stage_cue

import android.accounts.AccountManager
import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

class SafDirectoryPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPickResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
        pendingPickResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> pickDirectory(result)
            "getTreeInfo" -> {
                val treeUri = call.argument<String>("treeUri")
                if (treeUri.isNullOrEmpty()) {
                    result.error("invalid_args", "treeUri requis", null)
                } else {
                    result.success(getTreeInfo(Uri.parse(treeUri)))
                }
            }
            "listAudioFiles" -> {
                val treeUri = call.argument<String>("treeUri")
                if (treeUri.isNullOrEmpty()) {
                    result.error("invalid_args", "treeUri requis", null)
                } else {
                    try {
                        result.success(listAudioFiles(Uri.parse(treeUri)))
                    } catch (e: Exception) {
                        result.error("list_failed", e.message, null)
                    }
                }
            }
            "copyToFile" -> {
                val documentUri = call.argument<String>("documentUri")
                val destinationPath = call.argument<String>("destinationPath")
                if (documentUri.isNullOrEmpty() || destinationPath.isNullOrEmpty()) {
                    result.error("invalid_args", "Arguments requis", null)
                } else {
                    try {
                        copyToFile(Uri.parse(documentUri), destinationPath)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("copy_failed", e.message, null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE_REQUEST_CODE) {
            return false
        }

        val result = pendingPickResult
        pendingPickResult = null

        if (result == null) {
            return true
        }

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }

        val treeUri = data.data!!
        val resolver = activity?.contentResolver
        if (resolver != null) {
            try {
                resolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // Certaines sources cloud ne supportent pas la permission persistante.
            }
        }

        result.success(buildPickResult(treeUri))
        return true
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("no_activity", "Activity indisponible", null)
            return
        }

        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
        }
        currentActivity.startActivityForResult(intent, PICK_TREE_REQUEST_CODE)
    }

    private fun buildPickResult(treeUri: Uri): String {
        val info = treeInfoJson(treeUri)
        info.put("uri", treeUri.toString())
        info.put("googleAccountEmails", JSONArray(listGoogleAccountEmails()))
        return info.toString()
    }

    private fun getTreeInfo(treeUri: Uri): String = treeInfoJson(treeUri).toString()

    private fun treeInfoJson(treeUri: Uri): JSONObject {
        val displayName = getTreeDisplayName(treeUri) ?: "Dossier"
        return JSONObject()
            .put("displayName", displayName)
            .put("displayPath", formatFolderPath(treeUri, displayName))
            .put("driveFileId", extractDriveFileId(treeUri))
            .put("isGoogleDrive", isGoogleDriveUri(treeUri))
    }

    private fun isGoogleDriveUri(treeUri: Uri): Boolean {
        return when (treeUri.authority) {
            "com.google.android.apps.docs.storage",
            "com.google.android.apps.docs" -> true
            else -> false
        }
    }

    private fun listGoogleAccountEmails(): List<String> {
        val currentActivity = activity ?: return emptyList()
        val accountManager = AccountManager.get(currentActivity)
        return accountManager.getAccountsByType("com.google")
            .mapNotNull { account ->
                account.name?.takeIf { it.contains("@") }
            }
            .distinct()
    }

    private fun getTreeDisplayName(treeUri: Uri): String? {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        return queryDisplayName(documentUri)
    }

    private fun formatFolderPath(treeUri: Uri, displayName: String): String {
        val treeId = DocumentsContract.getTreeDocumentId(treeUri)

        if (treeId.contains(":")) {
            val pathPart = treeId.substringAfter(':')
            if (pathPart.isNotEmpty() && pathPart.contains("/")) {
                return pathPart
                    .split("/")
                    .filter { it.isNotEmpty() }
                    .joinToString("/")
            }
        }

        return displayName
    }

    /// Extrait l'identifiant fichier Drive quand l'ID SAF l'expose (sans slash).
    private fun extractDriveFileId(treeUri: Uri): String? {
        if (!isGoogleDriveUri(treeUri)) {
            return null
        }

        val treeId = DocumentsContract.getTreeDocumentId(treeUri)
        if (!treeId.contains(":")) {
            return treeId.takeIf { looksLikeDriveFileId(it) }
        }

        val afterColon = treeId.substringAfter(':')
        if (afterColon.contains("/")) {
            return null
        }

        return afterColon.takeIf { looksLikeDriveFileId(it) }
    }

    private fun looksLikeDriveFileId(value: String): Boolean {
        return value.length >= 10 &&
            value.all { it.isLetterOrDigit() || it == '-' || it == '_' }
    }

    private fun queryDisplayName(documentUri: Uri): String? {
        val resolver = activity?.contentResolver ?: return null
        safeQuery(
            resolver,
            documentUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index =
                    cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                if (index >= 0) {
                    return cursor.getString(index)
                }
            }
        }
        return null
    }

    private fun safeQuery(
        resolver: ContentResolver,
        uri: Uri,
        projection: Array<String>? = null,
    ) = try {
        resolver.query(uri, projection, null, null, null)
    } catch (_: SecurityException) {
        null
    }

    private fun listAudioFiles(treeUri: Uri): String {
        val results = JSONArray()
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        walkTree(treeUri, rootId, "", results)
        return results.toString()
    }

    private fun walkTree(
        treeUri: Uri,
        documentId: String,
        relativePrefix: String,
        results: JSONArray,
    ) {
        val resolver = activity?.contentResolver ?: return
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        resolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

            while (cursor.moveToNext()) {
                val childId = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex) ?: continue
                val mimeType = cursor.getString(mimeIndex) ?: continue

                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val childPrefix = if (relativePrefix.isEmpty()) {
                        name
                    } else {
                        "$relativePrefix/$name"
                    }
                    walkTree(treeUri, childId, childPrefix, results)
                } else if (isAudioFileName(name)) {
                    val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                    val relativePath = if (relativePrefix.isEmpty()) {
                        name
                    } else {
                        "$relativePrefix/$name"
                    }
                    results.put(
                        JSONObject()
                            .put("uri", documentUri.toString())
                            .put("name", name)
                            .put("relativePath", relativePath),
                    )
                }
            }
        }
    }

    private fun isAudioFileName(name: String): Boolean {
        val extension = name.substringAfterLast('.', "").lowercase()
        return extension in AUDIO_EXTENSIONS
    }

    private fun copyToFile(documentUri: Uri, destinationPath: String) {
        val resolver = activity?.contentResolver
            ?: throw IllegalStateException("ContentResolver indisponible")
        val destination = File(destinationPath)
        destination.parentFile?.mkdirs()
        resolver.openInputStream(documentUri)?.use { input ->
            FileOutputStream(destination).use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Impossible d'ouvrir le document")
    }

    companion object {
        private const val CHANNEL_NAME = "stage_cue/saf"
        private const val PICK_TREE_REQUEST_CODE = 7401
        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "wav", "m4a", "aac", "ogg", "flac", "wma", "opus",
        )
    }
}
