package software.doable.doable

import android.app.Activity
import android.app.ActivityManager
import android.os.Bundle

class MainActivity : Activity() {
    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val policy = DisplayWindowPolicy(this)
        val rootClass = getSystemService(ActivityManager::class.java).appTasks
            .map { it.taskInfo }
            .firstOrNull { it.id == taskId }
            ?.baseActivity?.className
        val existingHost = DisplayCategory.entries.find { it.activityClass.name == rootClass }
        // Существующая Activity сама переносит движок, если дисплей сменился в фоне.
        policy.launch(
            existingHost ?: policy.category(),
            replaceTask = existingHost == null,
        )
        finish()
    }
}
