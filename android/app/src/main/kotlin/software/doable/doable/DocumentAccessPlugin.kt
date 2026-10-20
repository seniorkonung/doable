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
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import java.util.concurrent.LinkedBlockingQueue

/**
 * Документы вне каталога приложения через системные диалоги Storage Access
 * Framework без разрешений и без `FileProvider` (ADR-0037).
 *
 * Канал создаёт документ диалогом `ACTION_CREATE_DOCUMENT` и копирует в него
 * временный файл приложения, а документ, открытый диалогом
 * `ACTION_OPEN_DOCUMENT`, читает одной сессией: ограниченное начало передаётся
 * Dart порциями, а копирование в файл приложения разрешает проверка Dart.
 * Чтение идёт потоками `ContentResolver` в [backgroundExecutor]. Протокол
 * сессии описан у [beginDocumentRead], Dart-адаптер канала —
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

    /** Сессии чтения начала и копирования по отдельным путям попыток импорта. */
    private val reads = ConcurrentHashMap<String, DocumentRead>()

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
        reads.values.forEach(DocumentRead::cancel)
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
            "beginDocumentRead" -> beginDocumentRead(
                document = Uri.parse(requireNotNull(call.argument<String>("document"))),
                destination = File(requireNotNull(call.argument<String>("destination"))),
                prefixLimit = requireNotNull(call.argument<Int>("prefixLimit")),
                chunkSize = requireNotNull(call.argument<Int>("chunkSize")),
                result = result,
            )
            "readDocumentPrefix" -> requestRead(call, ReadAction.PREFIX, result)
            "copyReadDocument" -> requestRead(call, ReadAction.COPY, result)
            "finishDocumentRead" -> requestRead(call, ReadAction.FINISH, result)
            "cancelCopy" -> {
                val destination = requireNotNull(call.argument<String>("destination"))
                reads[destination]?.cancel()
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

    /**
     * `beginDocumentRead(document, destination, prefixLimit, chunkSize)` открывает
     * поток, не читая его. Последовательные `readDocumentPrefix(destination)`
     * возвращают не больше [chunkSize] байт, суммарно не больше [prefixLimit].
     * Пустая порция означает конец потока или достижение предела.
     * `copyReadDocument(destination)` разрешает запись начала и остатка того же
     * потока в файл попытки и завершает сессию исходом копирования.
     * `finishDocumentRead(destination)` закрывает поток без копии.
     * Параметры задаёт Dart; правил формата документа здесь нет.
     */
    private fun beginDocumentRead(
        document: Uri,
        destination: File,
        prefixLimit: Int,
        chunkSize: Int,
        result: MethodChannel.Result,
    ) {
        require(prefixLimit > 0 && chunkSize in 1..prefixLimit)
        val read = DocumentRead(result)
        check(reads.putIfAbsent(destination.path, read) == null)
        backgroundExecutor.execute {
            var outcome = ReadOutcome.DOCUMENT_NOT_READ
            try {
                val input = openForReading(document, read.cancellation)
                try {
                    outcome = if (read.isCancelled) {
                        ReadOutcome.CANCELLED
                    } else {
                        readDocument(input, destination, read, prefixLimit, chunkSize)
                    }
                } finally {
                    try {
                        input.close()
                    } catch (error: Exception) {
                        // Чтение закончено: ошибка закрытия не меняет его исход.
                    }
                }
            } catch (error: Exception) {
                // Поставщик может отказать и при открытии, и между порциями.
            }
            if (outcome != ReadOutcome.COPIED) destination.delete()
            releaseGrant(document)
            reads.remove(destination.path, read)
            // Отмена уже сообщила исход. Позднее завершение и отказ канала
            // удаляют только файл своей попытки.
            if (!read.finish(outcome) && outcome == ReadOutcome.COPIED) destination.delete()
        }
    }

    private fun requestRead(call: MethodCall, action: ReadAction, result: MethodChannel.Result) {
        val read = reads[requireNotNull(call.argument<String>("destination"))]
        if (read == null) {
            // Завершение идемпотентно: отмена могла уже освободить сессию.
            if (action == ReadAction.FINISH) result.success(null)
            else ReadOutcome.CANCELLED.reply(result)
        } else {
            read.request(action, result)
        }
    }

    private fun readDocument(
        input: InputStream,
        destination: File,
        read: DocumentRead,
        prefixLimit: Int,
        chunkSize: Int,
    ): ReadOutcome {
        if (!read.answer(null)) return ReadOutcome.CANCELLED
        val prefix = ByteArrayOutputStream(chunkSize)
        val buffer = ByteArray(chunkSize)
        var ended = false
        while (!read.isCancelled) {
            val action = read.next()
            if (read.isCancelled) return ReadOutcome.CANCELLED
            when (action) {
                ReadAction.FINISH -> return ReadOutcome.CLOSED_WITHOUT_COPY
                ReadAction.COPY -> return writeCopy(input, destination, read, prefix)
                ReadAction.PREFIX -> {
                    val remaining = prefixLimit - prefix.size()
                    val count = if (ended || remaining == 0) {
                        -1
                    } else {
                        input.read(buffer, 0, minOf(buffer.size, remaining))
                    }
                    if (count < 0) {
                        ended = true
                    } else {
                        prefix.write(buffer, 0, count)
                    }
                    if (!read.answer(if (count < 0) byteArrayOf() else buffer.copyOf(count))) {
                        return ReadOutcome.CANCELLED
                    }
                }
            }
        }
        return ReadOutcome.CANCELLED
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

    private fun writeCopy(
        input: InputStream,
        destination: File,
        read: DocumentRead,
        prefix: ByteArrayOutputStream,
    ): ReadOutcome {
        try {
            if (read.isCancelled) return ReadOutcome.CANCELLED
            openCopy(destination).use { output ->
                if (read.isCancelled) return ReadOutcome.CANCELLED
                prefix.writeTo(output)
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (!read.isCancelled) {
                    val count = try {
                        input.read(buffer)
                    } catch (error: Exception) {
                        return ReadOutcome.DOCUMENT_NOT_READ
                    }
                    // Поставщик, который не учитывает сигнал отмены, отвечает и после неё.
                    if (read.isCancelled) return ReadOutcome.CANCELLED
                    if (count < 0) return ReadOutcome.COPIED
                    output.write(buffer, 0, count)
                }
            }
            return ReadOutcome.CANCELLED
        } catch (error: Exception) {
            return if (error.isStorageFull()) ReadOutcome.STORAGE_FULL else ReadOutcome.COPY_NOT_WRITTEN
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

private enum class ReadAction { PREFIX, COPY, FINISH }

/**
 * Запросы Dart будят единственного владельца потока. Отмена будит также
 * ожидание решения и сразу отвечает на текущий запрос, даже если поставщик
 * держит чтение. Ответы допустимы из фонового потока:
 * https://api.flutter.dev/javadoc/io/flutter/plugin/common/MethodChannel.Result.html
 */
private class DocumentRead(result: MethodChannel.Result) {
    val cancellation = CancellationSignal()
    private val requests = LinkedBlockingQueue<ReadAction>()
    private var pending: MethodChannel.Result? = result
    @Volatile
    private var state = State.RUNNING
    val isCancelled get() = state == State.CANCELLED

    @Synchronized
    fun request(action: ReadAction, result: MethodChannel.Result) {
        if (state != State.RUNNING) {
            ReadOutcome.CANCELLED.reply(result)
            return
        }
        check(pending == null)
        pending = result
        requests.add(action)
    }

    fun next(): ReadAction = requests.take()

    @Synchronized
    fun answer(value: Any?): Boolean {
        if (state != State.RUNNING) return false
        val result = checkNotNull(pending)
        pending = null
        return try {
            result.success(value)
            true
        } catch (error: Exception) {
            // Канал потерян: поток и право больше некому передать.
            cancel()
            false
        }
    }

    @Synchronized
    fun cancel() {
        if (state != State.RUNNING) return
        state = State.CANCELLED
        val result = pending
        pending = null
        requests.add(ReadAction.FINISH)
        cancellation.cancel()
        try {
            result?.let(ReadOutcome.CANCELLED::reply)
        } catch (error: Exception) {
            // Движок мог уже потерять канал; повторного ответа не будет.
        }
    }

    @Synchronized
    fun finish(outcome: ReadOutcome): Boolean {
        if (state != State.RUNNING) return false
        state = State.FINISHED
        val result = checkNotNull(pending)
        pending = null
        return try {
            outcome.reply(result)
            true
        } catch (error: Exception) {
            // Ресурсы уже освобождены, а канал больше не принимает ответ.
            false
        }
    }

    private enum class State { RUNNING, CANCELLED, FINISHED }
}

/** Исход сессии чтения открытого документа с копией в файл приложения или без неё. */
private enum class ReadOutcome {
    COPIED,
    CLOSED_WITHOUT_COPY,
    DOCUMENT_NOT_READ,
    STORAGE_FULL,
    COPY_NOT_WRITTEN,
    CANCELLED;

    fun reply(result: MethodChannel.Result) {
        val code = when (this) {
            COPIED, CLOSED_WITHOUT_COPY -> return result.success(null)
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
