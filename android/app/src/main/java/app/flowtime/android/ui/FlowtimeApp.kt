package app.flowtime.android.ui

import android.content.Context
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.TaskAlt
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.flowtime.android.data.FlowEvent
import app.flowtime.android.data.FlowTask
import app.flowtime.android.data.FlowtimeStore
import app.flowtime.android.data.FocusSession
import app.flowtime.android.data.TaskPriority
import app.flowtime.android.data.TimerEndAlert
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlin.math.abs
import kotlin.math.ceil

private enum class MainTab(val label: String, val icon: ImageVector) {
    TODAY("Today", Icons.Default.CalendarMonth),
    TASKS("Tasks", Icons.Default.TaskAlt),
    FOCUS("Focus", Icons.Default.Timer),
    INSIGHTS("Insights", Icons.Default.Analytics)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlowtimeApp(store: FlowtimeStore) {
    var tab by remember { mutableStateOf(MainTab.TODAY) }
    var showSettings by remember { mutableStateOf(false) }

    if (showSettings) {
        BackHandler { showSettings = false }
        SettingsScreen(store = store, onBack = { showSettings = false })
        return
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar(modifier = Modifier.navigationBarsPadding()) {
                MainTab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = tab == item,
                        onClick = { tab = item },
                        icon = { Icon(item.icon, contentDescription = item.label) },
                        label = { Text(item.label) }
                    )
                }
            }
        }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (tab) {
                MainTab.TODAY -> TodayScreen(store)
                MainTab.TASKS -> TasksScreen(store)
                MainTab.FOCUS -> FocusScreen(store)
                MainTab.INSIGHTS -> InsightsScreen(store, onOpenSettings = { showSettings = true })
            }
        }
    }
}

// MARK: Calendar

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TodayScreen(store: FlowtimeStore) {
    var shownMonth by remember(store.selectedDay) { mutableStateOf(YearMonth.from(LocalDate.ofEpochDay(store.selectedDay))) }
    var addingEvent by remember { mutableStateOf(false) }
    val selectedDate = LocalDate.ofEpochDay(store.selectedDay)
    val selectedEvents = store.eventsOn(store.selectedDay)

    Scaffold(
        topBar = { TopAppBar(title = { Text("Today", fontWeight = FontWeight.Bold) }) },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { addingEvent = true },
                icon = { Icon(Icons.Default.Add, null) },
                text = { Text("New Event") }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                Card(shape = RoundedCornerShape(24.dp)) {
                    Column(Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { shownMonth = shownMonth.minusMonths(1) }) {
                                Icon(Icons.Default.ChevronLeft, "Previous month")
                            }
                            Text(
                                shownMonth.format(DateTimeFormatter.ofPattern("MMMM yyyy")),
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.weight(1f)
                            )
                            IconButton(onClick = { shownMonth = shownMonth.plusMonths(1) }) {
                                Icon(Icons.Default.ChevronRight, "Next month")
                            }
                        }
                        CalendarMonthGrid(
                            month = shownMonth,
                            selectedDay = store.selectedDay,
                            events = store.events,
                            onSelect = { store.selectedDay = it }
                        )
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        selectedDate.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL)),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        if (selectedEvents.isEmpty()) "No events" else "${selectedEvents.size} event${if (selectedEvents.size == 1) "" else "s"}",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            items(selectedEvents, key = { it.id }) { event -> EventCard(event, store::deleteEvent) }
        }
    }

    if (addingEvent) {
        EventEditorDialog(
            initialDay = store.selectedDay,
            categories = store.categories,
            onDismiss = { addingEvent = false },
            onSave = { start, end, category ->
                store.addEvent(start, end, category)
                store.selectedDay = start
                shownMonth = YearMonth.from(LocalDate.ofEpochDay(start))
                addingEvent = false
            }
        )
    }
}

@Composable
private fun CalendarMonthGrid(
    month: YearMonth,
    selectedDay: Long,
    events: List<FlowEvent>,
    onSelect: (Long) -> Unit
) {
    val weekdays = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    Row(Modifier.fillMaxWidth()) {
        weekdays.forEach { day ->
            Text(
                day,
                modifier = Modifier.weight(1f).padding(vertical = 10.dp),
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
    val offset = month.atDay(1).dayOfWeek.value - 1
    val cellCount = (ceil((offset + month.lengthOfMonth()) / 7.0) * 7).toInt()
    repeat(cellCount / 7) { rowIndex ->
        Row(Modifier.fillMaxWidth()) {
            repeat(7) { column ->
                val dayNumber = rowIndex * 7 + column - offset + 1
                if (dayNumber !in 1..month.lengthOfMonth()) {
                    Spacer(Modifier.weight(1f).aspectRatio(1f))
                } else {
                    val date = month.atDay(dayNumber)
                    val epochDay = date.toEpochDay()
                    val hasEvents = events.any { it.occurs(epochDay) }
                    val selected = epochDay == selectedDay
                    Box(
                        modifier = Modifier.weight(1f).aspectRatio(1f).padding(2.dp)
                            .clip(CircleShape)
                            .background(if (selected) MaterialTheme.colorScheme.primary else Color.Transparent)
                            .clickable { onSelect(epochDay) },
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                dayNumber.toString(),
                                color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                                fontWeight = if (date == LocalDate.now()) FontWeight.Bold else FontWeight.Normal
                            )
                            Spacer(Modifier.height(3.dp))
                            Box(
                                Modifier.width(17.dp).height(3.dp).clip(CircleShape)
                                    .background(
                                        if (hasEvents) {
                                            if (selected) MaterialTheme.colorScheme.onPrimary else categoryColor(events.first { it.occurs(epochDay) }.category)
                                        } else Color.Transparent
                                    )
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EventCard(event: FlowEvent, onDelete: (FlowEvent) -> Unit) {
    OutlinedCard {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(5.dp).height(50.dp).clip(CircleShape).background(categoryColor(event.category)))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(event.category, fontWeight = FontWeight.SemiBold)
                Text(
                    dateRange(event.startDay, event.endDay),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = { onDelete(event) }) { Icon(Icons.Default.Delete, "Delete event") }
        }
    }
}

@Composable
private fun EventEditorDialog(
    initialDay: Long,
    categories: List<String>,
    onDismiss: () -> Unit,
    onSave: (Long, Long, String) -> Unit
) {
    var startDay by remember { mutableLongStateOf(initialDay) }
    var endDay by remember { mutableLongStateOf(initialDay) }
    var category by remember { mutableStateOf(categories.firstOrNull().orEmpty()) }
    var customCategory by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New Event") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                DateField("Starts date", startDay) {
                    startDay = it
                    if (endDay < it) endDay = it
                }
                DateField("Ends date", endDay.coerceAtLeast(startDay), minDay = startDay) { endDay = it }
                Text("Category", style = MaterialTheme.typography.labelLarge)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    categories.forEach { item ->
                        FilterChip(selected = category == item, onClick = { category = item; customCategory = "" }, label = { Text(item) })
                    }
                }
                OutlinedTextField(
                    value = customCategory,
                    onValueChange = { customCategory = it; if (it.isNotBlank()) category = it },
                    label = { Text("New category") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(startDay, endDay.coerceAtLeast(startDay), category.trim()) }, enabled = category.isNotBlank()) {
                Text("Add")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

// MARK: Tasks

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TasksScreen(store: FlowtimeStore) {
    var editing by remember { mutableStateOf<FlowTask?>(null) }
    var creating by remember { mutableStateOf(false) }
    var manageCategories by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Tasks", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { manageCategories = true }) { Icon(Icons.Default.Flag, "Manage categories") }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { creating = true }) { Icon(Icons.Default.Add, "New task") }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (store.activeTasks.isEmpty()) {
                item { EmptyState(Icons.Default.TaskAlt, "No Tasks", "Add something you plan to do and estimate how long it will take.") }
            } else {
                item { SectionLabel("TO DO", "${store.activeTasks.size}") }
                items(store.activeTasks, key = { it.id }) { task ->
                    TaskCard(task, onToggle = { store.toggleTask(task) }, onEdit = { editing = task }, onDelete = { store.deleteTask(task) })
                }
            }
            val completed = store.tasks.filter { it.done }
            if (completed.isNotEmpty()) {
                item { SectionLabel("COMPLETED", completed.size.toString()) }
                items(completed, key = { it.id }) { task ->
                    TaskCard(task, onToggle = { store.toggleTask(task) }, onEdit = { editing = task }, onDelete = { store.deleteTask(task) })
                }
            }
        }
    }

    if (creating || editing != null) {
        TaskEditorDialog(
            existing = editing,
            categories = store.categories,
            onDismiss = { creating = false; editing = null },
            onManageCategories = { manageCategories = true },
            onSave = { title, minutes, category, priority, day ->
                editing?.let {
                    store.updateTask(it.copy(title = title, estimateMinutes = minutes, category = category, priority = priority, scheduledDay = day))
                } ?: store.addTask(title, minutes, category, priority, day)
                creating = false
                editing = null
            }
        )
    }
    if (manageCategories) {
        ManageCategoriesDialog(store, onDismiss = { manageCategories = false })
    }
}

@Composable
private fun TaskCard(task: FlowTask, onToggle: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(25.dp).clip(CircleShape)
                    .background(if (task.done) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant)
                    .clickable(onClick = onToggle),
                contentAlignment = Alignment.Center
            ) {
                if (task.done) Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(17.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(9.dp).clip(CircleShape).background(priorityColor(task.priority)))
                    Spacer(Modifier.width(7.dp))
                    Text(task.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(durationCompact(task.estimateMinutes * 60), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(LocalDate.ofEpochDay(task.scheduledDay).format(DateTimeFormatter.ofPattern("MMM d")), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(task.category ?: "Other", style = MaterialTheme.typography.bodySmall, color = categoryColor(task.category ?: "Other"))
                }
            }
            IconButton(onClick = onEdit) { Icon(Icons.Default.Edit, "Edit task") }
            IconButton(onClick = onDelete) { Icon(Icons.Default.Delete, "Delete task") }
        }
    }
}

@Composable
private fun TaskEditorDialog(
    existing: FlowTask?,
    categories: List<String>,
    onDismiss: () -> Unit,
    onManageCategories: () -> Unit,
    onSave: (String, Int, String?, TaskPriority, Long) -> Unit
) {
    var title by remember(existing) { mutableStateOf(existing?.title.orEmpty()) }
    var hours by remember(existing) { mutableIntStateOf((existing?.estimateMinutes ?: 25) / 60) }
    var minutes by remember(existing) { mutableIntStateOf((existing?.estimateMinutes ?: 25) % 60) }
    var category by remember(existing) { mutableStateOf(existing?.category) }
    var priority by remember(existing) { mutableStateOf(existing?.priority ?: TaskPriority.MEDIUM) }
    var day by remember(existing) { mutableLongStateOf(existing?.scheduledDay ?: LocalDate.now().toEpochDay()) }
    val totalMinutes = (hours * 60 + minutes).coerceIn(1, 1439)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (existing == null) "New Task" else "Edit Task") },
        text = {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                item {
                    OutlinedTextField(title, { title = it }, label = { Text("What do you want to do?") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                item {
                    Text("Estimated time", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(8.dp))
                    DurationWheelPicker(
                        hours = hours,
                        minutes = minutes,
                        onHoursChange = { hours = it },
                        onMinutesChange = { minutes = it }
                    )
                    Row(Modifier.padding(top = 8.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        listOf(5, 15, 20, 25, 30, 60, 120).forEach { preset ->
                            AssistChip(
                                onClick = { hours = preset / 60; minutes = preset % 60 },
                                label = { Text(if (preset < 60) "${preset}m" else "${preset / 60}h") }
                            )
                        }
                    }
                }
                item {
                    Text("Priority", style = MaterialTheme.typography.labelLarge)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TaskPriority.entries.forEach { item ->
                            FilterChip(
                                selected = priority == item,
                                onClick = { priority = item },
                                label = { Text(item.label) },
                                leadingIcon = { Box(Modifier.size(9.dp).clip(CircleShape).background(priorityColor(item))) }
                            )
                        }
                    }
                }
                item {
                    Text("Category", style = MaterialTheme.typography.labelLarge)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(selected = category == null, onClick = { category = null }, label = { Text("Other") })
                        categories.forEach { item ->
                            FilterChip(selected = category == item, onClick = { category = item }, label = { Text(item) })
                        }
                    }
                    TextButton(onClick = onManageCategories) { Text("Manage Categories") }
                }
                item { DateField("Planned day", day) { day = it } }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(title, totalMinutes, category, priority, day) }, enabled = title.isNotBlank() && hours * 60 + minutes > 0) {
                Text("Save")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DurationWheelPicker(
    hours: Int,
    minutes: Int,
    onHoursChange: (Int) -> Unit,
    onMinutesChange: (Int) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        NumberWheel(value = hours, range = 0..23, label = "hours", onValueChange = onHoursChange)
        Text("h", modifier = Modifier.padding(horizontal = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        NumberWheel(value = minutes, range = 0..59, label = "minutes", onValueChange = onMinutesChange)
        Text("m", modifier = Modifier.padding(start = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NumberWheel(
    value: Int,
    range: IntRange,
    label: String,
    onValueChange: (Int) -> Unit
) {
    val values = remember(range.first, range.last) { range.toList() }
    val initialIndex = (value - range.first).coerceIn(values.indices)
    val state = rememberLazyListState(initialFirstVisibleItemIndex = initialIndex)
    val flingBehavior = rememberSnapFlingBehavior(lazyListState = state)
    val haptics = LocalHapticFeedback.current
    val currentValue by rememberUpdatedState(value)
    var hasInitialized by remember { mutableStateOf(false) }
    val centeredIndex by remember(state) {
        derivedStateOf {
            val layout = state.layoutInfo
            val viewportCenter = (layout.viewportStartOffset + layout.viewportEndOffset) / 2
            layout.visibleItemsInfo.minByOrNull { item ->
                abs((item.offset + item.size / 2) - viewportCenter)
            }?.index ?: state.firstVisibleItemIndex
        }
    }

    LaunchedEffect(value) {
        val targetIndex = (value - range.first).coerceIn(values.indices)
        if (targetIndex != centeredIndex && !state.isScrollInProgress) {
            state.animateScrollToItem(targetIndex)
        }
    }

    LaunchedEffect(state) {
        snapshotFlow { centeredIndex }
            .distinctUntilChanged()
            .collect { index ->
                val selected = values.getOrNull(index) ?: return@collect
                if (selected != currentValue) onValueChange(selected)
                if (hasInitialized) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                } else {
                    hasInitialized = true
                }
            }
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Box(
            modifier = Modifier.width(92.dp).height(156.dp),
            contentAlignment = Alignment.Center
        ) {
            Box(
                Modifier.fillMaxWidth().height(52.dp).clip(RoundedCornerShape(12.dp))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
            )
            LazyColumn(
                state = state,
                flingBehavior = flingBehavior,
                contentPadding = PaddingValues(vertical = 52.dp),
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                items(values.size) { index ->
                    val item = values[index]
                    Box(Modifier.fillMaxWidth().height(52.dp), contentAlignment = Alignment.Center) {
                        Text(
                            text = String.format(Locale.US, "%02d", item),
                            fontSize = if (item == value) 28.sp else 20.sp,
                            fontWeight = if (item == value) FontWeight.SemiBold else FontWeight.Normal,
                            color = if (item == value) MaterialTheme.colorScheme.onSurface
                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f)
                        )
                    }
                }
            }
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
                Spacer(Modifier.height(51.dp))
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
            }
        }
    }
}

@Composable
private fun NumberStepper(label: String, value: Int, range: IntRange, onChange: (Int) -> Unit) {
    Column(Modifier.width(130.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { onChange(if (value <= range.first) range.last else value - 1) }) { Text("−", fontSize = 23.sp) }
            Text(String.format(Locale.US, "%02d", value), fontSize = 24.sp, fontWeight = FontWeight.Bold)
            TextButton(onClick = { onChange(if (value >= range.last) range.first else value + 1) }) { Text("+", fontSize = 23.sp) }
        }
    }
}

@Composable
private fun ManageCategoriesDialog(store: FlowtimeStore, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Categories") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(name, { name = it }, label = { Text("New category") }, singleLine = true, modifier = Modifier.weight(1f))
                    IconButton(onClick = { store.addCategory(name); name = "" }, enabled = name.isNotBlank()) { Icon(Icons.Default.Add, "Add category") }
                }
                store.categories.forEach { category ->
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(10.dp).clip(CircleShape).background(categoryColor(category)))
                        Text(category, Modifier.padding(start = 10.dp).weight(1f))
                        IconButton(onClick = { store.deleteCategory(category) }) { Icon(Icons.Default.Delete, "Delete $category") }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } }
    )
}

// MARK: Focus

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FocusScreen(store: FlowtimeStore) {
    Scaffold(topBar = { TopAppBar(title = { Text("Focus", fontWeight = FontWeight.Bold) }) }) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            if (store.timerRinging) {
                item {
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                        Column(Modifier.fillMaxWidth().padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Timer Finished", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                            Text("Tap the alarm notification to stop the sound and vibration.", textAlign = TextAlign.Center)
                        }
                    }
                }
            }
            if (store.activeTasks.isEmpty()) {
                item { EmptyState(Icons.Default.Timer, "No Task Timers", "Add a task first. Every active task automatically appears here.") }
            } else {
                item {
                    Text("Choose a task to focus on", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                items(store.activeTasks, key = { it.id }) { task ->
                    FocusTimerCard(task, store)
                }
            }
        }
    }
}

@Composable
private fun FocusTimerCard(task: FlowTask, store: FlowtimeStore) {
    val remaining = store.remainingFor(task)
    val target = task.estimateMinutes * 60
    val progress = if (target > 0) remaining.toFloat() / target else 0f
    val running = store.isRunning(task)
    val started = remaining < target
    val trackColor = MaterialTheme.colorScheme.surfaceVariant
    val progressColor = MaterialTheme.colorScheme.primary

    Card(shape = RoundedCornerShape(24.dp)) {
        Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(priorityColor(task.priority)))
                Text(task.title, Modifier.padding(start = 8.dp).weight(1f), fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(task.category ?: "Other", style = MaterialTheme.typography.bodySmall, color = categoryColor(task.category ?: "Other"))
            }
            Spacer(Modifier.height(18.dp))
            Box(Modifier.size(190.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    drawArc(
                        color = trackColor,
                        startAngle = -90f,
                        sweepAngle = 360f,
                        useCenter = false,
                        style = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Round)
                    )
                    drawArc(
                        color = progressColor,
                        startAngle = -90f,
                        sweepAngle = 360f * progress,
                        useCenter = false,
                        style = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Round)
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(durationClock(remaining), fontSize = if (remaining >= 3600) 30.sp else 39.sp, fontWeight = FontWeight.Light)
                    Text(if (running) "FOCUSING" else if (started) "PAUSED" else durationCompact(target), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(18.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = { store.resetTimer(task) }, enabled = started && !store.timerRinging, shape = CircleShape, contentPadding = PaddingValues(14.dp)) {
                    Icon(Icons.Default.Refresh, "Reset")
                }
                Button(onClick = { store.toggleTimer(task) }, enabled = !store.timerRinging, shape = CircleShape, contentPadding = PaddingValues(19.dp)) {
                    Icon(if (running) Icons.Default.Pause else Icons.Default.PlayArrow, if (running) "Pause" else "Start", modifier = Modifier.size(32.dp))
                }
            }
        }
    }
}

// MARK: Insights

private enum class InsightRange(val title: String) { DAY("Day"), WEEK("Week"), MONTH("Month"), YEAR("Year") }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InsightsScreen(store: FlowtimeStore, onOpenSettings: () -> Unit) {
    var range by remember { mutableStateOf(InsightRange.WEEK) }
    var editingSession by remember { mutableStateOf<FocusSession?>(null) }
    val interval = intervalFor(range)
    val selectedSeconds = store.focusSecondsBetween(interval.first, interval.second)
    val byCategory = store.focusByCategory(interval.first, interval.second).entries.sortedByDescending { it.value }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Insights", fontWeight = FontWeight.Bold) },
                actions = { IconButton(onClick = onOpenSettings) { Icon(Icons.Default.Settings, "Settings") } }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer), shape = RoundedCornerShape(22.dp)) {
                    Column(Modifier.fillMaxWidth().padding(20.dp)) {
                        Text("Total Focus Time", color = MaterialTheme.colorScheme.onPrimaryContainer)
                        Text(durationDetailed(store.totalFocusSeconds), fontSize = 31.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onPrimaryContainer)
                        Text("Across ${store.focusSessions.size} completed focus sessions", color = MaterialTheme.colorScheme.onPrimaryContainer)
                    }
                }
            }
            item {
                Card {
                    Column(Modifier.padding(17.dp), verticalArrangement = Arrangement.spacedBy(11.dp)) {
                        Text("Focus Summary", fontWeight = FontWeight.Bold)
                        InsightRange.entries.forEachIndexed { index, item ->
                            if (index > 0) HorizontalDivider()
                            val itemInterval = intervalFor(item)
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.Schedule, null, tint = MaterialTheme.colorScheme.primary)
                                Text(when (item) { InsightRange.DAY -> "Today"; InsightRange.WEEK -> "This Week"; InsightRange.MONTH -> "This Month"; InsightRange.YEAR -> "This Year" }, Modifier.padding(start = 10.dp).weight(1f))
                                Text(durationDetailed(store.focusSecondsBetween(itemInterval.first, itemInterval.second)), fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    InsightRange.entries.forEach { item ->
                        FilterChip(selected = range == item, onClick = { range = item }, label = { Text(item.title) }, modifier = Modifier.weight(1f))
                    }
                }
            }
            item {
                Card {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Text(when (range) { InsightRange.DAY -> "Today"; InsightRange.WEEK -> "This Week"; InsightRange.MONTH -> "This Month"; InsightRange.YEAR -> "This Year" }, fontWeight = FontWeight.Bold)
                        Text(durationDetailed(selectedSeconds), fontSize = 28.sp, fontWeight = FontWeight.Bold)
                        if (byCategory.isEmpty()) {
                            Text("Complete a task timer to see category activity.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        } else {
                            Text("Time by Category", fontWeight = FontWeight.SemiBold)
                            byCategory.forEach { (category, seconds) ->
                                CategoryBar(category, seconds, selectedSeconds)
                            }
                        }
                    }
                }
            }
            item { Text("Recorded Focus Time", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold) }
            if (store.focusSessions.isEmpty()) {
                item { Text("Completed timers will appear here for correction.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            } else {
                items(store.focusSessions.sortedByDescending { it.completedAtMillis }, key = { it.id }) { session ->
                    OutlinedCard(Modifier.clickable { editingSession = session }) {
                        Row(Modifier.fillMaxWidth().padding(15.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(10.dp).clip(CircleShape).background(categoryColor(session.category ?: "Other")))
                            Column(Modifier.padding(start = 11.dp).weight(1f)) {
                                Text(session.category ?: "Other", fontWeight = FontWeight.SemiBold)
                                Text(
                                    Instant.ofEpochMilli(session.completedAtMillis).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("MMM d, yyyy · h:mm a")),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Text(durationDetailed(session.durationSeconds), fontWeight = FontWeight.SemiBold)
                            Icon(Icons.Default.ChevronRight, null)
                        }
                    }
                }
            }
        }
    }

    editingSession?.let { session ->
        SessionEditorDialog(
            session = session,
            categories = store.categories,
            onDismiss = { editingSession = null },
            onSave = { store.updateSession(it); editingSession = null },
            onDelete = { store.deleteSession(session); editingSession = null }
        )
    }
}

@Composable
private fun CategoryBar(category: String, seconds: Int, total: Int) {
    val fraction = if (total > 0) seconds.toFloat() / total else 0f
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row {
            Text(category, Modifier.weight(1f))
            Text(durationDetailed(seconds), fontWeight = FontWeight.SemiBold)
        }
        Box(Modifier.fillMaxWidth().height(8.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant)) {
            Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).fillMaxHeight().background(categoryColor(category)))
        }
    }
}

@Composable
private fun SessionEditorDialog(
    session: FocusSession,
    categories: List<String>,
    onDismiss: () -> Unit,
    onSave: (FocusSession) -> Unit,
    onDelete: () -> Unit
) {
    var hours by remember { mutableIntStateOf(session.durationSeconds / 3600) }
    var minutes by remember { mutableIntStateOf((session.durationSeconds % 3600) / 60) }
    var seconds by remember { mutableIntStateOf(session.durationSeconds % 60) }
    var category by remember { mutableStateOf(session.category) }
    val duration = hours * 3600 + minutes * 60 + seconds

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit Focus Time") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(13.dp)) {
                Text("Time Spent", style = MaterialTheme.typography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    NumberStepper("Hours", hours, 0..23) { hours = it }
                    Column {
                        OutlinedTextField(
                            value = String.format(Locale.US, "%02d", minutes),
                            onValueChange = { minutes = it.filter(Char::isDigit).toIntOrNull()?.coerceIn(0, 59) ?: 0 },
                            label = { Text("Min") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.width(78.dp)
                        )
                        OutlinedTextField(
                            value = String.format(Locale.US, "%02d", seconds),
                            onValueChange = { seconds = it.filter(Char::isDigit).toIntOrNull()?.coerceIn(0, 59) ?: 0 },
                            label = { Text("Sec") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.width(78.dp)
                        )
                    }
                }
                Text("Category", style = MaterialTheme.typography.labelLarge)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = category == null, onClick = { category = null }, label = { Text("Other") })
                    categories.forEach { item -> FilterChip(selected = category == item, onClick = { category = item }, label = { Text(item) }) }
                }
                TextButton(onClick = onDelete) { Icon(Icons.Default.Delete, null); Spacer(Modifier.width(6.dp)); Text("Delete Record") }
            }
        },
        confirmButton = { TextButton(onClick = { onSave(session.copy(durationSeconds = duration.coerceAtLeast(1), category = category)) }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

// MARK: Settings and backup

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsScreen(store: FlowtimeStore, onBack: () -> Unit) {
    val context = LocalContext.current
    var pendingImport by remember { mutableStateOf<String?>(null) }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openOutputStream(uri)?.bufferedWriter()?.use { it.write(store.exportJson()) }
                ?: error("The selected file could not be opened.")
        }.onSuccess { toast(context, "Flowtime data exported") }
            .onFailure { toast(context, "Export failed: ${it.message}") }
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                ?: error("The selected file could not be opened.")
        }.onSuccess { pendingImport = it }
            .onFailure { toast(context, "Import failed: ${it.message}") }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Settings") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Default.Close, "Close") } }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                SettingsCard("Appearance") {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (store.darkTheme) Icons.Default.DarkMode else Icons.Default.LightMode, null)
                        Column(Modifier.padding(start = 12.dp).weight(1f)) {
                            Text(if (store.darkTheme) "Dark" else "Light", fontWeight = FontWeight.SemiBold)
                            Text("Changes immediately across every screen", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = store.darkTheme, onCheckedChange = store::setTheme)
                    }
                }
            }
            item {
                SettingsCard("When Timer Ends") {
                    TimerEndAlert.entries.forEachIndexed { index, alert ->
                        if (index > 0) HorizontalDivider()
                        Row(
                            Modifier.fillMaxWidth().clickable { store.setTimerAlert(alert) }.padding(vertical = 9.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = store.timerEndAlert == alert, onClick = { store.setTimerAlert(alert) })
                            Column(Modifier.padding(start = 7.dp)) {
                                Text(alert.label, fontWeight = FontWeight.SemiBold)
                                Text(alert.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
            item {
                SettingsCard("Your Data") {
                    Button(onClick = { exportLauncher.launch("Flowtime Backup.json") }, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Default.FileDownload, null); Spacer(Modifier.width(8.dp)); Text("Export Data")
                    }
                    Spacer(Modifier.height(10.dp))
                    OutlinedButton(onClick = { importLauncher.launch(arrayOf("application/json", "text/json", "text/plain")) }, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Default.FileUpload, null); Spacer(Modifier.width(8.dp)); Text("Import Data")
                    }
                    Spacer(Modifier.height(8.dp))
                    Text("JSON backups include tasks, categories, calendar events, focus history, timer progress, and settings. They can also be imported by the iPhone app.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }

    pendingImport?.let { raw ->
        AlertDialog(
            onDismissRequest = { pendingImport = null },
            title = { Text("Replace Current Data?") },
            text = { Text("Importing this backup replaces all tasks, events, insights, timer progress, and settings on this device.") },
            confirmButton = {
                TextButton(onClick = {
                    runCatching { store.importJson(raw) }
                        .onSuccess { toast(context, "Flowtime data imported") }
                        .onFailure { toast(context, "Import failed: ${it.message}") }
                    pendingImport = null
                }) { Text("Import") }
            },
            dismissButton = { TextButton(onClick = { pendingImport = null }) { Text("Cancel") } }
        )
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card {
        Column(Modifier.fillMaxWidth().padding(17.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(10.dp))
            content()
        }
    }
}

// MARK: Shared helpers

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateField(label: String, epochDay: Long, minDay: Long? = null, onSelected: (Long) -> Unit) {
    var showPicker by remember { mutableStateOf(false) }
    OutlinedButton(onClick = { showPicker = true }, modifier = Modifier.fillMaxWidth()) {
        Icon(Icons.Default.CalendarMonth, null)
        Spacer(Modifier.width(9.dp))
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
            Text(label, style = MaterialTheme.typography.labelSmall)
            Text(LocalDate.ofEpochDay(epochDay).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)))
        }
    }
    if (showPicker) {
        val initialMillis = LocalDate.ofEpochDay(epochDay).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val pickerState = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
        DatePickerDialog(
            onDismissRequest = { showPicker = false },
            confirmButton = {
                TextButton(onClick = {
                    val selected = pickerState.selectedDateMillis?.let { Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toEpochDay() }
                    if (selected != null) onSelected(selected.coerceAtLeast(minDay ?: Long.MIN_VALUE))
                    showPicker = false
                }) { Text("Done") }
            },
            dismissButton = { TextButton(onClick = { showPicker = false }) { Text("Cancel") } }
        ) { DatePicker(state = pickerState) }
    }
}

@Composable
private fun EmptyState(icon: ImageVector, title: String, message: String) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 70.dp, horizontal = 30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(icon, null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(message, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SectionLabel(title: String, count: String) {
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        Text(count, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun intervalFor(range: InsightRange): Pair<Long, Long> {
    val zone = ZoneId.systemDefault()
    val now = LocalDate.now(zone)
    val start = when (range) {
        InsightRange.DAY -> now
        InsightRange.WEEK -> now.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        InsightRange.MONTH -> now.withDayOfMonth(1)
        InsightRange.YEAR -> now.withDayOfYear(1)
    }
    val end = when (range) {
        InsightRange.DAY -> start.plusDays(1)
        InsightRange.WEEK -> start.plusWeeks(1)
        InsightRange.MONTH -> start.plusMonths(1)
        InsightRange.YEAR -> start.plusYears(1)
    }
    return start.atStartOfDay(zone).toInstant().toEpochMilli() to end.atStartOfDay(zone).toInstant().toEpochMilli()
}

private fun durationClock(seconds: Int): String {
    val safe = seconds.coerceAtLeast(0)
    return if (safe >= 3600) String.format(Locale.US, "%02d:%02d:%02d", safe / 3600, (safe % 3600) / 60, safe % 60)
    else String.format(Locale.US, "%02d:%02d", safe / 60, safe % 60)
}

private fun durationDetailed(seconds: Int): String {
    val safe = seconds.coerceAtLeast(0)
    return String.format(Locale.US, "%02d h %02d m %02d s", safe / 3600, (safe % 3600) / 60, safe % 60)
}

private fun durationCompact(seconds: Int): String {
    val safe = seconds.coerceAtLeast(0)
    val hours = safe / 3600
    val minutes = (safe % 3600) / 60
    return when {
        hours > 0 && minutes > 0 -> "${hours}h ${minutes}m"
        hours > 0 -> "${hours}h"
        minutes > 0 -> "${minutes}m"
        else -> "${safe}s"
    }
}

private fun dateRange(startDay: Long, endDay: Long): String {
    val formatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
    val start = LocalDate.ofEpochDay(startDay).format(formatter)
    val end = LocalDate.ofEpochDay(endDay).format(formatter)
    return if (startDay == endDay) start else "$start – $end"
}

private fun priorityColor(priority: TaskPriority): Color = when (priority) {
    TaskPriority.LOW -> Color(0xFF34C759)
    TaskPriority.MEDIUM -> Color(0xFFFFCC00)
    TaskPriority.HIGH -> Color(0xFFFF453A)
}

private val categoryPalette = listOf(
    Color(0xFF4F8CFF), Color(0xFFFF6B6B), Color(0xFF34C759), Color(0xFFFF9F0A),
    Color(0xFFBF5AF2), Color(0xFF5AC8FA), Color(0xFFFF375F), Color(0xFF64D2FF)
)

private fun categoryColor(category: String): Color = categoryPalette[(category.hashCode() and Int.MAX_VALUE) % categoryPalette.size]

private fun toast(context: Context, message: String) = Toast.makeText(context, message, Toast.LENGTH_LONG).show()
