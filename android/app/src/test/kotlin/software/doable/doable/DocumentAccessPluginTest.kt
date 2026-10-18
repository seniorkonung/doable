package software.doable.doable

import android.app.Activity
import android.content.ContentProvider
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
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
import java.io.IOException
import java.io.OutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executor
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
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
    private val plugin = DocumentAccessPlugin(Executor { backgroundTasks += it })
    private val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    private val activityBinding = ResultActivityBinding(activity)
    private val document = Uri.parse(
        "content://com.android.externalstorage.documents/document/" +
            "primary%3ADownload%2FDoable%202026-10-18.jsonl.gz",
    )

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
    fun `Подключение к движку отпускает право, оставшееся после завершения процесса посреди экспорта`() {
        context.contentResolver.takePersistableUriPermission(document, Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

        DocumentAccessPlugin().onAttachedToEngine(pluginBinding(context, ChannelMessenger()))

        assertEquals(emptyList<Uri>(), writeGrants())
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
    private var envelope: ByteBuffer? = null
    val received get() = envelope != null

    override fun reply(reply: ByteBuffer?) {
        onReply()
        envelope = requireNotNull(reply)
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
