package software.doable.doable

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.FileInputStream
import java.util.concurrent.Executor

/**
 * Документы вне каталога приложения через системные диалоги Storage Access
 * Framework без разрешений и без `FileProvider` (ADR-0037).
 *
 * Канал создаёт документ диалогом `ACTION_CREATE_DOCUMENT` и копирует в него
 * временный файл приложения потоками `ContentResolver` в [copyExecutor]; байты
 * через канал не передаются. Контракт канала задаёт
 * `lib/src/data_transfer/data/method_channel_document_access.dart`.
 *
 * Временное право на документ Android снимает вместе с Activity, получившей
 * ответ диалога, а движок при смене дисплея переносится в другую Activity
 * (ADR-0031). Поэтому право записи закрепляется при ответе диалога и
 * отпускается на шаге завершения работы с документом.
 */
class DocumentAccessPlugin internal constructor(
    private val copyExecutor: Executor,
) : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
    constructor() : this(Executor { Thread(it, "DocumentAccessCopy").start() })

    private lateinit var channel: MethodChannel
    private lateinit var contentResolver: ContentResolver
    private var activityBinding: ActivityPluginBinding? = null

    /** Ответ на создание документа, пока диалог ожидает выбора места. */
    private var pendingCreation: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        contentResolver = binding.applicationContext.contentResolver
        // Постоянных прав на документы приложение не хранит: закреплённые права
        // остались от процесса, завершённого посреди операции с документом.
        contentResolver.persistedUriPermissions.map { it.uri }.forEach(::releaseGrant)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(::onMethodCall)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        binding.addActivityResultListener(this)
        activityBinding = binding
    }

    // Пересоздание при смене конфигурации сохраняет запись Activity, и система
    // доставляет ответ диалога новому экземпляру, поэтому ожидающий запрос остаётся.
    // https://api.flutter.dev/javadoc/io/flutter/embedding/engine/plugins/activity/ActivityAware.html#onDetachedFromActivityForConfigChanges()
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    // Ответ диалога получит уже отсоединённая Activity, например при переносе
    // движка в другую Activity, поэтому ожидающий запрос завершается как отмена.
    override fun onDetachedFromActivity() {
        detachActivity()
        pendingCreation?.success(null)
        pendingCreation = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CREATE_DOCUMENT_REQUEST) return false
        val result = pendingCreation ?: return false
        pendingCreation = null
        val document = data?.data?.takeIf { resultCode == Activity.RESULT_OK }
        // Право закрепляется, пока жива Activity, получившая ответ.
        document?.let(::takeWriteGrant)
        result.success(document?.toString())
        return true
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createDocument" -> createDocument(requireNotNull(call.argument<String>("name")), result)
            "writeDocument" -> writeDocument(
                source = requireNotNull(call.argument<String>("source")),
                document = Uri.parse(requireNotNull(call.argument<String>("document"))),
                result = result,
            )
            "finishDocument" -> {
                releaseGrant(Uri.parse(requireNotNull(call.argument<String>("document"))))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun createDocument(name: String, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        // Второй диалог не открывается, пока первый ожидает ответа.
        if (activity == null || pendingCreation != null) {
            result.error(DIALOG_UNAVAILABLE, null, null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(DOCUMENT_TYPE)
            .putExtra(Intent.EXTRA_TITLE, name)
        try {
            activity.startActivityForResult(intent, CREATE_DOCUMENT_REQUEST)
        } catch (error: ActivityNotFoundException) {
            result.error(DIALOG_UNAVAILABLE, null, null)
            return
        }
        pendingCreation = result
    }

    private fun writeDocument(source: String, document: Uri, result: MethodChannel.Result) {
        copyExecutor.execute {
            // Исключение в собственном потоке завершило бы процесс, поэтому любой
            // отказ поставщика документа становится отказом записи. Текст
            // исключения не передаётся: он может содержать адрес документа.
            val written = try {
                FileInputStream(source).use { input ->
                    // Поставщик, который недавно аварийно завершился, не возвращает поток.
                    val output = checkNotNull(contentResolver.openOutputStream(document))
                    output.use { input.copyTo(it) }
                }
                true
            } catch (error: Exception) {
                false
            }
            if (written) result.success(null) else result.error(DOCUMENT_NOT_WRITTEN, null, null)
        }
    }

    private fun takeWriteGrant(document: Uri) {
        try {
            contentResolver.takePersistableUriPermission(document, Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        } catch (error: SecurityException) {
            // Поставщик не дал закрепляемого права: копирование идёт с временным.
        }
    }

    /** Отпускает закреплённое право на [document] в любых режимах, если оно есть. */
    private fun releaseGrant(document: Uri) {
        try {
            contentResolver.releasePersistableUriPermission(
                document,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (error: SecurityException) {
            // Права нет: поставщик не дал закрепляемого права.
        }
    }

    private companion object {
        const val CHANNEL = "software.doable.doable/document_access"
        const val DOCUMENT_TYPE = "application/gzip"
        const val CREATE_DOCUMENT_REQUEST = 0x0d0c
        const val DIALOG_UNAVAILABLE = "dialog_unavailable"
        const val DOCUMENT_NOT_WRITTEN = "document_not_written"
    }
}
