package software.doable.doable

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.Rect
import android.os.Build
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAppTask
import org.robolectric.shadows.ShadowDisplayManager
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 30, 35, 36])
class DisplayWindowPolicyTest {
    @Test
    fun `Граница дисплея учитывает плотность и не зависит от поворота`() {
        assertEquals(DisplayCategory.PHONE, DisplayCategory.fromPixels(1199, 1800, 320))
        assertEquals(DisplayCategory.LARGE, DisplayCategory.fromPixels(1200, 1800, 320))
        assertEquals(DisplayCategory.LARGE, DisplayCategory.fromPixels(1800, 1200, 320))
    }

    @Test
    @Config(qualifiers = "w599dp-h900dp-mdpi")
    fun `Холодный запуск выбирает телефонную Activity до запуска Flutter`() {
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        controller.create()
        val activity = controller.get()
        val launch = shadowOf(activity).nextStartedActivity

        assertEquals(PhoneActivity::class.java.name, launch.component!!.className)
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_CLEAR_TASK != 0)
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        assertTrue(activity.isFinishing)
        controller.destroy()
    }

    @Test
    @Config(qualifiers = "w600dp-h900dp-mdpi")
    fun `Холодный запуск на границе выбирает большую Activity`() {
        val controller = Robolectric.buildActivity(MainActivity::class.java).create()
        val launch = shadowOf(controller.get()).nextStartedActivity

        assertEquals(LargeDisplayActivity::class.java.name, launch.component!!.className)
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
    @Config(qualifiers = "w800dp-h1200dp-mdpi")
    fun `Смена категории заменяет корень задачи и переносит двигатель один раз`() {
        val controller = Robolectric.buildActivity(Activity::class.java).create()
        val activity = controller.get()
        var transfers = 0

        val policy = DisplayWindowPolicy(activity)
        policy.replaceIfNeeded(DisplayCategory.PHONE) {
            transfers++
            "engine"
        }
        val launch = shadowOf(activity).nextStartedActivity
        assertEquals(LargeDisplayActivity::class.java.name, launch.component!!.className)
        assertEquals("engine", launch.getStringExtra("cached_engine_id"))
        assertTrue(launch.getBooleanExtra("destroy_engine_with_activity", false))
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_CLEAR_TASK != 0)
        assertTrue(launch.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        assertEquals(1, transfers)

        policy.replaceIfNeeded(DisplayCategory.LARGE) {
            throw AssertionError("Одинаковая категория не переносит двигатель")
        }
        assertNull(shadowOf(activity).nextStartedActivity)
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
            id = activity.taskId
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
    fun `Складывание того же дисплея меняет большую политику на телефонную`() {
        val controller = Robolectric.buildActivity(Activity::class.java).create()
        val activity = controller.get()
        val policy = DisplayWindowPolicy(activity)
        assertEquals(DisplayCategory.LARGE, policy.category())

        ShadowDisplayManager.changeDisplay(Display.DEFAULT_DISPLAY, "w599dp-h900dp-mdpi")
        // При складывании система обновляет и дисплей, и конфигурацию ресурсов.
        RuntimeEnvironment.setQualifiers("w599dp-h900dp-mdpi")
        policy.invalidateDisplay()

        policy.replaceIfNeeded(DisplayCategory.LARGE) { "engine" }
        assertEquals(
            PhoneActivity::class.java.name,
            shadowOf(activity).nextStartedActivity.component!!.className,
        )
        controller.destroy()
    }
}
