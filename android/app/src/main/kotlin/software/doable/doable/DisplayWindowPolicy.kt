package software.doable.doable

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Point
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import kotlin.math.min

internal enum class DisplayCategory(val activityClass: Class<out FlutterActivity>) {
    PHONE(PhoneActivity::class.java),
    LARGE(LargeDisplayActivity::class.java);

    companion object {
        fun fromPixels(width: Int, height: Int, densityDpi: Int): DisplayCategory =
            if (min(width, height).toLong() * 160 < 600L * densityDpi) PHONE else LARGE
    }
}

internal class DisplayWindowPolicy(private val activity: Activity) {
    private var windowContext: Context? = null
    private var windowDisplayId: Int? = null

    fun invalidateDisplay() {
        windowContext = null
    }

    @Suppress("DEPRECATION")
    fun category(): DisplayCategory {
        val display = activity.windowManager.defaultDisplay
        if (Build.VERSION.SDK_INT >= 30) {
            // Контекст дисплея исключает ограничения текущей Activity и узкого окна.
            // https://developer.android.com/reference/android/content/Context#createWindowContext(int,android.os.Bundle)
            if (windowContext == null || windowDisplayId != display.displayId) {
                windowContext = activity.createDisplayContext(display).createWindowContext(
                    WindowManager.LayoutParams.TYPE_APPLICATION,
                    null,
                )
                windowDisplayId = display.displayId
            }
            val context = requireNotNull(windowContext)
            val bounds = context.getSystemService(WindowManager::class.java)
                .maximumWindowMetrics.bounds
            return DisplayCategory.fromPixels(
                bounds.width(), bounds.height(), context.resources.configuration.densityDpi,
            )
        }

        // На API 24–29 getRealSize возвращает дисплей независимо от многооконного режима.
        // https://developer.android.com/reference/android/view/Display#getRealSize(android.graphics.Point)
        val size = Point()
        display.getRealSize(size)
        return DisplayCategory.fromPixels(
            size.x, size.y, activity.createDisplayContext(display).resources.configuration.densityDpi,
        )
    }

    fun replaceIfNeeded(
        current: DisplayCategory,
        retainEngine: () -> String,
    ) {
        val target = category()
        if (target == current) return
        launch(target, engineId = retainEngine())
        activity.finish()
    }

    fun launch(
        target: DisplayCategory,
        engineId: String? = null,
        replaceTask: Boolean = true,
    ) {
        val intent = if (engineId == null) {
            FlutterActivity.NewEngineIntentBuilder(target.activityClass).build(activity)
        } else {
            FlutterActivity.CachedEngineIntentBuilder(target.activityClass, engineId)
                .destroyEngineWithActivity(true)
                .build(activity)
        }
        // Режим окна принадлежит корню задачи: перенос обязан заменить и этот корень.
        // https://developer.android.com/develop/ui/views/layout/support-multi-window-mode#configure
        intent.addFlags(
            if (replaceTask) Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            else Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        activity.startActivity(intent)
    }
}
