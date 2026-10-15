package software.doable.doable

import android.app.Activity
import android.app.ActivityManager
import android.app.Instrumentation
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowAppTask
import org.robolectric.shadows.ShadowDisplayManager
import org.robolectric.shadows.ShadowInstrumentation
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 30, 35, 36])
class DisplayWindowPolicyTest {
    @Test
    fun `Хосты и временный launcher принадлежат разным задачам`() {
        val context = RuntimeEnvironment.getApplication()
        val affinities = listOf(
            MainActivity::class.java, PhoneActivity::class.java, LargeDisplayActivity::class.java,
        ).map {
            context.packageManager.getActivityInfo(ComponentName(context, it), 0).taskAffinity
        }

        assertEquals(3, affinities.toSet().size)
    }

    @Test
    fun `Граница дисплея учитывает плотность и не зависит от поворота`() {
        assertEquals(DisplayCategory.PHONE, DisplayCategory.fromPixels(1199, 1800, 320))
        assertEquals(DisplayCategory.LARGE, DisplayCategory.fromPixels(1200, 1800, 320))
        assertEquals(DisplayCategory.LARGE, DisplayCategory.fromPixels(1800, 1200, 320))
    }

    @Test
    @Config(qualifiers = "w599dp-h900dp-mdpi", shadows = [LaunchSourceInstrumentation::class])
    fun `Холодный запуск выбирает телефонную Activity до запуска Flutter`() {
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        controller.create()
        val activity = controller.get()
        val launch = shadowOf(activity).nextStartedActivity

        assertEquals(PhoneActivity::class.java.name, launch.component!!.className)
        assertEquals(0, launch.flags and Intent.FLAG_ACTIVITY_CLEAR_TASK)
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        assertNull(Shadow.extract<LaunchSourceInstrumentation>(
            ShadowInstrumentation.getInstrumentation(),
        ).sourceToken)
        assertTrue(activity.isFinishing)
        controller.destroy()
    }

    @Test
    @Config(qualifiers = "w600dp-h900dp-mdpi", shadows = [LaunchSourceInstrumentation::class])
    fun `Холодный запуск большой Activity сохраняет связь с исходной Activity и задачей`() {
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        val activity = controller.get()
        assertTrue(activity.getSystemService(ActivityManager::class.java).appTasks.isEmpty())

        controller.create()
        val launch = shadowOf(activity).nextStartedActivity
        val instrumentation = Shadow.extract<LaunchSourceInstrumentation>(
            ShadowInstrumentation.getInstrumentation(),
        )

        assertEquals(LargeDisplayActivity::class.java.name, launch.component!!.className)
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        assertNotNull("Android должен получить токен исходной Activity", instrumentation.sourceToken)
        assertEquals(activity.taskId, instrumentation.sourceTaskId)
        controller.destroy()
    }

    @Test
    @Config(qualifiers = "w800dp-h1200dp-mdpi")
    fun `Узкое окно планшета не получает телефонную политику`() {
        val controller = Robolectric.buildActivity(Activity::class.java).create()
        val activity = controller.get()
        val configuration = activity.resources.configuration
        configuration.screenWidthDp = 320
        if (Build.VERSION.SDK_INT >= 28) {
            val windowConfiguration = ReflectionHelpers.getField<Any>(
                configuration, "windowConfiguration",
            )
            ReflectionHelpers.callInstanceMethod<Void>(
                windowConfiguration,
                "setBounds",
                ClassParameter.from(Rect::class.java, Rect(0, 0, 320, 1200)),
            )
        }

        assertEquals(DisplayCategory.LARGE, DisplayWindowPolicy(activity).category())
        controller.destroy()
    }

    @Test
    @Config(qualifiers = "w800dp-h1200dp-mdpi", shadows = [LaunchSourceInstrumentation::class])
    fun `Смена категории передаёт двигатель в отдельную задачу до удаления исходной`() {
        val controller = Robolectric.buildActivity(Activity::class.java).create()
        val activity = controller.get()
        var transfers = 0

        val policy = DisplayWindowPolicy(activity)
        policy.replaceIfNeeded(DisplayCategory.PHONE) {
            transfers++
            RetainedDisplayEngine("engine", frameworkHandlesBack = true)
        }
        val launch = shadowOf(activity).nextStartedActivity
        assertEquals(LargeDisplayActivity::class.java.name, launch.component!!.className)
        assertEquals("engine", launch.getStringExtra("cached_engine_id"))
        assertTrue(launch.getBooleanExtra("destroy_engine_with_activity", false))
        assertEquals(0, launch.flags and Intent.FLAG_ACTIVITY_CLEAR_TASK)
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        val instrumentation = Shadow.extract<LaunchSourceInstrumentation>(
            ShadowInstrumentation.getInstrumentation(),
        )
        assertNull(instrumentation.sourceToken)
        assertNull(instrumentation.sourceTaskId)
        assertFalse(activity.isFinishing)
        assertEquals(1, transfers)

        val sourceTask = ShadowAppTask.newInstance()
        shadowOf(sourceTask).setTaskInfo(ActivityManager.RecentTaskInfo().apply {
            id = activity.taskId
            baseActivity = ComponentName(activity, PhoneActivity::class.java)
        })
        val targetController = Robolectric.buildActivity(Activity::class.java, launch).create()
        val targetActivity = targetController.get()
        shadowOf(targetActivity.getSystemService(ActivityManager::class.java))
            .setAppTasks(listOf(sourceTask))
        assertFalse(shadowOf(sourceTask).isFinishedAndRemoved)

        DisplayWindowPolicy(targetActivity).completeTransfer()
        assertTrue(shadowOf(sourceTask).isFinishedAndRemoved)
        targetController.destroy()

        policy.replaceIfNeeded(DisplayCategory.LARGE) {
            throw AssertionError("Одинаковая категория не переносит двигатель")
        }
        assertNull(shadowOf(activity).nextStartedActivity)
        controller.destroy()
    }

    @Test
    @Config(qualifiers = "w800dp-h1200dp-mdpi")
    fun `Перенос передаёт готовность Flutter вместе с двигателем только первому созданию хоста`() {
        val controller = Robolectric.buildActivity(Activity::class.java).create()
        val activity = controller.get()
        val policy = DisplayWindowPolicy(activity)

        for (handlesBack in listOf(true, false)) {
            policy.replaceIfNeeded(DisplayCategory.PHONE) {
                RetainedDisplayEngine("engine", frameworkHandlesBack = handlesBack)
            }
            val launch = shadowOf(activity).nextStartedActivity
            assertEquals("engine", launch.getStringExtra("cached_engine_id"))
            val target = Robolectric.buildActivity(Activity::class.java, launch).create()
            val targetPolicy = DisplayWindowPolicy(target.get())

            assertEquals(handlesBack, targetPolicy.takeTransferredFrameworkHandlesBack())
            // При пересоздании используется свежий savedInstanceState самого Flutter.
            assertNull(targetPolicy.takeTransferredFrameworkHandlesBack())
            target.destroy()
        }

        policy.launch(DisplayCategory.LARGE)
        val cold = Robolectric.buildActivity(
            Activity::class.java, shadowOf(activity).nextStartedActivity,
        ).create()
        assertNull(DisplayWindowPolicy(cold.get()).takeTransferredFrameworkHandlesBack())
        cold.destroy()
        controller.destroy()
    }

    @Test
    @Suppress("DEPRECATION")
    @Config(qualifiers = "w800dp-h1200dp-mdpi")
    fun `Launcher возвращает существующий корень для сохранения состояния при смене дисплея`() {
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        val activity = controller.get()
        val task = ShadowAppTask.newInstance()
        shadowOf(task).setTaskInfo(ActivityManager.RecentTaskInfo().apply {
            id = activity.taskId + 1
            baseActivity = ComponentName(activity, PhoneActivity::class.java)
        })
        shadowOf(activity.getSystemService(ActivityManager::class.java)).setAppTasks(listOf(task))

        controller.create()
        val launch = shadowOf(activity).nextStartedActivity
        assertEquals(PhoneActivity::class.java.name, launch.component!!.className)
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
        assertEquals(0, launch.flags and Intent.FLAG_ACTIVITY_CLEAR_TASK)
        controller.destroy()
    }

    @Test
    fun `После гибели процесса восстановление не требует исчезнувшего кэша двигателя`() {
        val context = RuntimeEnvironment.getApplication()
        val intent = FlutterActivity.CachedEngineIntentBuilder(
            PhoneActivity::class.java, "lost-engine",
        ).destroyEngineWithActivity(true).build(context)
        val activity = Robolectric.buildActivity(PhoneActivity::class.java, intent).get()

        assertNull(activity.cachedEngineId)
    }

    @Test
    @Config(qualifiers = "w800dp-h1200dp-mdpi")
    fun `Launcher восстанавливает прежнюю задачу без живой Activity после гибели процесса`() {
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        val activity = controller.get()
        val task = ShadowAppTask.newInstance()
        shadowOf(task).setTaskInfo(ActivityManager.RecentTaskInfo().apply {
            id = -1
            baseIntent = Intent(activity, PhoneActivity::class.java)
        })
        shadowOf(activity.getSystemService(ActivityManager::class.java)).setAppTasks(listOf(task))

        controller.create()
        val launch = shadowOf(activity).nextStartedActivity
        assertEquals(PhoneActivity::class.java.name, launch.component!!.className)
        assertEquals(0, launch.flags and Intent.FLAG_ACTIVITY_NEW_TASK)
        assertNull(launch.getStringExtra("cached_engine_id"))
        controller.destroy()
    }

    @Test
    @Config(qualifiers = "w800dp-h1200dp-mdpi")
    fun `Складывание того же дисплея меняет большую политику на телефонную`() {
        val controller = Robolectric.buildActivity(Activity::class.java).create()
        val activity = controller.get()
        val policy = DisplayWindowPolicy(activity)
        assertEquals(DisplayCategory.LARGE, policy.category())

        ShadowDisplayManager.changeDisplay(Display.DEFAULT_DISPLAY, "w599dp-h900dp-mdpi")
        // При складывании система обновляет и дисплей, и конфигурацию ресурсов.
        RuntimeEnvironment.setQualifiers("w599dp-h900dp-mdpi")
        policy.invalidateDisplay()

        policy.replaceIfNeeded(DisplayCategory.LARGE) {
            RetainedDisplayEngine("engine", frameworkHandlesBack = false)
        }
        assertEquals(
            PhoneActivity::class.java.name,
            shadowOf(activity).nextStartedActivity.component!!.className,
        )
        controller.destroy()
    }

    @Implements(Instrumentation::class)
    class LaunchSourceInstrumentation : ShadowInstrumentation() {
        var sourceToken: IBinder? = null
        var sourceTaskId: Int? = null

        @Implementation
        override fun execStartActivity(
            who: Context,
            contextThread: IBinder?,
            token: IBinder?,
            target: Activity?,
            intent: Intent,
            requestCode: Int,
            options: Bundle?,
        ): Instrumentation.ActivityResult? {
            sourceToken = token
            sourceTaskId = target?.taskId
            return super.execStartActivity(
                who, contextThread, token, target, intent, requestCode, options,
            )
        }
    }
}
