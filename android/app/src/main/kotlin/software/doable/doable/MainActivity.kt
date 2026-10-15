package software.doable.doable

import android.app.Activity
import android.app.ActivityManager
import android.os.Bundle

class MainActivity : Activity() {
    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val policy = DisplayWindowPolicy(this)
        val existingHost = getSystemService(ActivityManager::class.java).appTasks
            .firstNotNullOfOrNull { task ->
                val info = task.taskInfo ?: return@firstNotNullOfOrNull null
                // После гибели процесса живая Activity отсутствует, но корневой Intent остаётся.
                val rootClass = (info.baseActivity ?: info.baseIntent.component)?.className
                DisplayCategory.entries
                    .find { it.activityClass.name == rootClass }
                    ?.let { it to task }
            }
        // Существующая Activity сама переносит движок, если дисплей сменился в фоне.
        policy.launch(
            existingHost?.first ?: policy.category(),
            task = existingHost?.second,
        )
        if (existingHost?.second?.taskInfo?.id == taskId) finish()
        else finishAndRemoveTask()
    }
}
