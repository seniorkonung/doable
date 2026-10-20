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
    fun `Отказ поставщика при открытии документа даёт исход непрочитанного документа без копии`() {
        openDocument { openFailure = FileNotFoundException("Document moved") }
        val copy = File(temporary.root, "import-1.jsonl.gz")

        val reply = beginRead(copy)
        backgroundTasks.single().run()

        assertEquals("document_not_read", reply.errorCode())
        assertFalse(copy.exists())
        assertEquals(emptyList<Uri>(), readGrants())
    }

    @Test
    fun `Отказ поставщика посреди разрешённого копирования даёт исход непрочитанного документа и удаляет неполную копию`() {
        openDocument {
            content.writeBytes(ByteArray(20_000))
            // Облачный поставщик сообщает в канал, что загрузка прервалась.
            onReadEnd = { throw IOException("Remote error: network unavailable") }
        }
        val copy = File(temporary.root, "import-1.jsonl.gz")

        withDocumentRead(copy) {
            val reply = messenger.invoke("copyReadDocument", mapOf("destination" to copy.path))

            assertEquals("document_not_read", reply.awaitReply().errorCode())
            assertFalse(copy.exists())
            assertEquals(emptyList<Uri>(), readGrants())
        }
    }

    @Test
    fun `Другой отказ записи разрешённой копии даёт исход незаписанной копии`() {
        openDocument { content.writeBytes(ByteArray(20_000)) }
        val copy = File(temporary.root, "import-1.jsonl.gz")
        copyOutput = { file -> failingOutput(file, ErrnoException("write", OsConstants.EIO)) }

        withDocumentRead(copy) {
            val reply = messenger.invoke("copyReadDocument", mapOf("destination" to copy.path))

            assertEquals("copy_not_written", reply.awaitReply().errorCode())
            assertFalse(copy.exists())
            assertEquals(emptyList<Uri>(), readGrants())
        }
    }

    @Test
    fun `Отмена посреди копирования сразу даёт исход отмены, прекращает копирование после текущей порции и удаляет копию`() {
        openDocument { content.writeBytes(ByteArray(20_000)) }
        val copy = File(temporary.root, "import-1.jsonl.gz")
        lateinit var reply: ChannelReply
        val copyRequested = CountDownLatch(1)
        var writes = 0
        var cancelledAtFirstWrite = false
        copyOutput = { file ->
            object : FilterOutputStream(FileOutputStream(file)) {
                override fun write(b: ByteArray, off: Int, len: Int) {
                    out.write(b, off, len)
                    if (++writes == 1) {
                        copyRequested.await()
                        messenger.invoke("cancelCopy", mapOf("destination" to copy.path))
                        cancelledAtFirstWrite = reply.received
                    }
                }
            }
        }

        withDocumentRead(copy) { worker ->
            readPrefix(copy)
            reply = messenger.invoke("copyReadDocument", mapOf("destination" to copy.path))
            copyRequested.countDown()
            assertEquals("copy_cancelled", reply.awaitReply().errorCode())
            worker.join(5_000)

            assertTrue(cancelledAtFirstWrite)
            assertEquals(1, reply.count)
            assertEquals(1, writes)
            assertFalse(copy.exists())
            assertEquals(emptyList<Uri>(), readGrants())
        }
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
        val reply = beginRead(copy)
        val worker = thread { backgroundTasks.single().run() }
        try {
            assertTrue(opening.await(5, TimeUnit.SECONDS))

            val cancel = messenger.invoke("cancelCopy", mapOf("destination" to copy.path))

            assertNull(cancel.value())
            assertEquals("copy_cancelled", reply.errorCode())
            assertTrue(requireNotNull(signalAtOpening).isCanceled)
        } finally {
            providerAnswers.countDown()
            worker.join(5_000)
        }

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
        val next = File(temporary.root, "import-2.jsonl.gz")
        withDocumentRead(abandoned) { worker ->
            val reply = messenger.invoke("copyReadDocument", mapOf("destination" to abandoned.path))
            try {
                assertTrue(reading.await(5, TimeUnit.SECONDS))

                messenger.invoke("cancelCopy", mapOf("destination" to abandoned.path))
                assertEquals("copy_cancelled", reply.errorCode())

                provider.onReadEnd = null
                withDocumentRead(next) {
                    val nextReply = messenger.invoke("copyReadDocument", mapOf("destination" to next.path))
                    assertNull(nextReply.awaitReply().value())
                }
            } finally {
                providerAnswers.countDown()
                worker.join(5_000)
            }

            assertFalse(worker.isAlive)
            assertEquals(1, reply.count)
            assertFalse(abandoned.exists())
            assertArrayEquals(bytes, next.readBytes())
            assertEquals(emptyList<Uri>(), readGrants())
        }
    }

    @Test
    fun `Начало читается только по запросу в пределах порции и общего предела без чтения остатка и записи`() {
        val prefix = byteArrayOf(10, 20, 30, 40)
        var closed = false
        openDocument {
            content.writeBytes(prefix)
            onReadEnd = { throw IOException("Остаток пока недоступен") }
            onReadClose = { closed = true }
        }
        val copy = File(temporary.root, "import-prefix.jsonl.gz")
        copyOutput = { throw AssertionError("Копирование ещё не разрешено") }

        withDocumentRead(copy, prefixLimit = 4, chunkSize = 3) {
            assertFalse(copy.exists())
            assertEquals(listOf(document), readGrants())
            assertArrayEquals(byteArrayOf(10, 20, 30), readPrefix(copy).value() as ByteArray)
            assertArrayEquals(byteArrayOf(40), readPrefix(copy).value() as ByteArray)
            assertArrayEquals(byteArrayOf(), readPrefix(copy).value() as ByteArray)
            assertFalse(copy.exists())
            assertFalse(closed)

            val finish = messenger.invoke("finishDocumentRead", mapOf("destination" to copy.path))
            assertNull(finish.awaitReply().value())
            assertTrue(closed)
            assertEquals(emptyList<Uri>(), readGrants())
        }
    }

    @Test
    fun `Отказ проверки завершает сессию без открытия назначения даже при нехватке места`() {
        var writes = 0
        openDocument {
            content.writeBytes(byteArrayOf(1, 2))
            onReadEnd = { throw IOException("Остаток не должен читаться") }
        }
        val copy = File(temporary.root, "import-rejected.jsonl.gz")
        copyOutput = {
            writes++
            throw IOException("write failed", ErrnoException("open", OsConstants.ENOSPC))
        }

        withDocumentRead(copy, prefixLimit = 2, chunkSize = 2) {
            assertArrayEquals(byteArrayOf(1, 2), readPrefix(copy).value() as ByteArray)
            val finish = messenger.invoke("finishDocumentRead", mapOf("destination" to copy.path))

            assertNull(finish.awaitReply().value())
            assertEquals(0, writes)
            assertFalse(copy.exists())
            assertEquals(emptyList<Uri>(), readGrants())
        }
    }

    @Test
    fun `Разрешённая копия содержит начало и остаток одного открытия документа ровно по одному разу`() {
        val prefix = byteArrayOf(10, 20, 30, 40)
        val remainder = byteArrayOf(50, 60)
        var allowed = false
        var openings = 0
        var closed = false
        var copiedAtReply: ByteArray? = null
        val provider = openDocument {
            content.writeBytes(prefix)
            onOpen = { openings++ }
            onReadEnd = { check(allowed) { "Остаток ещё недоступен" } }
            onReadClose = { closed = true }
        }
        val copy = File(temporary.root, "import-allowed.jsonl.gz")
        copyOutput = { file ->
            check(allowed) { "Запись ещё не разрешена" }
            FileOutputStream(file)
        }

        withDocumentRead(copy, prefixLimit = 8, chunkSize = 3) {
            assertArrayEquals(byteArrayOf(10, 20, 30), readPrefix(copy).value() as ByteArray)
            assertArrayEquals(byteArrayOf(40), readPrefix(copy).value() as ByteArray)
            assertFalse(copy.exists())
            // Поставщик догрузил остаток; чтение продолжает тот же дескриптор.
            provider.content.appendBytes(remainder)
            allowed = true

            val copied = messenger.invoke(
                "copyReadDocument", mapOf("destination" to copy.path),
                onReply = { copiedAtReply = copy.readBytes() },
            )

            assertNull(copied.awaitReply().value())
            assertArrayEquals(prefix + remainder, copiedAtReply)
            assertArrayEquals(prefix + remainder, copy.readBytes())
            assertEquals(1, openings)
            assertTrue(closed)
            assertEquals(emptyList<Uri>(), readGrants())
            assertEquals(1, copied.count)
        }
    }

    @Test
    fun `Нехватка места при разрешённой записи сохранённого начала даёт свой исход и удаляет копию`() {
        openDocument { content.writeBytes(byteArrayOf(1, 2)) }
        val copy = File(temporary.root, "import-full.jsonl.gz")
        copyOutput = { file -> failingOutput(file, ErrnoException("write", OsConstants.ENOSPC)) }

        withDocumentRead(copy, prefixLimit = 2, chunkSize = 2) {
            readPrefix(copy)
            val copied = messenger.invoke("copyReadDocument", mapOf("destination" to copy.path))

            assertEquals("storage_full", copied.awaitReply().errorCode())
            assertFalse(copy.exists())
            assertEquals(emptyList<Uri>(), readGrants())
        }
    }

    @Test
    fun `Короткий документ заканчивает порции до общего предела без повторного чтения конца`() {
        var endReads = 0
        openDocument {
            content.writeBytes(byteArrayOf(1))
            onReadEnd = { endReads++ }
        }
        val copy = File(temporary.root, "import-short.jsonl.gz")

        withDocumentRead(copy, prefixLimit = 4, chunkSize = 2) {
            assertArrayEquals(byteArrayOf(1), readPrefix(copy).value() as ByteArray)
            assertArrayEquals(byteArrayOf(), readPrefix(copy).value() as ByteArray)
            assertArrayEquals(byteArrayOf(), readPrefix(copy).value() as ByteArray)
            assertEquals(1, endReads)
            assertFalse(copy.exists())
            assertNull(messenger.invoke("finishDocumentRead", mapOf("destination" to copy.path)).awaitReply().value())
        }
    }

    @Test
    fun `Отказ поставщика при чтении начала остаётся отказом чтения без попытки записи`() {
        var closed = false
        openDocument {
            content.writeBytes(byteArrayOf(1))
            onReadEnd = { throw IOException("Загрузка прервана") }
            onReadClose = { closed = true }
        }
        val copy = File(temporary.root, "import-unread.jsonl.gz")
        copyOutput = { throw AssertionError("Заголовок ещё не проверен") }

        withDocumentRead(copy, prefixLimit = 4, chunkSize = 2) {
            readPrefix(copy)

            assertEquals("document_not_read", readPrefix(copy).errorCode())
            assertTrue(closed)
            assertFalse(copy.exists())
            assertEquals(emptyList<Uri>(), readGrants())
        }
    }

    @Test
    fun `Отмена будит ожидание решения Dart и отпускает поток и право без повторного исхода`() =
        assertStoppedWhileAwaitingDecision { copy ->
            assertNull(messenger.invoke("cancelCopy", mapOf("destination" to copy.path)).value())
        }

    @Test
    fun `Потеря движка будит ожидание решения Dart и отпускает поток и право без повторного исхода`() =
        assertStoppedWhileAwaitingDecision {
            plugin.onDetachedFromEngine(pluginBinding(context, messenger))
        }

    @Test
    fun `Отказ канала при передаче начала завершает сессию и отпускает поток и право`() {
        var closed = false
        var replies = 0
        openDocument {
            content.writeBytes(byteArrayOf(1))
            onReadClose = { closed = true }
        }
        val copy = File(temporary.root, "import-channel-lost.jsonl.gz")

        withDocumentRead(copy, prefixLimit = 2, chunkSize = 1) { worker ->
            messenger.invoke("readDocumentPrefix", mapOf("destination" to copy.path), onReply = {
                replies++
                throw IllegalStateException("Канал потерян")
            })
            worker.join(5_000)

            assertFalse(worker.isAlive)
            assertEquals(1, replies)
            assertTrue(closed)
            assertFalse(copy.exists())
            assertEquals(emptyList<Uri>(), readGrants())
        }
    }

    private fun assertStoppedWhileAwaitingDecision(stop: (File) -> Unit) {
        var signal: CancellationSignal? = null
        var closed = false
        openDocument {
            content.writeBytes(byteArrayOf(1))
            onOpen = { signal = it }
            onReadEnd = { throw IOException("Остаток недоступен") }
            onReadClose = { closed = true }
        }
        val copy = File(temporary.root, "import-stopped.jsonl.gz")

        withDocumentRead(copy, prefixLimit = 2, chunkSize = 1) { worker ->
            val prefix = readPrefix(copy)
            assertArrayEquals(byteArrayOf(1), prefix.value() as ByteArray)

            stop(copy)
            worker.join(5_000)

            assertFalse(worker.isAlive)
            assertTrue(requireNotNull(signal).isCanceled)
            assertTrue(closed)
            assertFalse(copy.exists())
            assertEquals(emptyList<Uri>(), readGrants())
            assertEquals(1, prefix.count)
        }
    }

    /** Сессия работает в отдельном потоке и ждёт явных запросов канала. */
    private fun withDocumentRead(
        copy: File,
        prefixLimit: Int = 64 * 1024,
        chunkSize: Int = 1024,
        verify: (Thread) -> Unit,
    ) {
        val begun = beginRead(copy, prefixLimit, chunkSize)
        val worker = thread(isDaemon = true) { backgroundTasks.removeAt(0).run() }
        try {
            assertNull(begun.awaitReply().value())
            verify(worker)
        } finally {
            plugin.onDetachedFromEngine(pluginBinding(context, messenger))
            worker.join(5_000)
        }
        assertFalse(worker.isAlive)
        assertEquals(1, begun.count)
    }

    private fun beginRead(copy: File, prefixLimit: Int = 64 * 1024, chunkSize: Int = 1024): ChannelReply =
        messenger.invoke(
            "beginDocumentRead",
            mapOf(
                "document" to document.toString(), "destination" to copy.path,
                "prefixLimit" to prefixLimit, "chunkSize" to chunkSize,
            ),
        )

    private fun readPrefix(copy: File): ChannelReply =
        messenger.invoke("readDocumentPrefix", mapOf("destination" to copy.path)).awaitReply()

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
    private val answered = CountDownLatch(1)
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
        answered.countDown()
    }

    fun awaitReply(): ChannelReply {
        assertTrue("Плагин не ответил", answered.await(5, TimeUnit.SECONDS))
        return this
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

    /** Закрытие потока, которым плагин владеет до исхода сессии. */
    var onReadClose: () -> Unit = {}

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
        val readEnd = onReadEnd
        // Поток документа проверяет ошибку канала, дочитав его до конца.
        return object : ParcelFileDescriptor(descriptor) {
            override fun canDetectErrors() = readEnd != null

            override fun checkError() { readEnd?.invoke() }

            override fun close() {
                super.close()
                onReadClose()
            }
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
