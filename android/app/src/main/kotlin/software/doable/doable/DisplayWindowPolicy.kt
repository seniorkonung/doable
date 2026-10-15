package software.doable.doable

import android.app.Activity
import android.app.ActivityManager
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

internal data class RetainedDisplayEngine(val id: String, val frameworkHandlesBack: Boolean)

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
        retainEngine: () -> RetainedDisplayEngine,
    ) {
        val target = category()
        if (target == current) return
        launch(target, engine = retainEngine())
    }

    fun takeTransferredFrameworkHandlesBack(): Boolean? {
        if (!activity.intent.hasExtra(FRAMEWORK_HANDLES_BACK)) return null
        val handlesBack = activity.intent.getBooleanExtra(FRAMEWORK_HANDLES_BACK, false)
        activity.intent.removeExtra(FRAMEWORK_HANDLES_BACK)
        return handlesBack
    }

    @Suppress("DEPRECATION")
    fun completeTransfer() {
        if (!activity.intent.hasExtra(PREVIOUS_TASK_ID)) return
        val previousTaskId = activity.intent.getIntExtra(PREVIOUS_TASK_ID, -1)
        activity.intent.removeExtra(PREVIOUS_TASK_ID)
        // Новый хост уже подключил двигатель; удаляем и старую карточку в недавних.
        // https://developer.android.com/reference/android/app/ActivityManager.AppTask#finishAndRemoveTask()
        activity.getSystemService(ActivityManager::class.java).appTasks
            .firstOrNull { it.taskInfo?.id == previousTaskId }
            ?.finishAndRemoveTask()
    }

    fun launch(
        target: DisplayCategory,
        engine: RetainedDisplayEngine? = null,
        task: ActivityManager.AppTask? = null,
    ) {
        val intent = if (engine == null) {
            FlutterActivity.NewEngineIntentBuilder(target.activityClass).build(activity)
        } else {
            FlutterActivity.CachedEngineIntentBuilder(target.activityClass, engine.id)
                .destroyEngineWithActivity(true)
                .build(activity)
                .putExtra(PREVIOUS_TASK_ID, activity.taskId)
                .putExtra(FRAMEWORK_HANDLES_BACK, engine.frameworkHandlesBack)
        }
        // Разные affinity хостов не дают NEW_TASK унаследовать разделённое окно.
        // https://developer.android.com/guide/components/activities/tasks-and-back-stack#HandleAffinities
        intent.addFlags(
            if (task == null) Intent.FLAG_ACTIVITY_NEW_TASK
            else Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        if (task == null) {
            // Независимый контекст сохраняет дисплей, исключая размеры исходной Activity.
            // https://developer.android.com/reference/android/content/Context#startActivity(android.content.Intent)
            activity.createDisplayContext(activity.windowManager.defaultDisplay).startActivity(intent)
        } else {
            // AppTask направляет Intent в найденную задачу, независимо от задачи launcher.
            // https://developer.android.com/reference/android/app/ActivityManager.AppTask#startActivity(android.content.Context,android.content.Intent,android.os.Bundle)
            task.startActivity(activity, intent, null)
        }
    }

    private companion object {
        const val PREVIOUS_TASK_ID = "software.doable.doable.previousTaskId"
        const val FRAMEWORK_HANDLES_BACK = "software.doable.doable.frameworkHandlesBack"
    }
}
