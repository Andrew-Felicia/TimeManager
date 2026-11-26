package app.flowtime.android.data

import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.flowtime.android.alarm.TimerAlarmService
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

class FlowtimeStore(application: Application) : AndroidViewModel(application) {
    private val preferences = application.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val zone: ZoneId get() = ZoneId.systemDefault()

    val tasks = mutableStateListOf<FlowTask>()
    val events = mutableStateListOf<FlowEvent>()
    val categories = mutableStateListOf<String>()
    val focusSessions = mutableStateListOf<FocusSession>()
    val remainingByTask = mutableStateMapOf<String, Int>()

    var selectedDay by mutableLongStateOf(LocalDate.now().toEpochDay())
    var darkTheme by mutableStateOf(true)
    var timerEndAlert by mutableStateOf(TimerEndAlert.CLASSIC)
        private set
    var selectedTaskId by mutableStateOf<String?>(null)
        private set
    var timerRunning by mutableStateOf(false)
        private set
    var timerRinging by mutableStateOf(false)
        private set
    var timerRemainingSeconds by mutableIntStateOf(0)
        private set
    private var timerTargetSeconds = 0
    private var timerEndAtMillis: Long? = null
    private var tickJob: Job? = null

    init {
        restore()
        synchronizeTaskTimers()
        reconcileTimer()
    }

    val activeTasks: List<FlowTask> get() = tasks.filterNot { it.done }
    val totalFocusSeconds: Int get() = focusSessions.sumOf { it.durationSeconds.coerceAtLeast(0) }

    fun setTheme(dark: Boolean) {
        darkTheme = dark
        persist()
    }

    fun setTimerAlert(alert: TimerEndAlert) {
        timerEndAlert = alert
        persist()
        if (timerRunning) startTimerService()
    }

    fun addCategory(rawName: String) {
        val name = rawName.trim()
        if (name.isEmpty() || categories.any { it.equals(name, true) }) return
        categories += name
        categories.sortWith(String.CASE_INSENSITIVE_ORDER)
        persist()
    }

    fun deleteCategory(category: String) {
        if (category !in categories) return
        categories.remove(category)
        if (categories.isEmpty()) categories += "Uncategorized"
        tasks.replaceAll { task -> if (task.category == category) task.copy(category = null) else task }
        events.replaceAll { event -> if (event.category == category) event.copy(category = categories.first()) else event }
        focusSessions.replaceAll { session -> if (session.category == category) session.copy(category = null) else session }
        persist()
    }

    fun addTask(title: String, estimateMinutes: Int, category: String?, priority: TaskPriority, scheduledDay: Long) {
        val cleanTitle = title.trim()
        if (cleanTitle.isEmpty()) return
        val task = FlowTask(
            title = cleanTitle,
            estimateMinutes = estimateMinutes.coerceIn(1, 1439),
            category = normalizeCategory(category),
            priority = priority,
            scheduledDay = scheduledDay
        )
        tasks.add(0, task)
        remainingByTask[task.id] = task.estimateMinutes * 60
        persist()
    }

    fun updateTask(updated: FlowTask) {
        val index = tasks.indexOfFirst { it.id == updated.id }
        if (index < 0 || updated.title.trim().isEmpty()) return
        val old = tasks[index]
        val clean = updated.copy(
            title = updated.title.trim(),
            estimateMinutes = updated.estimateMinutes.coerceIn(1, 1439),
            category = normalizeCategory(updated.category)
        )
        tasks[index] = clean
        val oldTarget = old.estimateMinutes * 60
        val newTarget = clean.estimateMinutes * 60
        val oldRemaining = remainingFor(old)
        val adjusted = (newTarget - (oldTarget - oldRemaining).coerceAtLeast(0)).coerceAtLeast(0)
        remainingByTask[clean.id] = if (adjusted == 0) newTarget else adjusted
        if (selectedTaskId == clean.id) {
            timerTargetSeconds = newTarget
            timerRemainingSeconds = remainingByTask[clean.id] ?: newTarget
            if (timerRunning) {
                timerEndAtMillis = System.currentTimeMillis() + timerRemainingSeconds * 1000L
                startTimerService()
            }
        }
        persist()
    }

    fun toggleTask(task: FlowTask) {
        val index = tasks.indexOfFirst { it.id == task.id }
        if (index < 0) return
        val next = tasks[index].copy(done = !tasks[index].done)
        tasks[index] = next
        if (next.done) removeTimer(next.id)
        persist()
    }

    fun deleteTask(task: FlowTask) {
        removeTimer(task.id)
        tasks.removeAll { it.id == task.id }
        persist()
    }

    fun addEvent(startDay: Long, endDay: Long, category: String) {
        val clean = category.trim()
        if (clean.isEmpty()) return
        val end = endDay.coerceAtLeast(startDay)
        events += FlowEvent(startDay = startDay, endDay = end, category = clean)
        if (categories.none { it.equals(clean, true) }) categories += clean
        persist()
    }

    fun deleteEvent(event: FlowEvent) {
        events.removeAll { it.id == event.id }
        persist()
    }

    fun eventsOn(day: Long): List<FlowEvent> = events.filter { it.occurs(day) }.sortedBy { it.startDay }

    fun remainingFor(task: FlowTask): Int {
        val target = task.estimateMinutes * 60
        return if (selectedTaskId == task.id) timerRemainingSeconds.coerceIn(0, target)
        else (remainingByTask[task.id] ?: target).coerceIn(0, target)
    }

    fun isRunning(task: FlowTask): Boolean = timerRunning && selectedTaskId == task.id

    fun toggleTimer(task: FlowTask) {
        if (task.done) return
        if (isRunning(task)) pauseTimer() else startTimer(task)
    }

    fun resetTimer(task: FlowTask) {
        if (selectedTaskId == task.id) {
            timerRunning = false
            timerRinging = false
            timerEndAtMillis = null
            timerTargetSeconds = task.estimateMinutes * 60
            timerRemainingSeconds = timerTargetSeconds
            stopTimerService()
            stopTicker()
        }
        remainingByTask[task.id] = task.estimateMinutes * 60
        persist()
    }

    private fun startTimer(task: FlowTask) {
        if (timerRunning) pauseTimer()
        selectedTaskId?.let { remainingByTask[it] = timerRemainingSeconds }
        val target = task.estimateMinutes * 60
        var remaining = remainingByTask[task.id] ?: target
        if (remaining <= 0 || remaining > target) remaining = target
        selectedTaskId = task.id
        timerTargetSeconds = target
        timerRemainingSeconds = remaining
        timerEndAtMillis = System.currentTimeMillis() + remaining * 1000L
        timerRunning = true
        timerRinging = false
        remainingByTask[task.id] = remaining
        startTicker()
        startTimerService()
        persist()
    }

    private fun pauseTimer() {
        reconcileTimer()
        if (!timerRunning) return
        timerRunning = false
        timerEndAtMillis = null
        selectedTaskId?.let { remainingByTask[it] = timerRemainingSeconds }
        stopTicker()
        stopTimerService()
        persist()
    }

    fun reconcileTimer() {
        if (!timerRunning) return
        val end = timerEndAtMillis ?: return
        val remaining = ((end - System.currentTimeMillis() + 999) / 1000).toInt().coerceAtLeast(0)
        timerRemainingSeconds = remaining
        selectedTaskId?.let { remainingByTask[it] = remaining }
        if (remaining == 0) finishTimer()
    }

    private fun finishTimer() {
        if (!timerRunning) return
        val selected = activeTasks.firstOrNull { it.id == selectedTaskId }
        focusSessions += FocusSession(
            durationSeconds = timerTargetSeconds.coerceAtLeast(1),
            category = selected?.category
        )
        timerRunning = false
        timerRinging = true
        timerEndAtMillis = null
        timerRemainingSeconds = 0
        selectedTaskId?.let { remainingByTask[it] = 0 }
        stopTicker()
        persist()
    }

    fun stopAlarm() {
        timerRinging = false
        selectedTaskId?.let { id ->
            tasks.firstOrNull { it.id == id }?.let { remainingByTask[id] = it.estimateMinutes * 60 }
        }
        timerRemainingSeconds = selectedTaskId?.let { id -> remainingByTask[id] } ?: 0
        stopTimerService()
        persist()
    }

    private fun removeTimer(taskId: String) {
        remainingByTask.remove(taskId)
        if (selectedTaskId != taskId) return
        timerRunning = false
        timerRinging = false
        selectedTaskId = null
        timerTargetSeconds = 0
        timerRemainingSeconds = 0
        timerEndAtMillis = null
        stopTicker()
        stopTimerService()
    }

    private fun startTicker() {
        tickJob?.cancel()
        tickJob = viewModelScope.launch {
            while (isActive && timerRunning) {
                reconcileTimer()
                delay(250)
            }
        }
    }

    private fun stopTicker() {
        tickJob?.cancel()
        tickJob = null
    }

    private fun startTimerService() {
        val end = timerEndAtMillis ?: return
        val taskTitle = tasks.firstOrNull { it.id == selectedTaskId }?.title ?: "Focus timer"
        val intent = TimerAlarmService.scheduleIntent(
            getApplication(),
            end,
            taskTitle,
            timerEndAlert,
            timerRemainingSeconds
        )
        ContextCompat.startForegroundService(getApplication(), intent)
    }

    private fun stopTimerService() {
        getApplication<Application>().startService(TimerAlarmService.stopIntent(getApplication()))
    }

    fun focusSecondsBetween(startMillis: Long, endMillis: Long): Int = focusSessions
        .filter { it.completedAtMillis in startMillis until endMillis }
        .sumOf { it.durationSeconds }

    fun focusByCategory(startMillis: Long, endMillis: Long): Map<String, Int> = focusSessions
        .filter { it.completedAtMillis in startMillis until endMillis }
        .groupBy { it.category?.takeIf(String::isNotBlank) ?: "Other" }
        .mapValues { (_, values) -> values.sumOf { it.durationSeconds } }

    fun updateSession(session: FocusSession) {
        val index = focusSessions.indexOfFirst { it.id == session.id }
        if (index < 0) return
        focusSessions[index] = session.copy(durationSeconds = session.durationSeconds.coerceAtLeast(1))
        persist()
    }

    fun deleteSession(session: FocusSession) {
        focusSessions.removeAll { it.id == session.id }
        persist()
    }

    fun exportJson(): String = archiveJson().toString(2)

    fun importJson(raw: String) {
        val root = JSONObject(raw)
        require(root.optInt("formatVersion", 1) == 1) { "This backup version is not supported." }
        restoreFromArchive(root)
        persist()
    }

    private fun persist() {
        preferences.edit { putString(ARCHIVE_KEY, archiveJson().toString()) }
    }

    private fun restore() {
        val raw = preferences.getString(ARCHIVE_KEY, null)
        if (raw != null) {
            runCatching { restoreFromArchive(JSONObject(raw)) }.onSuccess { return }
        }
        categories.addAll(listOf("Work", "Personal", "Focus time"))
        tasks.addAll(
            listOf(
                FlowTask(id = "t1", title = "Review project brief", estimateMinutes = 10),
                FlowTask(id = "t2", title = "Book dentist", estimateMinutes = 5),
                FlowTask(id = "t3", title = "Prepare weekly notes", estimateMinutes = 30)
            )
        )
        persist()
    }

    private fun synchronizeTaskTimers() {
        val activeIds = activeTasks.mapTo(mutableSetOf()) { it.id }
        remainingByTask.keys.toList().filterNot(activeIds::contains).forEach(remainingByTask::remove)
        activeTasks.forEach { remainingByTask.putIfAbsent(it.id, it.estimateMinutes * 60) }
    }

    private fun normalizeCategory(value: String?): String? {
        val clean = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return categories.firstOrNull { it.equals(clean, true) } ?: clean.also { categories += it }
    }

    private fun archiveJson(): JSONObject {
        val formatter = DateTimeFormatter.ISO_INSTANT
        // Match Foundation's ISO-8601 JSON dates so backups move cleanly between Android and iPhone.
        fun instant(millis: Long) = formatter.format(Instant.ofEpochSecond(millis / 1000))
        fun dayInstant(day: Long) = instant(LocalDate.ofEpochDay(day).atStartOfDay(zone).toInstant().toEpochMilli())

        return JSONObject().apply {
            put("formatVersion", 1)
            put("exportedAt", instant(System.currentTimeMillis()))
            put("appVersion", "1.0")
            put("selectedCalendarDate", dayInstant(selectedDay))
            put("categories", JSONArray(categories))
            put("tasks", JSONArray().apply {
                tasks.forEach { task ->
                    put(JSONObject().apply {
                        put("id", task.id)
                        put("title", task.title)
                        put("estimate", task.estimateMinutes)
                        put("done", task.done)
                        put("category", task.category ?: JSONObject.NULL)
                        put("priority", task.priority.label)
                        put("scheduledAt", dayInstant(task.scheduledDay))
                    })
                }
            })
            put("calendarEvents", JSONArray().apply {
                events.forEach { event ->
                    put(JSONObject().apply {
                        put("id", event.id)
                        put("title", event.category)
                        put("startsAt", dayInstant(event.startDay))
                        put("endsAt", dayInstant(event.endDay + 1))
                        put("category", event.category)
                        put("isAllDay", true)
                    })
                }
            })
            put("insights", JSONObject().apply {
                put("totalFocusSeconds", totalFocusSeconds)
                put("focusSessions", JSONArray().apply {
                    focusSessions.forEach { session ->
                        put(JSONObject().apply {
                            put("id", session.id)
                            put("completedAt", instant(session.completedAtMillis))
                            put("durationSeconds", session.durationSeconds)
                            put("category", session.category ?: JSONObject.NULL)
                        })
                    }
                })
            })
            put("timer", JSONObject().apply {
                put("selectedTaskId", selectedTaskId ?: JSONObject.NULL)
                put("isRunning", timerRunning)
                put("isRinging", timerRinging)
                put("targetSeconds", timerTargetSeconds)
                put("remainingSeconds", timerRemainingSeconds)
                put("scheduledEndDate", timerEndAtMillis?.let(::instant) ?: JSONObject.NULL)
                put("remainingSecondsByTask", JSONObject(remainingByTask.toMap()))
            })
            put("settings", JSONObject().apply {
                put("appearance", if (darkTheme) "Dark" else "Light")
                put("timerEndAlert", timerEndAlert.storedName)
            })
        }
    }

    private fun restoreFromArchive(root: JSONObject) {
        fun parseInstant(value: String?): Long? = value?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
        fun parseDay(value: String?): Long = parseInstant(value)?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalDate().toEpochDay() }
            ?: LocalDate.now().toEpochDay()
        fun JSONObject.nullableString(key: String): String? = if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }

        categories.clear()
        root.optJSONArray("categories")?.let { array ->
            repeat(array.length()) { index -> array.optString(index).takeIf(String::isNotBlank)?.let(categories::add) }
        }
        if (categories.isEmpty()) categories += "Uncategorized"

        tasks.clear()
        root.optJSONArray("tasks")?.let { array ->
            repeat(array.length()) { index ->
                val item = array.getJSONObject(index)
                tasks += FlowTask(
                    id = item.optString("id", UUID.randomUUID().toString()),
                    title = item.optString("title", "Task"),
                    estimateMinutes = item.optInt("estimate", 25).coerceIn(1, 1439),
                    done = item.optBoolean("done", false),
                    category = item.nullableString("category"),
                    priority = TaskPriority.from(item.optString("priority")),
                    scheduledDay = parseDay(item.optString("scheduledAt"))
                )
            }
        }

        events.clear()
        root.optJSONArray("calendarEvents")?.let { array ->
            repeat(array.length()) { index ->
                val item = array.getJSONObject(index)
                val start = parseDay(item.optString("startsAt"))
                val exclusiveEnd = parseDay(item.optString("endsAt"))
                events += FlowEvent(
                    id = item.optString("id", UUID.randomUUID().toString()),
                    startDay = start,
                    endDay = (exclusiveEnd - 1).coerceAtLeast(start),
                    category = item.optString("category", item.optString("title", "Event"))
                )
            }
        }

        focusSessions.clear()
        root.optJSONObject("insights")?.optJSONArray("focusSessions")?.let { array ->
            repeat(array.length()) { index ->
                val item = array.getJSONObject(index)
                focusSessions += FocusSession(
                    id = item.optString("id", UUID.randomUUID().toString()),
                    completedAtMillis = parseInstant(item.optString("completedAt")) ?: System.currentTimeMillis(),
                    durationSeconds = item.optInt("durationSeconds", 0).coerceAtLeast(0),
                    category = item.nullableString("category")
                )
            }
        }

        selectedDay = parseDay(root.optString("selectedCalendarDate"))
        val settings = root.optJSONObject("settings")
        darkTheme = !settings?.optString("appearance", "Dark").equals("Light", true)
        timerEndAlert = TimerEndAlert.from(settings?.optString("timerEndAlert"))

        remainingByTask.clear()
        val timer = root.optJSONObject("timer")
        timer?.optJSONObject("remainingSecondsByTask")?.let { map ->
            map.keys().forEach { key -> remainingByTask[key] = map.optInt(key, 0).coerceAtLeast(0) }
        }
        selectedTaskId = timer?.nullableString("selectedTaskId")?.takeIf { id -> tasks.any { it.id == id && !it.done } }
        timerTargetSeconds = timer?.optInt("targetSeconds", 0)?.coerceAtLeast(0) ?: 0
        timerRemainingSeconds = timer?.optInt("remainingSeconds", 0)?.coerceAtLeast(0) ?: 0
        timerEndAtMillis = parseInstant(timer?.nullableString("scheduledEndDate"))
        timerRunning = timer?.optBoolean("isRunning", false) == true && selectedTaskId != null && timerEndAtMillis != null
        timerRinging = timer?.optBoolean("isRinging", false) == true
        synchronizeTaskTimers()
        if (timerRunning) {
            startTicker()
            startTimerService()
        }
    }

    companion object {
        private const val PREFERENCES = "flowtime.android"
        private const val ARCHIVE_KEY = "flowtime.archive.v1"
    }
}
