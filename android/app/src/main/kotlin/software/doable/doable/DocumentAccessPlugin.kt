package software.doable.doable

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.system.ErrnoException
import android.system.OsConstants
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicReference

/**
 * Документы вне каталога приложения через системные диалоги Storage Access
 * Framework без разрешений и без `FileProvider` (ADR-0037).
 *
 * Канал создаёт документ диалогом `ACTION_CREATE_DOCUMENT` и копирует в него
 * временный файл приложения, а документ, открытый диалогом
 * `ACTION_OPEN_DOCUMENT`, копирует в файл приложения. Копирование идёт
 * потоками `ContentResolver` в [backgroundExecutor]; байты через канал не
 * передаются. Контракт канала задаёт
 * `lib/src/data_transfer/data/method_channel_document_access.dart`.
 *
 * Временное право на документ Android снимает вместе с Activity, получившей
 * ответ диалога, а движок при смене дисплея переносится в другую Activity
 * (ADR-0031). Поэтому право закрепляется при ответе диалога. Право записи
 * отпускается на шаге завершения работы с документом; после отказа операции
 * этот шаг сначала удаляет документ: удалению нужно это право. Право чтения
 * отпускается, когда закончено копирование открытого документа.
 *
 * Диалог позволяет выбрать и существующий файл, подтвердив его замену, и
 * возвращает его так же, как созданный документ. Поэтому перед ответом в Dart
 * плагин запрашивает размер документа у поставщика: файл с данными экспорт не
 * перезаписывает, а после отказа удаляется только документ, пустой при выборе.
 */
class DocumentAccessPlugin internal constructor(
    private val backgroundExecutor: Executor,
    /** Открывает для записи файл копии открытого документа. */
    private val openCopy: (File) -> OutputStream,
) : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
    constructor() : this(Executor { Thread(it, "DocumentAccess").start() }, { FileOutputStream(it) })

    private lateinit var channel: MethodChannel
    private lateinit var contentResolver: ContentResolver
    private var activityBinding: ActivityPluginBinding? = null

    /** Диалог, ожидающий ответа человека, и ответ на открывший его вызов. */
    private var pendingDialog: PendingDialog? = null

    /**
     * Копирования открытых документов по путям их копий, пока исход
     * копирования не сообщён.
     */
    private val copies = ConcurrentHashMap<String, DocumentCopy>()

    /**
     * Документы, о которых поставщик при выборе сообщил нулевой размер, до шага
     * завершения работы с ними. Пополняется в фоновом потоке.
     */
    private val emptyDocuments: MutableSet<Uri> = ConcurrentHashMap.newKeySet()

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
        pendingDialog?.result?.success(null)
        pendingDialog = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val pending = pendingDialog?.takeIf { it.dialog.requestCode == requestCode } ?: return false
        pendingDialog = null
        val result = pending.result
        val document = data?.data?.takeIf { resultCode == Activity.RESULT_OK }
        if (document == null) {
            result.success(null)
            return true
        }
        // Право закрепляется, пока жива Activity, получившая ответ.
        when (pending.dialog) {
            DocumentDialog.CREATION -> {
                takeGrant(document, Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                // Запрос размера — межпроцессный вызов поставщика.
                backgroundExecutor.execute { answerChosenDocument(document, result) }
            }
            DocumentDialog.OPENING -> {
                takeGrant(document, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                result.success(document.toString())
            }
        }
        return true
    }

    private fun answerChosenDocument(document: Uri, result: MethodChannel.Result) {
        when (documentSize(document)) {
            // В документе неизвестного размера могли быть данные, поэтому после
            // отказа он не удаляется.
            null -> result.success(document.toString())
            0L -> {
                emptyDocuments += document
                result.success(document.toString())
            }
            else -> {
                releaseGrant(document)
                result.error(EXISTING_FILE, null, null)
            }
        }
    }

    /** Размер [document] по сведениям поставщика или `null`, если он неизвестен. */
    private fun documentSize(document: Uri): Long? = try {
        contentResolver.query(document, arrayOf(DocumentsContract.Document.COLUMN_SIZE), null, null, null)
            ?.use { cursor ->
                val column = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                if (column >= 0 && cursor.moveToFirst() && !cursor.isNull(column)) {
                    cursor.getLong(column).takeIf { it >= 0 }
                } else {
                    null
                }
            }
    } catch (error: Exception) {
        // Поставщик отказал запросу. Исключение в собственном потоке завершило
        // бы процесс.
        null
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createDocument" -> createDocument(requireNotNull(call.argument<String>("name")), result)
            "openDocument" -> openDocument(result)
            "writeDocument" -> writeDocument(
                source = requireNotNull(call.argument<String>("source")),
                document = Uri.parse(requireNotNull(call.argument<String>("document"))),
                result = result,
            )
            "finishDocument" -> finishDocument(
                document = Uri.parse(requireNotNull(call.argument<String>("document"))),
                succeeded = requireNotNull(call.argument<Boolean>("succeeded")),
                result = result,
            )
            "copyDocument" -> copyDocument(
                document = Uri.parse(requireNotNull(call.argument<String>("document"))),
                destination = File(requireNotNull(call.argument<String>("destination"))),
                result = result,
            )
            "cancelCopy" -> {
                copies.remove(requireNotNull(call.argument<String>("destination")))?.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun createDocument(name: String, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(DOCUMENT_TYPE)
            .putExtra(Intent.EXTRA_TITLE, name)
        startDialog(DocumentDialog.CREATION, intent, result)
    }

    // Часть поставщиков указывает тип документа неверно, а файл всё равно
    // проверяется по содержимому, поэтому диалог принимает документ любого типа.
    private fun openDocument(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        startDialog(DocumentDialog.OPENING, intent, result)
    }

    private fun startDialog(dialog: DocumentDialog, intent: Intent, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        // Второй диалог не открывается, пока первый ожидает ответа.
        if (activity == null || pendingDialog != null) {
            result.error(DIALOG_UNAVAILABLE, null, null)
            return
        }
        try {
            activity.startActivityForResult(intent, dialog.requestCode)
        } catch (error: ActivityNotFoundException) {
            result.error(DIALOG_UNAVAILABLE, null, null)
            return
        }
        pendingDialog = PendingDialog(dialog, result)
    }

    private fun writeDocument(source: String, document: Uri, result: MethodChannel.Result) {
        backgroundExecutor.execute {
            // Исключение в собственном потоке завершило бы процесс, поэтому любой
            // отказ поставщика документа становится отказом записи. Текст
            // исключения не передаётся: он может содержать адрес документа.
            val written = try {
                FileInputStream(source).use { input ->
                    // Поставщик, который недавно аварийно завершился, не возвращает поток.
                    // Режим "w" поставщик может не усекать, и в документе остался бы
                    // хвост прежнего содержимого.
                    val output = checkNotNull(contentResolver.openOutputStream(document, "wt"))
                    output.use { input.copyTo(it) }
                }
                true
            } catch (error: Exception) {
                false
            }
            if (written) result.success(null) else result.error(DOCUMENT_NOT_WRITTEN, null, null)
        }
    }

    private fun copyDocument(document: Uri, destination: File, result: MethodChannel.Result) {
        val copy = DocumentCopy(result)
        copies[destination.path] = copy
        backgroundExecutor.execute {
            val outcome = copyBytes(document, destination, copy)
            // Отменённое копирование уже сообщило исход и само удаляет копию,
            // когда поставщик ответил.
            val reported = copy.finish()
            if (!reported || outcome != CopyOutcome.COPIED) destination.delete()
            releaseGrant(document)
            copies.remove(destination.path, copy)
            if (reported) outcome.reply(result)
        }
    }

    /**
     * Копирует все байты [document] в [destination], пока копирование [copy]
     * не отменено. Исключение в собственном потоке завершило бы процесс,
     * поэтому любой отказ поставщика становится исходом.
     */
    private fun copyBytes(document: Uri, destination: File, copy: DocumentCopy): CopyOutcome {
        val input = try {
            openForReading(document, copy.cancellation)
        } catch (error: Exception) {
            return CopyOutcome.DOCUMENT_NOT_READ
        }
        try {
            // Поставщик, который не учитывает сигнал отмены, отвечает и после неё.
            if (copy.isCancelled) return CopyOutcome.CANCELLED
            return writeCopy(input, destination, copy)
        } finally {
            try {
                input.close()
            } catch (error: Exception) {
                // Чтение уже закончено: исход копирования известен.
            }
        }
    }

    /**
     * Открывает [document] для чтения с сигналом [cancellation].
     *
     * `ContentResolver` открывает документ для чтения типизированным запросом
     * любого типа, и `DocumentsProvider` теряет сигнал (Android SDK 36.1), а
     * клиент поставщика передаёт его в `DocumentsProvider.openDocument`. Клиент
     * нестабильный, поэтому гибель поставщика становится отказом чтения, а не
     * завершает процесс приложения. Как и потоки `ContentResolver`, поток
     * держит поставщика, пока не закрыт: поставщик отдаёт документ через канал.
     */
    private fun openForReading(document: Uri, cancellation: CancellationSignal): InputStream {
        val client = checkNotNull(contentResolver.acquireUnstableContentProviderClient(document))
        val descriptor = try {
            checkNotNull(client.openFile(document, "r", cancellation))
        } catch (error: Exception) {
            client.close()
            throw error
        }
        return object : ParcelFileDescriptor.AutoCloseInputStream(descriptor) {
            override fun close() = try {
                super.close()
            } finally {
                client.close()
            }
        }
    }

    private fun writeCopy(input: InputStream, destination: File, copy: DocumentCopy): CopyOutcome {
        try {
            openCopy(destination).use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val count = try {
                        input.read(buffer)
                    } catch (error: Exception) {
                        return CopyOutcome.DOCUMENT_NOT_READ
                    }
                    // Поставщик, который не учитывает сигнал отмены, отвечает и после неё.
                    if (copy.isCancelled) return CopyOutcome.CANCELLED
                    if (count < 0) return CopyOutcome.COPIED
                    output.write(buffer, 0, count)
                }
            }
        } catch (error: Exception) {
            return if (error.isStorageFull()) CopyOutcome.STORAGE_FULL else CopyOutcome.COPY_NOT_WRITTEN
        }
    }

    private fun finishDocument(document: Uri, succeeded: Boolean, result: MethodChannel.Result) {
        val wasEmpty = emptyDocuments.remove(document)
        if (succeeded || !wasEmpty) {
            releaseGrant(document)
            result.success(null)
            return
        }
        backgroundExecutor.execute {
            // Прерванное копирование оставляет в документе часть байтов.
            deleteDocument(document)
            releaseGrant(document)
            result.success(null)
        }
    }

    private fun deleteDocument(document: Uri) {
        try {
            DocumentsContract.deleteDocument(contentResolver, document)
        } catch (error: Exception) {
            // Поставщик не поддерживает удаление, доступ отозван или поставщик
            // отказал: документ остаётся, а исход операции не меняется. Исключение
            // в собственном потоке завершило бы процесс.
        }
    }

    /** Закрепляет право на [document] в режиме [mode], если поставщик его дал. */
    private fun takeGrant(document: Uri, mode: Int) {
        try {
            contentResolver.takePersistableUriPermission(document, mode)
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

    private enum class DocumentDialog(val requestCode: Int) {
        CREATION(0x0d0c),
        OPENING(0x0d0d),
    }

    private class PendingDialog(val dialog: DocumentDialog, val result: MethodChannel.Result)

    private companion object {
        const val CHANNEL = "software.doable.doable/document_access"
        const val DOCUMENT_TYPE = "application/gzip"
        const val DIALOG_UNAVAILABLE = "dialog_unavailable"
        const val DOCUMENT_NOT_WRITTEN = "document_not_written"
        const val EXISTING_FILE = "existing_file"
    }
}

/**
 * Копирование открытого документа, исход которого сообщается [result] один
 * раз: отменой или самим копированием, если оно закончилось раньше.
 */
private class DocumentCopy(private val result: MethodChannel.Result) {
    /** Сигнал, с которым открывается документ; отмена подаёт его поставщику. */
    val cancellation = CancellationSignal()
    private val state = AtomicReference(State.RUNNING)

    val isCancelled get() = state.get() == State.CANCELLED

    /**
     * Сразу сообщает исход отмены, не дожидаясь поставщика, который может
     * держать открытие документа или чтение из канала и не учитывать сигнал.
     * После исхода копирования ничего не меняет.
     */
    fun cancel() {
        if (!state.compareAndSet(State.RUNNING, State.CANCELLED)) return
        cancellation.cancel()
        CopyOutcome.CANCELLED.reply(result)
    }

    /** Заканчивает копирование и возвращает, должно ли оно сообщить свой исход. */
    fun finish(): Boolean = state.compareAndSet(State.RUNNING, State.FINISHED)

    private enum class State { RUNNING, CANCELLED, FINISHED }
}

/** Исход копирования открытого документа в файл приложения. */
private enum class CopyOutcome {
    COPIED,
    DOCUMENT_NOT_READ,
    STORAGE_FULL,
    COPY_NOT_WRITTEN,
    CANCELLED;

    fun reply(result: MethodChannel.Result) {
        val code = when (this) {
            COPIED -> return result.success(null)
            DOCUMENT_NOT_READ -> "document_not_read"
            STORAGE_FULL -> "storage_full"
            COPY_NOT_WRITTEN -> "copy_not_written"
            CANCELLED -> "copy_cancelled"
        }
        result.error(code, null, null)
    }
}

/** Отказ файловой системы из-за нехватки места на устройстве. */
private fun Throwable.isStorageFull(): Boolean =
    generateSequence(this) { it.cause }.any { it is ErrnoException && it.errno == OsConstants.ENOSPC }
