"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";

type Task = { id: string; title: string; when: string; category: string; estimate: number; done: boolean };
type EventItem = { id: string; title: string; meta: string; tone: string; top: number; height: number };
type CreateKind = "event" | "task";

const week = [
  { day: "MON", date: 24 }, { day: "TUE", date: 25 }, { day: "WED", date: 26 },
  { day: "THU", date: 27 }, { day: "FRI", date: 28, active: true }, { day: "SAT", date: 29 }, { day: "SUN", date: 30 },
];
const initialEvents: EventItem[] = [
  { id: "e1", title: "Product strategy", meta: "9:00 – 10:00", tone: "blue", top: 42, height: 62 },
  { id: "e2", title: "Morning run", meta: "10:30 – 11:15", tone: "green", top: 132, height: 52 },
  { id: "e3", title: "Deep work", meta: "Website redesign · 2h", tone: "violet", top: 252, height: 92 },
  { id: "e4", title: "Team sync", meta: "16:00 – 16:45", tone: "orange", top: 407, height: 58 },
];
const initialTasks: Task[] = [
  { id: "t1", title: "Review project brief", when: "Today", category: "Work", estimate: 10, done: false },
  { id: "t2", title: "Book dentist", when: "Today", category: "Personal", estimate: 5, done: false },
  { id: "t3", title: "Prepare weekly notes", when: "Tomorrow", category: "Work", estimate: 30, done: false },
  { id: "t4", title: "Send August report", when: "Friday", category: "Work", estimate: 20, done: true },
];

function formatClock(total: number) {
  const safe = Math.max(0, total);
  return `${Math.floor(safe / 60).toString().padStart(2, "0")}:${(safe % 60).toString().padStart(2, "0")}`;
}

export default function Home() {
  const [active, setActive] = useState("Today");
  const [calendarView, setCalendarView] = useState("Week");
  const [tasks, setTasks] = useState(initialTasks);
  const [events, setEvents] = useState(initialEvents);
  const [modal, setModal] = useState<CreateKind | null>(null);
  const [title, setTitle] = useState("");
  const [timerMode, setTimerMode] = useState<"focus" | "stopwatch">("focus");
  const [seconds, setSeconds] = useState(2304);
  const [running, setRunning] = useState(true);
  const [toast, setToast] = useState("");
  const openTasks = useMemo(() => tasks.filter((task) => !task.done), [tasks]);

  useEffect(() => {
    if (!running) return;
    const timer = window.setInterval(() => setSeconds((value) => timerMode === "focus" ? Math.max(0, value - 1) : value + 1), 1000);
    return () => window.clearInterval(timer);
  }, [running, timerMode]);

  useEffect(() => {
    if (!toast) return;
    const timeout = window.setTimeout(() => setToast(""), 2200);
    return () => window.clearTimeout(timeout);
  }, [toast]);

  async function sync(action: string, payload: unknown) {
    try {
      await fetch("/api/sync", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action, payload }) });
      setToast("Saved and synced");
    } catch { setToast("Saved locally · sync pending"); }
  }

  function createItem(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const clean = title.trim();
    if (!clean || !modal) return;
    if (modal === "task") {
      const task = { id: crypto.randomUUID(), title: clean, when: "Today", category: "Work", estimate: 25, done: false };
      setTasks((items) => [task, ...items]); sync("upsert-task", task);
    } else {
      const item = { id: crypto.randomUUID(), title: clean, meta: "15:00 – 16:00", tone: "blue", top: 357, height: 62 };
      setEvents((items) => [...items, item]); sync("upsert-event", item);
    }
    setTitle(""); setModal(null);
  }

  function toggleTask(task: Task) {
    const next = { ...task, done: !task.done };
    setTasks((items) => items.map((item) => item.id === task.id ? next : item)); sync("upsert-task", next);
  }

  function changeTimerMode(mode: "focus" | "stopwatch") {
    setTimerMode(mode); setSeconds(mode === "focus" ? 3000 : 0); setRunning(false);
  }

  function stopTimer() {
    setRunning(false);
    const duration = timerMode === "focus" ? 3000 - seconds : seconds;
    if (duration > 0) sync("log-session", { id: crypto.randomUUID(), label: "Website redesign", duration, mode: timerMode });
    setSeconds(timerMode === "focus" ? 3000 : 0);
  }

  const nav = [
    { label: "Today", icon: "▦" }, { label: "Tasks", icon: "✓" }, { label: "Focus", icon: "◷" }, { label: "Insights", icon: "⌁" },
  ];

  return (
    <main className="app-shell">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark">F</span><span>Flowtime</span></div>
        <button className="create-button" type="button" onClick={() => setModal("event")}><span>＋</span> Create</button>
        <nav className="nav-list" aria-label="Main navigation">
          {nav.map((item) => <button className={`nav-item ${active === item.label ? "active" : ""}`} onClick={() => setActive(item.label)} key={item.label}><span className="nav-icon">{item.icon}</span>{item.label}{item.label === "Tasks" && <span className="count">{openTasks.length}</span>}</button>)}
        </nav>
        <div className="sidebar-section"><p>MY CALENDARS</p><div><span className="dot blue" />Work</div><div><span className="dot green" />Personal</div><div><span className="dot violet" />Focus time</div></div>
        <div className="sync-badge"><span /> Sync is on</div>
        <div className="sidebar-footer"><div className="mini-avatar">TY</div><div><strong>Tao Yongli</strong><span>tao@flowtime.app</span></div><button aria-label="More account options">•••</button></div>
      </aside>

      <section className="workspace">
        <header className="topbar">
          <div><p className="eyebrow">FRIDAY, AUGUST 28</p><h1>{active === "Today" ? "Good afternoon, Tao" : active} <span>{active === "Today" ? "👋" : ""}</span></h1></div>
          <div className="top-actions"><button className="icon-button" aria-label="Search">⌕</button><button className="icon-button notification" aria-label="Notifications">♢</button><button className="start-focus" type="button" onClick={() => { setActive("Focus"); setRunning(true); }}><span>▶</span> Start focus</button></div>
        </header>

        {active === "Insights" ? <Insights /> : active === "Tasks" ? <TasksView tasks={tasks} onToggle={toggleTask} onAdd={() => setModal("task")} /> : (
          <div className={`content-grid ${active === "Focus" ? "focus-layout" : ""}`}>
            {active !== "Focus" && <Calendar events={events} view={calendarView} setView={setCalendarView} />}
            <aside className="right-rail">
              <FocusCard mode={timerMode} seconds={seconds} running={running} onMode={changeTimerMode} onToggle={() => setRunning((value) => !value)} onStop={stopTimer} />
              {active !== "Focus" && <TasksCard tasks={openTasks} onToggle={toggleTask} onAdd={() => setModal("task")} onView={() => setActive("Tasks")} />}
              {active !== "Focus" && <ProgressCard onView={() => setActive("Insights")} />}
              {active === "Focus" && <FocusStats />}
            </aside>
          </div>
        )}
      </section>

      {modal && <div className="modal-backdrop"><form className="create-modal" onSubmit={createItem}><div className="modal-handle" /><div className="kind-switch"><button type="button" className={modal === "event" ? "selected" : ""} onClick={() => setModal("event")}>Event</button><button type="button" className={modal === "task" ? "selected" : ""} onClick={() => setModal("task")}>Task</button></div><input value={title} onChange={(event) => setTitle(event.target.value)} placeholder={modal === "event" ? "Event title" : "What needs doing?"} aria-label="Title" /><div className="form-row"><label><span>When</span><input type="date" defaultValue="2026-08-28" /></label><label><span>{modal === "event" ? "Starts" : "Estimate"}</span><input type={modal === "event" ? "time" : "text"} defaultValue={modal === "event" ? "15:00" : "25 min"} /></label></div><label className="category-label"><span>Calendar</span><select defaultValue="Work"><option>Work</option><option>Personal</option><option>Focus time</option></select></label><div className="modal-actions"><button type="button" onClick={() => setModal(null)}>Cancel</button><button className="save-button" type="submit">Create {modal}</button></div></form></div>}
      {toast && <div className="toast"><span>✓</span>{toast}</div>}
      <nav className="mobile-nav" aria-label="Mobile navigation">{nav.map((item) => <button className={active === item.label ? "active" : ""} onClick={() => setActive(item.label)} key={item.label}><span>{item.icon}</span>{item.label}</button>)}</nav>
    </main>
  );
}

function Calendar({ events, view, setView }: { events: EventItem[]; view: string; setView: (view: string) => void }) {
  return <section className="calendar-card" aria-label="Weekly calendar"><div className="calendar-toolbar"><div className="calendar-title"><button aria-label="Previous week">‹</button><h2>August 24 – 30</h2><button aria-label="Next week">›</button><button className="today-pill">Today</button></div><div className="segmented" aria-label="Calendar view">{["Day","Week","Month"].map((item) => <button className={view === item ? "selected" : ""} onClick={() => setView(item)} key={item}>{item}</button>)}</div></div><div className="week-header"><div />{week.map((item) => <div className={item.active ? "active-day" : ""} key={item.day}><span>{item.day}</span><strong>{item.date}</strong></div>)}</div><div className="calendar-body"><div className="time-axis">{[8,9,10,11,12,13,14,15,16,17].map((hour) => <span key={hour}>{hour > 12 ? hour - 12 : hour}:00</span>)}</div><div className="day-columns">{week.map((item) => <div className={item.active ? "day-column active-column" : "day-column"} key={item.day} />)}</div><div className="now-line"><span>2:38</span></div>{events.map((event) => <article className={`event ${event.tone}`} style={{ top: event.top, height: event.height }} key={event.id}><strong>{event.title}</strong><span>{event.meta}</span></article>)}</div></section>;
}

function FocusCard({ mode, seconds, running, onMode, onToggle, onStop }: { mode: "focus"|"stopwatch"; seconds: number; running: boolean; onMode: (mode:"focus"|"stopwatch") => void; onToggle:()=>void; onStop:()=>void }) {
  const focusElapsed = 3000 - seconds;
  return <section className="focus-card"><div className="timer-tabs"><button className={mode === "focus" ? "selected" : ""} onClick={() => onMode("focus")}>Timer</button><button className={mode === "stopwatch" ? "selected" : ""} onClick={() => onMode("stopwatch")}>Stopwatch</button></div><div className="card-heading"><div><span className={running ? "live-dot" : "live-dot paused-dot"} />{running ? "FOCUSING NOW" : "READY WHEN YOU ARE"}</div><button aria-label="Focus options">•••</button></div><p className="focus-label">Website redesign</p><div className="timer">{formatClock(seconds)}</div><div className="timer-track"><span style={{ width: mode === "focus" ? `${Math.max(2, focusElapsed / 30)}%` : "55%" }} /></div><div className="timer-controls"><button className="stop" aria-label="Stop session" onClick={onStop}>■</button><button className="pause" aria-label={running ? "Pause session" : "Resume session"} onClick={onToggle}>{running ? "Ⅱ" : "▶"}</button><button className="expand" aria-label="Expand timer">↗</button></div><p className="timer-goal">{mode === "focus" ? `50 min focus · ${Math.ceil(seconds / 60)} min remaining` : "Count up without a limit"}</p></section>;
}

function TasksCard({ tasks, onToggle, onAdd, onView }: { tasks: Task[]; onToggle:(task:Task)=>void; onAdd:()=>void; onView:()=>void }) { return <section className="tasks-card"><div className="card-title"><h3>Up next</h3><button onClick={onView}>View all</button></div>{tasks.slice(0,3).map((task) => <TaskRow key={task.id} task={task} onToggle={onToggle} />)}<button className="add-task" onClick={onAdd}>＋ Add a task</button></section>; }
function TaskRow({ task, onToggle }: { task:Task; onToggle:(task:Task)=>void }) { return <div className={`task ${task.done ? "done" : ""}`}><button aria-label={task.done ? "Reopen task" : "Complete task"} onClick={() => onToggle(task)}>{task.done ? "✓" : ""}</button><div><strong>{task.title}</strong><span>{task.when} · {task.category}</span></div><em>{task.estimate}m</em></div>; }
function ProgressCard({ onView }: { onView:()=>void }) { return <section className="progress-card"><div className="card-title"><div><h3>Today&apos;s progress</h3><span>4h 12m tracked</span></div><button onClick={onView}>Insights</button></div>{[["Focus","78%","3h 18m",""],["Meetings","32%","45m","orange-bar"],["Personal","18%","29m","green-bar"]].map((row) => <div className="progress-row" key={row[0]}><span>{row[0]}</span><div><i className={row[3]} style={{width:row[1]}} /></div><strong>{row[2]}</strong></div>)}</section>; }

function TasksView({ tasks, onToggle, onAdd }: { tasks:Task[]; onToggle:(task:Task)=>void; onAdd:()=>void }) { return <section className="page-card tasks-page"><div className="page-card-header"><div><p>YOUR DAY</p><h2>Tasks</h2><span>{tasks.filter((task)=>!task.done).length} things left to do</span></div><button onClick={onAdd}>＋ New task</button></div><div className="task-filter"><button className="selected">All</button><button>Today</button><button>Upcoming</button><button>Completed</button></div><div className="task-list">{tasks.map((task) => <TaskRow key={task.id} task={task} onToggle={onToggle} />)}</div></section>; }
function Insights() { const bars=[52,71,43,86,64,92,35]; return <section className="page-card insights-page"><div className="page-card-header"><div><p>WEEKLY REPORT</p><h2>Your time, clearly</h2><span>Aug 24 – 30 · 26h 40m tracked</span></div><button>Export report</button></div><div className="metric-grid"><div><span>Total focus</span><strong>18h 24m</strong><em>↑ 12% from last week</em></div><div><span>Tasks completed</span><strong>32</strong><em>8 more than last week</em></div><div><span>Daily average</span><strong>3h 49m</strong><em>of intentional time</em></div></div><div className="chart-card"><div className="chart-heading"><div><h3>Focused time</h3><span>Daily tracked hours</span></div><div className="chart-legend"><i />Focus <i className="meeting-dot" />Meetings</div></div><div className="bar-chart">{bars.map((height,index)=><div className="bar-group" key={index}><div className="bar-stack"><i style={{height:`${height}%`}} /><b style={{height:`${Math.max(10,height/3)}%`}} /></div><span>{["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][index]}</span></div>)}</div></div><div className="insight-note"><span>✦</span><div><strong>Your best focus window is 9–11 AM</strong><p>You complete 38% more focused work during this time. Keep protecting it.</p></div><button>Plan focus time</button></div></section>; }
function FocusStats(){return <section className="focus-stats"><p>THIS WEEK</p><h2>18h 24m</h2><span>Focused across 14 sessions</span><div><strong>92%</strong><small>Goal progress</small></div><div><strong>1h 19m</strong><small>Average session</small></div></section>}
