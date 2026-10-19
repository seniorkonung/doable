package software.doable.doable

import android.app.Activity
import android.content.ContentProvider
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.UriPermission
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.system.ErrnoException
import android.system.OsConstants
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.plugin.platform.PlatformViewRegistry
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.FilterOutputStream
import java.io.IOException
import java.io.OutputStream
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowContentResolver
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter

@RunWith(RobolectricTestRunner::class)
class DocumentAccessPluginTest {
    private val context = RuntimeEnvironment.getApplication()
    private val messenger = ChannelMessenger()
    private val backgroundTasks = mutableListOf<Runnable>()

    /** Открывает файл копии документа для записи. */
    private var copyOutput: (File) -> OutputStream = { FileOutputStream(it) }
    private val plugin = DocumentAccessPlugin(Executor { backgroundTasks += it }) { copyOutput(it) }
    private val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    private val activityBinding = ResultActivityBinding(activity)
    private val document = Uri.parse(
        "content://com.android.externalstorage.documents/document/" +
            "primary%3ADownload%2FDoable%202026-10-18.jsonl.gz",
    )

    @get:Rule
    val temporary = TemporaryFolder()

    init {
        plugin.onAttachedToEngine(pluginBinding(context, messenger))
        plugin.onAttachedToActivity(activityBinding)
    }

    @Test
    fun `Диалог сохранения создаёт документ gzip с именем по умолчанию`() {
        val reply = messenger.invoke("createDocument", mapOf("name" to "Doable 2026-10-18.jsonl.gz"))

        val dialog = shadowOf(activity).nextStartedActivityForResult
        assertEquals(Intent.ACTION_CREATE_DOCUMENT, dialog.intent.action)
        assertEquals(setOf(Intent.CATEGORY_OPENABLE), dialog.intent.categories)
        assertEquals("application/gzip", dialog.intent.type)
        assertEquals("Doable 2026-10-18.jsonl.gz", dialog.intent.getStringExtra(Intent.EXTRA_TITLE))
        assertFalse(reply.received)

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))
        backgroundTasks.single().run()
        assertEquals(document.toString(), reply.value())
    }

    @Test
    fun `Выбор места закрепляет право записи в документ до ответа в Dart`() {
        var grantsAtReply: List<Uri>? = null
        val reply = messenger.invoke(
            "createDocument",
            mapOf("name" to "Doable 2026-10-18.jsonl.gz"),
            onReply = { grantsAtReply = writeGrants() },
        )
        val dialog = shadowOf(activity).nextStartedActivityForResult

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))
        backgroundTasks.single().run()

        assertEquals(document.toString(), reply.value())
        assertEquals(listOf(document), grantsAtReply)
    }

    @Test
    @Config(shadows = [ContentResolverWithoutPersistableGrants::class])
    fun `Без закрепляемого права адрес документа передаётся, а завершение работы отвечает без ошибки`() {
        val reply = messenger.invoke("createDocument", mapOf("name" to "Doable 2026-10-18.jsonl.gz"))
        val dialog = shadowOf(activity).nextStartedActivityForResult

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))
        backgroundTasks.single().run()
        val finish = messenger.invoke(
            "finishDocument", mapOf("document" to document.toString(), "succeeded" to true),
        )

        assertEquals(document.toString(), reply.value())
        assertNull(finish.value())
    }

    @Test
    fun `Завершение работы после записи документа отпускает закреплённое право и оставляет документ`() {
        val provider = chooseDocument()
        val source = File.createTempFile("export", ".jsonl.gz").apply {
            deleteOnExit()
            writeBytes(ByteArray(10))
        }
        shadowOf(context.contentResolver).registerOutputStream(document, ByteArrayOutputStream())
        messenger.invoke("writeDocument", mapOf("source" to source.path, "document" to document.toString()))
        backgroundTasks.single().run()
        backgroundTasks.clear()

        val finish = messenger.invoke(
            "finishDocument", mapOf("document" to document.toString(), "succeeded" to true),
        )
        backgroundTasks.forEach(Runnable::run)

        assertNull(finish.value())
        assertEquals(emptyList<Uri>(), writeGrants())
        assertEquals(emptyList<Uri>(), provider.deleted)
    }

    @Test
    fun `Завершение работы после отказа удаляет пустой при выборе документ в фоне, а затем отпускает право`() {
        val provider = chooseDocument()
        var grantsAtDeletion: List<Uri>? = null
        provider.onDelete = { grantsAtDeletion = writeGrants() }

        val finish = messenger.invoke(
            "finishDocument", mapOf("document" to document.toString(), "succeeded" to false),
        )
        assertFalse(finish.received)
        assertEquals(emptyList<Uri>(), provider.deleted)

        backgroundTasks.single().run()

        assertNull(finish.value())
        assertEquals(listOf(document), provider.deleted)
        assertEquals(listOf(document), grantsAtDeletion)
        assertEquals(emptyList<Uri>(), writeGrants())
    }

    @Test
    fun `Исключение поставщика при удалении документа не мешает отпустить право и ответить без ошибки`() {
        chooseDocument().deletionFailure = UnsupportedOperationException("Delete not supported")

        val finish = messenger.invoke(
            "finishDocument", mapOf("document" to document.toString(), "succeeded" to false),
        )
        backgroundTasks.single().run()

        assertNull(finish.value())
        assertEquals(emptyList<Uri>(), writeGrants())
    }

    @Test
    fun `Выбранный для замены файл с данными даёт в Dart исход существующего файла, а файл остаётся прежним и без права`() {
        val provider = registerDocumentsProvider().apply { content.writeBytes(ByteArray(10) { 7 }) }
        val reply = messenger.invoke("createDocument", mapOf("name" to "Doable 2026-10-18.jsonl.gz"))
        val dialog = shadowOf(activity).nextStartedActivityForResult

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))
        assertFalse(reply.received)
        backgroundTasks.forEach(Runnable::run)

        assertEquals("existing_file", reply.errorCode())
        assertEquals(emptyList<Uri>(), writeGrants())
        assertEquals(emptyList<Uri>(), provider.deleted)
        assertArrayEquals(ByteArray(10) { 7 }, provider.content.readBytes())
    }

    @Test
    fun `Документ, размер которого поставщик не сообщил, после отказа не удаляется, а право отпускается`() =
        assertKeptAfterFailure(chooseDocument { reportsSize = false })

    @Test
    fun `Документ, запрос размера которого отказал, после отказа не удаляется, а право отпускается`() =
        assertKeptAfterFailure(chooseDocument { sizeQueryFailure = IllegalStateException("Provider died") })

    @Test
    fun `Подключение к движку отпускает права, оставшиеся после завершения процесса посреди экспорта и импорта`() {
        val imported = Uri.parse("content://com.android.providers.downloads.documents/document/42")
        context.contentResolver.takePersistableUriPermission(document, Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        context.contentResolver.takePersistableUriPermission(imported, Intent.FLAG_GRANT_READ_URI_PERMISSION)

        DocumentAccessPlugin().onAttachedToEngine(pluginBinding(context, ChannelMessenger()))

        assertEquals(emptyList<UriPermission>(), context.contentResolver.persistedUriPermissions)
    }

    @Test
    fun `Закрытие диалога без выбора места завершает создание отменой`() {
        val reply = messenger.invoke("createDocument", mapOf("name" to "Doable 2026-10-18.jsonl.gz"))
        val dialog = shadowOf(activity).nextStartedActivityForResult

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_CANCELED, null)

        assertNull(reply.value())
    }

    @Test
    fun `Отсоединение Activity с ожидающим диалогом завершает создание отменой`() {
        val reply = messenger.invoke("createDocument", mapOf("name" to "Doable 2026-10-18.jsonl.gz"))

        plugin.onDetachedFromActivity()

        assertNull(reply.value())
    }

    @Test
    fun `Пересоздание Activity при смене конфигурации получает ответ ожидающего диалога`() {
        val reply = messenger.invoke("createDocument", mapOf("name" to "Doable 2026-10-18.jsonl.gz"))
        val dialog = shadowOf(activity).nextStartedActivityForResult
        val recreated = ResultActivityBinding(Robolectric.buildActivity(Activity::class.java).setup().get())

        plugin.onDetachedFromActivityForConfigChanges()
        plugin.onReattachedToActivityForConfigChanges(recreated)
        assertFalse(reply.received)
        recreated.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))
        backgroundTasks.single().run()

        assertEquals(document.toString(), reply.value())
    }

    @Test
    fun `Копирование в фоне записывает все байты файла и закрывает документ до ответа`() {
        // Больше буфера копирования, чтобы запись шла несколькими порциями.
        val bytes = ByteArray(20_000) { it.toByte() }
        val source = File.createTempFile("export", ".jsonl.gz").apply {
            deleteOnExit()
            writeBytes(bytes)
        }
        val written = ClosingOutputStream()
        shadowOf(context.contentResolver).registerOutputStream(document, written)

        val reply = messenger.invoke(
            "writeDocument", mapOf("source" to source.path, "document" to document.toString()),
        )
        assertEquals(0, written.size())
        assertFalse(reply.received)

        backgroundTasks.single().run()

        assertNull(reply.value())
        assertArrayEquals(bytes, written.toByteArray())
        assertTrue(written.closedBeforeReply)
    }

    @Test
    fun `Копирование заменяет прежнее содержимое документа целиком, даже если оно длиннее файла`() {
        val provider = registerDocumentsProvider().apply { content.writeBytes(ByteArray(300) { 7 }) }
        val bytes = ByteArray(100) { it.toByte() }
        val source = File.createTempFile("export", ".jsonl.gz").apply {
            deleteOnExit()
            writeBytes(bytes)
        }

        val reply = messenger.invoke(
            "writeDocument", mapOf("source" to source.path, "document" to document.toString()),
        )
        backgroundTasks.single().run()

        assertNull(reply.value())
        assertArrayEquals(bytes, provider.content.readBytes())
    }

    @Test
    fun `Ошибка потока документа завершает копирование отказом записи`() {
        val source = File.createTempFile("export", ".jsonl.gz").apply {
            deleteOnExit()
            writeBytes(ByteArray(10))
        }
        shadowOf(context.contentResolver).registerOutputStream(
            document,
            object : OutputStream() {
                override fun write(b: Int) = throw IOException("ENOSPC")
            },
        )

        val reply = messenger.invoke(
            "writeDocument", mapOf("source" to source.path, "document" to document.toString()),
        )
        backgroundTasks.single().run()

        assertEquals("document_not_written", reply.errorCode())
    }

    @Test
    fun `Диалог выбора открывает документ любого типа и отвечает его адресом`() {
        val reply = messenger.invoke("openDocument", emptyMap())

        val dialog = shadowOf(activity).nextStartedActivityForResult
        assertEquals(Intent.ACTION_OPEN_DOCUMENT, dialog.intent.action)
        assertEquals(setOf(Intent.CATEGORY_OPENABLE), dialog.intent.categories)
        assertEquals("*/*", dialog.intent.type)
        assertFalse(reply.received)

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))
        assertEquals(document.toString(), reply.value())
    }

    @Test
    fun `Выбор документа закрепляет право чтения до ответа в Dart`() {
        var grantsAtReply: List<Uri>? = null
        val reply = messenger.invoke("openDocument", emptyMap(), onReply = { grantsAtReply = readGrants() })
        val dialog = shadowOf(activity).nextStartedActivityForResult

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))

        assertEquals(document.toString(), reply.value())
        assertEquals(listOf(document), grantsAtReply)
    }

    @Test
    @Config(shadows = [ContentResolverWithoutPersistableGrants::class])
    fun `Без закрепляемого права выбор документа отвечает его адресом`() {
        val reply = messenger.invoke("openDocument", emptyMap())
        val dialog = shadowOf(activity).nextStartedActivityForResult

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))

        assertEquals(document.toString(), reply.value())
    }

    @Test
    fun `Закрытие диалога выбора без документа завершает открытие отменой`() {
        val reply = messenger.invoke("openDocument", emptyMap())
        val dialog = shadowOf(activity).nextStartedActivityForResult

        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_CANCELED, null)

        assertNull(reply.value())
    }

    @Test
    fun `Отсоединение Activity с ожидающим диалогом выбора завершает открытие отменой`() {
        val reply = messenger.invoke("openDocument", emptyMap())

        plugin.onDetachedFromActivity()

        assertNull(reply.value())
    }

    @Test
    fun `Копирование в фоне записывает в файл приложения все байты документа до ответа и отпускает право`() {
        // Больше буфера копирования, чтобы чтение шло несколькими порциями.
        val bytes = ByteArray(20_000) { it.toByte() }
        openDocument { content.writeBytes(bytes) }
        val copy = File(temporary.root, "import-1.jsonl.gz")
        var copiedAtReply: ByteArray? = null

        val reply = messenger.invoke(
            "copyDocument",
            mapOf("document" to document.toString(), "destination" to copy.path),
            onReply = { copiedAtReply = copy.readBytes() },
        )
        assertFalse(reply.received)
        backgroundTasks.single().run()

        assertNull(reply.value())
        assertArrayEquals(bytes, copiedAtReply)
        assertEquals(emptyList<Uri>(), readGrants())
    }

    @Test
    fun `Отказ поставщика при открытии документа даёт исход непрочитанного документа без копии`() {
        openDocument { openFailure = FileNotFoundException("Document moved") }
        val copy = File(temporary.root, "import-1.jsonl.gz")

        val reply = messenger.invoke(
            "copyDocument", mapOf("document" to document.toString(), "destination" to copy.path),
        )
        backgroundTasks.single().run()

        assertEquals("document_not_read", reply.errorCode())
        assertFalse(copy.exists())
        assertEquals(emptyList<Uri>(), readGrants())
    }

    @Test
    fun `Отказ поставщика посреди чтения даёт исход непрочитанного документа и удаляет неполную копию`() {
        openDocument {
            content.writeBytes(ByteArray(20_000))
            // Облачный поставщик сообщает в канал, что загрузка прервалась.
            onReadEnd = { throw IOException("Remote error: network unavailable") }
        }
        val copy = File(temporary.root, "import-1.jsonl.gz")

        val reply = messenger.invoke(
            "copyDocument", mapOf("document" to document.toString(), "destination" to copy.path),
        )
        backgroundTasks.single().run()

        assertEquals("document_not_read", reply.errorCode())
        assertFalse(copy.exists())
        assertEquals(emptyList<Uri>(), readGrants())
    }

    @Test
    fun `Нехватка места при записи копии даёт свой исход и удаляет неполную копию`() {
        openDocument { content.writeBytes(ByteArray(20_000)) }
        val copy = File(temporary.root, "import-1.jsonl.gz")
        copyOutput = { file -> failingOutput(file, ErrnoException("write", OsConstants.ENOSPC)) }

        val reply = messenger.invoke(
            "copyDocument", mapOf("document" to document.toString(), "destination" to copy.path),
        )
        backgroundTasks.single().run()

        assertEquals("storage_full", reply.errorCode())
        assertFalse(copy.exists())
        assertEquals(emptyList<Uri>(), readGrants())
    }

    @Test
    fun `Другой отказ записи копии даёт исход незаписанной копии`() {
        openDocument { content.writeBytes(ByteArray(20_000)) }
        val copy = File(temporary.root, "import-1.jsonl.gz")
        copyOutput = { file -> failingOutput(file, ErrnoException("write", OsConstants.EIO)) }

        val reply = messenger.invoke(
            "copyDocument", mapOf("document" to document.toString(), "destination" to copy.path),
        )
        backgroundTasks.single().run()

        assertEquals("copy_not_written", reply.errorCode())
        assertFalse(copy.exists())
        assertEquals(emptyList<Uri>(), readGrants())
    }

    @Test
    fun `Отмена посреди копирования сразу даёт исход отмены, прекращает копирование после текущей порции и удаляет копию`() {
        openDocument { content.writeBytes(ByteArray(20_000)) }
        val copy = File(temporary.root, "import-1.jsonl.gz")
        lateinit var reply: ChannelReply
        var writes = 0
        var cancelledAtFirstWrite = false
        copyOutput = { file ->
            object : FilterOutputStream(FileOutputStream(file)) {
                override fun write(b: ByteArray, off: Int, len: Int) {
                    out.write(b, off, len)
                    if (++writes == 1) {
                        messenger.invoke("cancelCopy", mapOf("destination" to copy.path))
                        cancelledAtFirstWrite = reply.received
                    }
                }
            }
        }

        reply = messenger.invoke(
            "copyDocument", mapOf("document" to document.toString(), "destination" to copy.path),
        )
        backgroundTasks.single().run()

        assertTrue(cancelledAtFirstWrite)
        assertEquals("copy_cancelled", reply.errorCode())
        assertEquals(1, writes)
        assertFalse(copy.exists())
        assertEquals(emptyList<Uri>(), readGrants())
    }

    @Test
    fun `Отмена, пока поставщик держит открытие документа, подаёт ему сигнал и даёт исход отмены до его ответа`() {
        val opening = CountDownLatch(1)
        val providerAnswers = CountDownLatch(1)
        var signalAtOpening: CancellationSignal? = null
        // Поставщик не учитывает сигнал и отвечает документом, когда загрузит его.
        openDocument {
            content.writeBytes(ByteArray(20_000))
            onOpen = { signal ->
                signalAtOpening = signal
                opening.countDown()
                providerAnswers.await()
            }
        }
        val copy = File(temporary.root, "import-1.jsonl.gz")
        val openedCopies = mutableListOf<File>()
        copyOutput = { file -> FileOutputStream(file).also { openedCopies += file } }
        val reply = messenger.invoke(
            "copyDocument", mapOf("document" to document.toString(), "destination" to copy.path),
        )
        val worker = thread { backgroundTasks.single().run() }
        assertTrue(opening.await(5, TimeUnit.SECONDS))

        val cancel = messenger.invoke("cancelCopy", mapOf("destination" to copy.path))

        assertNull(cancel.value())
        assertEquals("copy_cancelled", reply.errorCode())
        assertTrue(requireNotNull(signalAtOpening).isCanceled)

        providerAnswers.countDown()
        worker.join(5_000)

        assertFalse(worker.isAlive)
        assertEquals(1, reply.count)
        assertEquals(emptyList<File>(), openedCopies)
        assertEquals(emptyList<Uri>(), readGrants())
    }

    @Test
    fun `Брошенное копирование, поставщик которого держит чтение, после его ответа удаляет копию и не меняет файл другого копирования`() {
        val bytes = ByteArray(20_000) { it.toByte() }
        val reading = CountDownLatch(1)
        val providerAnswers = CountDownLatch(1)
        // Поставщик отдал часть документа, а остальное отдаст, когда загрузит.
        val provider = openDocument {
            content.writeBytes(bytes)
            onReadEnd = {
                reading.countDown()
                providerAnswers.await()
            }
        }
        val abandoned = File(temporary.root, "import-1.jsonl.gz")
        val reply = messenger.invoke(
            "copyDocument", mapOf("document" to document.toString(), "destination" to abandoned.path),
        )
        val worker = thread { backgroundTasks.removeAt(0).run() }
        assertTrue(reading.await(5, TimeUnit.SECONDS))

        messenger.invoke("cancelCopy", mapOf("destination" to abandoned.path))
        assertEquals("copy_cancelled", reply.errorCode())

        provider.onReadEnd = null
        val next = File(temporary.root, "import-2.jsonl.gz")
        val nextReply = messenger.invoke(
            "copyDocument", mapOf("document" to document.toString(), "destination" to next.path),
        )
        backgroundTasks.single().run()
        assertNull(nextReply.value())

        providerAnswers.countDown()
        worker.join(5_000)

        assertFalse(worker.isAlive)
        assertEquals(1, reply.count)
        assertFalse(abandoned.exists())
        assertArrayEquals(bytes, next.readBytes())
        assertEquals(emptyList<Uri>(), readGrants())
    }

    /**
     * Документ, который человек выбрал в диалоге выбора, и его поставщик,
     * настроенный [configure].
     */
    private fun openDocument(configure: DocumentsProviderStub.() -> Unit): DocumentsProviderStub {
        val provider = registerDocumentsProvider().apply(configure)
        val reply = messenger.invoke("openDocument", emptyMap())
        val dialog = shadowOf(activity).nextStartedActivityForResult
        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))
        assertEquals(document.toString(), reply.value())
        return provider
    }

    /** Поток файла [file], запись в который отказывает ошибкой файловой системы [cause]. */
    private fun failingOutput(file: File, cause: ErrnoException): OutputStream =
        object : FilterOutputStream(FileOutputStream(file)) {
            override fun write(b: ByteArray, off: Int, len: Int) = throw IOException("write failed", cause)
        }

    /**
     * Документ, место которого человек выбрал в системном диалоге, и его
     * поставщик, настроенный [configure]. По умолчанию поставщик сообщает, что
     * документ пуст, как после создания диалогом.
     */
    private fun chooseDocument(configure: DocumentsProviderStub.() -> Unit = {}): DocumentsProviderStub {
        val provider = registerDocumentsProvider().apply(configure)
        val reply = messenger.invoke("createDocument", mapOf("name" to "Doable 2026-10-18.jsonl.gz"))
        val dialog = shadowOf(activity).nextStartedActivityForResult
        activityBinding.deliverResult(dialog.requestCode, Activity.RESULT_OK, Intent().setData(document))
        backgroundTasks.forEach(Runnable::run)
        backgroundTasks.clear()
        assertEquals(document.toString(), reply.value())
        return provider
    }

    /** Завершение работы после отказа оставляет документ и отпускает право. */
    private fun assertKeptAfterFailure(provider: DocumentsProviderStub) {
        val finish = messenger.invoke(
            "finishDocument", mapOf("document" to document.toString(), "succeeded" to false),
        )
        backgroundTasks.forEach(Runnable::run)

        assertNull(finish.value())
        assertEquals(emptyList<Uri>(), provider.deleted)
        assertEquals(emptyList<Uri>(), writeGrants())
    }

    /** Поставщик документа, место которого выбрано в диалоге сохранения. */
    private fun registerDocumentsProvider(): DocumentsProviderStub =
        Robolectric.setupContentProvider(DocumentsProviderStub::class.java, document.authority)

    /** Документы с закреплённым правом записи. */
    private fun writeGrants(): List<Uri> =
        context.contentResolver.persistedUriPermissions.filter { it.isWritePermission }.map { it.uri }

    /** Документы с закреплённым правом чтения. */
    private fun readGrants(): List<Uri> =
        context.contentResolver.persistedUriPermissions.filter { it.isReadPermission }.map { it.uri }

    private inner class ClosingOutputStream : ByteArrayOutputStream() {
        var closedBeforeReply = false

        override fun close() {
            closedBeforeReply = !messenger.anyReplyReceived
        }
    }
}

private fun pluginBinding(
    context: Context,
    messenger: BinaryMessenger,
): FlutterPlugin.FlutterPluginBinding =
    // Плагину нужны только контекст и канал, а движок требует нативной библиотеки.
    ReflectionHelpers.callConstructor(
        FlutterPlugin.FlutterPluginBinding::class.java,
        ClassParameter.from(Context::class.java, context),
        ClassParameter.from(FlutterEngine::class.java, null),
        ClassParameter.from(BinaryMessenger::class.java, messenger),
        ClassParameter.from(TextureRegistry::class.java, null),
        ClassParameter.from(PlatformViewRegistry::class.java, null),
        ClassParameter.from(FlutterPlugin.FlutterAssets::class.java, null),
        ClassParameter.from(FlutterEngineGroup::class.java, null),
    )

private const val CHANNEL = "software.doable.doable/document_access"

/** Передаёт вызовы Dart плагину через его канал и кодек. */
private class ChannelMessenger : BinaryMessenger {
    private val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
    private val replies = mutableListOf<ChannelReply>()
    val anyReplyReceived get() = replies.any { it.received }

    fun invoke(method: String, arguments: Map<String, Any>, onReply: () -> Unit = {}): ChannelReply {
        val reply = ChannelReply(onReply).also { replies += it }
        val message = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments))
        message.rewind()
        requireNotNull(handlers[CHANNEL]).onMessage(message, reply)
        return reply
    }

    override fun send(channel: String, message: ByteBuffer?) = Unit

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) =
        Unit

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        if (handler == null) handlers.remove(channel) else handlers[channel] = handler
    }
}

/** Ответ плагина; [onReply] наблюдает состояние в момент ответа. */
private class ChannelReply(private val onReply: () -> Unit) : BinaryMessenger.BinaryReply {
    @Volatile
    private var envelope: ByteBuffer? = null

    /** Сколько раз плагин ответил на вызов: Flutter принимает только один ответ. */
    @Volatile
    var count = 0
        private set
    val received get() = count > 0

    override fun reply(reply: ByteBuffer?) {
        onReply()
        envelope = requireNotNull(reply)
        count++
    }

    fun value(): Any? {
        val envelope = requireNotNull(envelope) { "Плагин не ответил" }
        envelope.rewind()
        return StandardMethodCodec.INSTANCE.decodeEnvelope(envelope)
    }

    fun errorCode(): String {
        val error = runCatching { value() }.exceptionOrNull()
        return (error as? FlutterException)?.code
            ?: throw AssertionError("Ожидался отказ канала, получено $error")
    }
}

/**
 * Поставщик документа без закрепляемого права: как Android, отказывает и
 * закрепить право, и отпустить его.
 *
 * Класс открыт: Robolectric создаёт тень отражением.
 */
@Implements(ContentResolver::class)
class ContentResolverWithoutPersistableGrants : ShadowContentResolver() {
    @Implementation
    override fun takePersistableUriPermission(uri: Uri, modeFlags: Int): Unit =
        throw SecurityException("No persistable permission grants found")

    @Implementation
    override fun releasePersistableUriPermission(uri: Uri, modeFlags: Int): Unit =
        throw SecurityException("No permission grants found")
}

/**
 * Поставщик документа с содержимым [content], который запоминает удалённые
 * документы, а при [deletionFailure] отказывает удалению исключением.
 *
 * Класс открыт: Robolectric создаёт поставщика отражением.
 */
class DocumentsProviderStub : ContentProvider() {
    val deleted = mutableListOf<Uri>()

    /** Наблюдает состояние в момент удаления. */
    var onDelete: () -> Unit = {}
    var deletionFailure: RuntimeException? = null

    val content: File = File.createTempFile("document", ".jsonl.gz").apply { deleteOnExit() }

    /** Сообщает ли поставщик размер документа: сообщать его он не обязан. */
    var reportsSize = true
    var sizeQueryFailure: RuntimeException? = null

    /**
     * Наблюдает открытие документа с сигналом отмены и может держать его, как
     * облачный поставщик, который сначала загружает документ.
     */
    var onOpen: (CancellationSignal?) -> Unit = {}
    var openFailure: Exception? = null

    /**
     * Чтение после последнего байта [content]. Как канал облачного поставщика,
     * может сообщить ошибку загрузки или держать чтение, пока документ
     * загружается; без него чтение заканчивается.
     */
    var onReadEnd: (() -> Unit)? = null

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        // Метод поставщика, которым DocumentsContract.deleteDocument удаляет документ.
        check(method == "android:deleteDocument") { "Неожиданный метод поставщика $method" }
        deletionFailure?.let { throw it }
        onDelete()
        deleted += requireNotNull(extras?.getParcelable("uri", Uri::class.java))
        return null
    }

    override fun onCreate() = true

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor {
        sizeQueryFailure?.let { throw it }
        val size = content.length().takeIf { reportsSize }
        return MatrixCursor(arrayOf(DocumentsContract.Document.COLUMN_SIZE)).apply { addRow(arrayOf(size)) }
    }

    // Как поставщик локальных папок FileSystemProvider: режим "w" переводится во
    // флаги файла без усечения.
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor =
        ParcelFileDescriptor.open(content, ParcelFileDescriptor.parseMode(mode))

    override fun openFile(uri: Uri, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        onOpen(signal)
        openFailure?.let { throw it }
        val descriptor = openFile(uri, mode)
        val readEnd = onReadEnd ?: return descriptor
        // Поток документа проверяет ошибку канала, дочитав его до конца.
        return object : ParcelFileDescriptor(descriptor) {
            override fun canDetectErrors() = true

            override fun checkError() = readEnd()
        }
    }

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?) = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<String>?,
    ) = 0
}

/** Привязка к Activity, которая, как Flutter, передаёт ответы Activity слушателям. */
private class ResultActivityBinding(private val activity: Activity) : ActivityPluginBinding {
    private val resultListeners = mutableSetOf<PluginRegistry.ActivityResultListener>()

    fun deliverResult(requestCode: Int, resultCode: Int, data: Intent?) {
        resultListeners.toList().forEach { it.onActivityResult(requestCode, resultCode, data) }
    }

    override fun getActivity(): Activity = activity

    override fun getLifecycle(): Any = Unit

    override fun addActivityResultListener(listener: PluginRegistry.ActivityResultListener) {
        resultListeners += listener
    }

    override fun removeActivityResultListener(listener: PluginRegistry.ActivityResultListener) {
        resultListeners -= listener
    }

    override fun addRequestPermissionsResultListener(
        listener: PluginRegistry.RequestPermissionsResultListener,
    ) = Unit

    override fun removeRequestPermissionsResultListener(
        listener: PluginRegistry.RequestPermissionsResultListener,
    ) = Unit

    override fun addOnNewIntentListener(listener: PluginRegistry.NewIntentListener) = Unit

    override fun removeOnNewIntentListener(listener: PluginRegistry.NewIntentListener) = Unit

    override fun addOnUserLeaveHintListener(listener: PluginRegistry.UserLeaveHintListener) = Unit

    override fun removeOnUserLeaveHintListener(listener: PluginRegistry.UserLeaveHintListener) = Unit

    override fun addOnWindowFocusChangedListener(
        listener: PluginRegistry.WindowFocusChangedListener,
    ) = Unit

    override fun removeOnWindowFocusChangedListener(
        listener: PluginRegistry.WindowFocusChangedListener,
    ) = Unit

    override fun addOnSaveStateListener(listener: ActivityPluginBinding.OnSaveInstanceStateListener) =
        Unit

    override fun removeOnSaveStateListener(
        listener: ActivityPluginBinding.OnSaveInstanceStateListener,
    ) = Unit
}
