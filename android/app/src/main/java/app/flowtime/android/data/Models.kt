package app.flowtime.android.data

import java.time.LocalDate
import java.util.UUID

enum class TaskPriority(val label: String) {
    LOW("Low"), MEDIUM("Medium"), HIGH("High");

    companion object {
        fun from(value: String?): TaskPriority = entries.firstOrNull {
            it.label.equals(value, ignoreCase = true) || it.name.equals(value, ignoreCase = true)
        } ?: MEDIUM
    }
}

enum class TimerEndAlert(val storedName: String, val label: String, val description: String) {
    CLASSIC("Default", "Classic", "Alternating alarm"),
    TWS("TWS", "TWS", "Track-while-scan warning chirps"),
    MASTER_CAUTION("Master Caution", "Master Caution", "Four-beat caution warning"),
    MISSILE_LAUNCH("Missile Launch", "Missile Launch", "Rapid launch-warning siren"),
    RWR("RWR", "RWR", "Radar-warning receiver cadence");

    companion object {
        fun from(value: String?): TimerEndAlert = entries.firstOrNull {
            it.storedName.equals(value, ignoreCase = true) || it.name.equals(value, ignoreCase = true)
        } ?: when (value) {
            "TWS Launch 2" -> TWS
            "RWR Lock", "Jet Lock" -> RWR
            else -> CLASSIC
        }
    }
}

data class FlowTask(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val estimateMinutes: Int = 25,
    val done: Boolean = false,
    val category: String? = null,
    val priority: TaskPriority = TaskPriority.MEDIUM,
    val scheduledDay: Long = LocalDate.now().toEpochDay()
)

data class FlowEvent(
    val id: String = UUID.randomUUID().toString(),
    val startDay: Long,
    val endDay: Long,
    val category: String
) {
    fun occurs(day: Long): Boolean = day in startDay..endDay
}

data class FocusSession(
    val id: String = UUID.randomUUID().toString(),
    val completedAtMillis: Long = System.currentTimeMillis(),
    val durationSeconds: Int,
    val category: String?
)

data class TimerSnapshot(
    val selectedTaskId: String? = null,
    val isRunning: Boolean = false,
    val isRinging: Boolean = false,
    val targetSeconds: Int = 0,
    val remainingSeconds: Int = 0,
    val endAtMillis: Long? = null,
    val remainingByTask: Map<String, Int> = emptyMap()
)
