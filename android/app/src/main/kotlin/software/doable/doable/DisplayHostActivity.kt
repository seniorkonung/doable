package software.doable.doable

import android.content.res.Configuration
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngineCache

abstract class DisplayHostActivity internal constructor(
    private val displayCategory: DisplayCategory,
) : FlutterActivity(), DisplayManager.DisplayListener {
    private var replacingHost = false
    private val displayPolicy = DisplayWindowPolicy(this)

    override fun onStart() {
        super.onStart()
        getSystemService(DisplayManager::class.java)
            .registerDisplayListener(this, Handler(Looper.getMainLooper()))
    }

    override fun onStop() {
        getSystemService(DisplayManager::class.java).unregisterDisplayListener(this)
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Проверяем также восстановленный системой корень до первого кадра Flutter.
        updateDisplayPolicy()
    }

    override fun onResume() {
        super.onResume()
        // Пока Activity остановлена, события дисплея не наблюдаются.
        displayPolicy.invalidateDisplay()
        updateDisplayPolicy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        displayPolicy.invalidateDisplay()
        updateDisplayPolicy()
    }

    override fun onDisplayAdded(displayId: Int) = Unit

    override fun onDisplayRemoved(displayId: Int) = Unit

    override fun onDisplayChanged(displayId: Int) {
        displayPolicy.invalidateDisplay()
        updateDisplayPolicy()
    }

    override fun shouldDestroyEngineWithHost(): Boolean =
        !replacingHost && super.shouldDestroyEngineWithHost()

    override fun getCachedEngineId(): String? {
        // После гибели процесса Intent сохраняется, а кэш двигателя — нет.
        val id = super.getCachedEngineId()
        return id?.takeIf { FlutterEngineCache.getInstance().contains(it) }
    }

    private fun updateDisplayPolicy() {
        if (replacingHost || isFinishing) return
        displayPolicy.replaceIfNeeded(displayCategory) {
            replacingHost = true
            FlutterEngineCache.getInstance().put(TRANSFER_ENGINE_ID, requireNotNull(flutterEngine))
            TRANSFER_ENGINE_ID
        }
    }

    private companion object {
        const val TRANSFER_ENGINE_ID = "display-policy"
    }
}

class PhoneActivity : DisplayHostActivity(DisplayCategory.PHONE)

class LargeDisplayActivity : DisplayHostActivity(DisplayCategory.LARGE)
