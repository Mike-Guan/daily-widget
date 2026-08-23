(function renderer() {
  'use strict';
  const Task = window.DailyWidgetTaskModel;
  const copy = {
    zh: {
      brandTagline: '轻一点，做重要的事', workspace: '工作区', todayPlan: '今日计划', inbox: '收集箱', rituals: '习惯', todayFocus: '今日重点', dailyReview: '日末回顾', setSyncFolder: '设置同步文件夹', today: '今天', sync: '同步', exportMarkdown: '导出 Markdown', quickAdd: '快速添加', quickPlaceholder: '例如：明天 9:30 跑步 45m', nowNext: '进行中 / 接下来', todayDone: '今日完成', timeline: '时间轴', timelineHint: '空白处拖动即可排入日程 · 15 分钟吸附', manage: '管理', add: '＋ 添加', wrapUp: '收尾', reviewAction: '回顾未完成事项，安排明天', todayHeading: '今天', makeSpace: '今天留一点空间给自己', easyStart: '轻松开始', inProgress: '进行中 · 至 {time}', next: '下一项 · {time}', task: '任务', newTask: '新任务', editTask: '编辑任务', title: '任务', date: '日期', category: '分类', start: '开始时间', end: '结束时间', repeat: '重复', focus: '设为今日重点', link: '链接', notes: '备注', delete: '删除', cancel: '取消', save: '保存任务', review: '日末回顾', reviewIntro: '未完成的任务不必成为负担，给它一个合适的去处。', tomorrow: '移到明天', moveInbox: '放入收集箱', noReview: '今天已经收尾得很好了。', localOnly: '本地优先 · 未启用同步', connected: '已连接 · 等待首次同步', synced: '已同步 · {time}', syncIssue: '同步需处理 · {error}', focusEmpty: '选出最多三件真正重要的事，让今天更清晰。', inboxEmpty: '想到什么先记下来，稍后再决定什么时候做。', untitled: '未命名任务', recurring: '重复', noTasks: '今天留一点空间给自己', reviewClear: '已清空', reviewPending: '{count} 项待处理', syncedToast: '同步完成 · ↑{push} ↓{pull}', chooseFolder: '请先选择同步文件夹', browserSync: '浏览器版无法直接访问共享文件夹；请使用桌面或 iPhone app。', taskSaved: '已保存', taskDeleted: '已删除', taskScheduled: '已排入时间轴', addedSchedule: '已加入日程', addedInbox: '已放入收集箱', focusLimit: '每天最多设置三件重点', writeTask: '写下想做的事，再按加号', titleRequired: '先写下这件要做的事', bothTimes: '请同时填写开始和结束时间', validRange: '结束时间需要晚于开始时间', recurringDate: '重复任务需要一个开始日期', focusManage: '在时间轴上点击 ☆ / ★ 管理今日重点', themeSystem: '跟随系统主题', themeDark: '深色主题', themeLight: '浅色主题', remoteChange: '检测到其他设备的更新', dragTitle: '空白处拖动即可排入日程', current: '进行中', nextTask: '下一项', personal: '个人', health: '健康', home: '生活', social: '关系', learning: '学习', errands: '杂事', none: '不重复', daily: '每天', weekdays: '工作日', weekly: '每周', taskPlaceholder: '要完成什么？', notesPlaceholder: '留给未来自己的补充说明', linkPlaceholder: 'https://…', quickTimeExample: '例如：tomorrow 9:30 run 45m',
    },
    en: {
      brandTagline: 'Make space for what matters', workspace: 'Workspace', todayPlan: 'Today', inbox: 'Inbox', rituals: 'Rituals', todayFocus: 'Top 3', dailyReview: 'Daily review', setSyncFolder: 'Set sync folder', today: 'Today', sync: 'Sync', exportMarkdown: 'Export Markdown', quickAdd: 'Quick add', quickPlaceholder: 'e.g. tomorrow 9:30 run 45m', nowNext: 'Now / next', todayDone: 'Done today', timeline: 'Timeline', timelineHint: 'Drag on empty time to schedule · 15 min snap', manage: 'Manage', add: '＋ Add', wrapUp: 'Wrap up', reviewAction: 'Review unfinished tasks for tomorrow', todayHeading: 'Today', makeSpace: 'Leave room for yourself today', easyStart: 'Easy start', inProgress: 'In progress · until {time}', next: 'Up next · {time}', task: 'Task', newTask: 'New task', editTask: 'Edit task', title: 'Task', date: 'Date', category: 'Category', start: 'Start', end: 'End', repeat: 'Repeat', focus: 'Make this a top task', link: 'Link', notes: 'Notes', delete: 'Delete', cancel: 'Cancel', save: 'Save task', review: 'Daily review', reviewIntro: 'Unfinished tasks are not a burden. Give each one a good home.', tomorrow: 'Move to tomorrow', moveInbox: 'Move to inbox', noReview: 'Your day is already wrapped up nicely.', localOnly: 'Local first · sync not enabled', connected: 'Connected · waiting for first sync', synced: 'Synced · {time}', syncIssue: 'Sync needs attention · {error}', focusEmpty: 'Choose up to three things that truly matter today.', inboxEmpty: 'Capture it first. Decide when later.', untitled: 'Untitled task', recurring: 'Repeats', noTasks: 'Leave room for yourself today', reviewClear: 'Clear', reviewPending: '{count} pending', syncedToast: 'Sync complete · ↑{push} ↓{pull}', chooseFolder: 'Choose a shared folder first.', browserSync: 'Browser mode cannot access a shared folder. Use the desktop or iPhone app.', taskSaved: 'Saved', taskDeleted: 'Deleted', taskScheduled: 'Scheduled on the timeline', addedSchedule: 'Added to your schedule', addedInbox: 'Added to inbox', focusLimit: 'You can choose up to three top tasks.', writeTask: 'Write what you want to do, then press add.', titleRequired: 'Give this task a name first.', bothTimes: 'Enter both a start and end time.', validRange: 'End time must be after start time.', recurringDate: 'A recurring task needs a start date.', focusManage: 'Use ☆ / ★ on the timeline to manage your top tasks.', themeSystem: 'Following system theme', themeDark: 'Dark theme', themeLight: 'Light theme', remoteChange: 'Updates from another device detected', dragTitle: 'Drag on empty time to schedule', current: 'In progress', nextTask: 'Up next', personal: 'Personal', health: 'Health', home: 'Home', social: 'Social', learning: 'Learning', errands: 'Errands', none: 'Does not repeat', daily: 'Every day', weekdays: 'Weekdays', weekly: 'Every week', taskPlaceholder: 'What needs doing?', notesPlaceholder: 'A note for future you', linkPlaceholder: 'https://…', quickTimeExample: 'e.g. tomorrow 9:30 run 45m',
    },
  };
  Object.assign(copy.zh, { inboxDragHint: '拖动任务到时间轴的具体时间，或点 ＋ 按默认空档排入今天', scheduleToday: '排入今天', inboxOverview: '{count} 项未排期事项', inboxPage: '收集箱 · 全部事项', deleteTask: '删除任务', exportHint: '选择要导出的日期范围。', exportStart: '开始日期', exportEnd: '结束日期', exportRange: '导出选定范围', exported: '已导出并复制到剪贴板', exportInvalid: '请选择有效的日期范围，且结束日期不能早于开始日期。', timelineHint: '拖出时间框后直接输入名称 · 15 分钟吸附', continuesFromPrevious: '从前一天延续', allInbox: '收集箱', inboxPageHint: '先捕捉，再决定什么时候做。', topPageHint: '只留下今天真正重要的事。', reviewPageHint: '用轻量回顾为今天收尾。', completed: '已完成', incomplete: '未完成', planned: '已计划', moveTomorrow: '移到明天', reviewEmpty: '今天还没有已排期的任务。', encouragementEmpty: '今天尚未排定事项。留一点空间，也是一种安排。', encouragementDone: '太棒了，今天安排的事项已经全部完成。', encouragementProgress: '做得很好，已经完成 {done} 项；剩下的也可以从容安排。', edit: '编辑', top3Page: '今日重点' });
  Object.assign(copy.en, { inboxDragHint: 'Drag a task to an exact time, or press + to schedule it today', scheduleToday: 'Schedule today', inboxOverview: '{count} unscheduled items', inboxPage: 'Inbox · all items', deleteTask: 'Delete task', exportHint: 'Choose the date range to export.', exportStart: 'Start date', exportEnd: 'End date', exportRange: 'Export selected range', exported: 'Exported and copied to clipboard', exportInvalid: 'Choose a valid range; the end date cannot be before the start date.', timelineHint: 'Draw a time block, then type its name · 15 min snap', continuesFromPrevious: 'Continues from previous day', allInbox: 'Inbox', inboxPageHint: 'Capture first. Decide when later.', topPageHint: 'Keep only what truly matters today.', reviewPageHint: 'A light reflection to close the day.', completed: 'Completed', incomplete: 'Unfinished', planned: 'Planned', moveTomorrow: 'Move to tomorrow', reviewEmpty: 'No scheduled tasks for this day yet.', encouragementEmpty: 'Nothing is scheduled today. Leaving space is a valid plan.', encouragementDone: 'Wonderful — every planned task is complete.', encouragementProgress: 'Nice work: {done} task(s) complete. The rest can be arranged with care.', edit: 'Edit', top3Page: 'Top 3' });
  function language() { return state.settings && state.settings.language === 'en' ? 'en' : 'zh'; }
  function t(key, values) { let text = (copy[language()] && copy[language()][key]) || copy.zh[key] || key; Object.entries(values || {}).forEach(([name, value]) => { text = text.replace(`{${name}}`, String(value)); }); return text; }
  const START_HOUR = 0;
  const END_HOUR = 24;
  const HOUR_HEIGHT = 64;
  const PIXELS_PER_MINUTE = HOUR_HEIGHT / 60;
  const DAY_HEIGHT = (END_HOUR - START_HOUR) * HOUR_HEIGHT;
  const $ = (selector) => document.querySelector(selector);
  const state = { date: Task.formatDateKey(new Date()), tasks: [], inbox: [], settings: null, editing: null, activeView: 'today', dragInboxId: null };
  const categoryMap = new Map(Task.CATEGORY_DEFINITIONS.map((category) => [category.id, category]));

  const timeline = $('#timeline');
  const toast = $('#toast');
  const taskDialog = $('#taskDialog');
  const reviewDialog = $('#reviewDialog');
  const exportDialog = $('#exportDialog');

  function dateForKey(dateKey) { return Task.dateFromKey(dateKey); }
  function isToday() { return state.date === Task.formatDateKey(new Date()); }
  function formattedDate() { return dateForKey(state.date).toLocaleDateString(language() === 'en' ? 'en-US' : 'zh-CN', { weekday: 'long', month: 'long', day: 'numeric' }); }
  function minuteToY(minute) { return (minute - START_HOUR * 60) * PIXELS_PER_MINUTE; }
  function clampTimelineMinute(minute) { return Math.max(START_HOUR * 60, Math.min(END_HOUR * 60, Math.round(minute / 15) * 15)); }
  function timeInputValue(minute) { return minute === null || minute === undefined ? '' : Task.minuteToTime(minute); }
  function sourceOccurrenceDate(task) { return task.sourceOccurrenceDate || state.date; }
  function taskTimeLabel(task, start, end) { const suffix = (task.spansNextDay || end > 24 * 60) ? ' (+1)' : (task.isContinuation ? ` · ${t('continuesFromPrevious')}` : ''); return `${Task.minuteToTime(start)} – ${Task.minuteToTime(end)}${suffix}`; }
  function timeToMinute(value) { if (!value) return null; const [hour, minute] = value.split(':').map(Number); return hour * 60 + minute; }
  function showToast(message) { toast.textContent = message; toast.classList.add('show'); clearTimeout(showToast.timer); showToast.timer = setTimeout(() => toast.classList.remove('show'), 2200); }
  function currentTask() { const now = new Date(); const minute = now.getHours() * 60 + now.getMinutes(); return state.tasks.find((task) => !task.done && task.start <= minute && task.end > minute); }
  function nextTask() { const now = new Date(); const minute = now.getHours() * 60 + now.getMinutes(); return state.tasks.find((task) => !task.done && task.start >= minute); }
  function scheduledIncomplete() { return state.tasks.filter((task) => !task.done && task.recurrence === 'none'); }

  async function reload() {
    [state.tasks, state.inbox, state.settings] = await Promise.all([
      window.dailyWidget.getDay(state.date), window.dailyWidget.getInbox(), window.dailyWidget.getSettings(),
    ]);
    applyTheme();
    render();
  }

  function applyTheme() {
    const theme = state.settings && state.settings.theme;
    if (theme === 'dark' || theme === 'light') document.documentElement.dataset.theme = theme;
    else delete document.documentElement.dataset.theme;
  }

  function render() {
    translateStatic();
    renderHeader();
    renderSummary();
    renderTimeline();
    renderFocus();
    renderInbox();
    renderSyncStatus();
    renderActiveView();
  }

  function setActiveView(view) {
    state.activeView = view;
    document.querySelectorAll('[data-view]').forEach((item) => item.classList.toggle('active', item.dataset.view === view));
    renderActiveView();
  }

  function renderActiveView() {
    const todayView = state.activeView === 'today';
    $('#dashboard').hidden = !todayView;
    $('#workspace').hidden = !todayView;
    const mount = $('#collectionView');
    mount.hidden = todayView;
    if (todayView) return;
    mount.innerHTML = '';
    if (state.activeView === 'inbox') renderInboxPage(mount);
    else if (state.activeView === 'focus') renderFocusPage(mount);
    else if (state.activeView === 'review') renderReviewPage(mount);
  }

  function createViewHeader(title, subtitle) {
    const header = element('div', 'view-header');
    const text = element('div'); text.append(element('h2', null, title), element('p', null, subtitle));
    header.appendChild(text);
    return header;
  }

  function collectionCard(task, options) {
    const card = element('article', `collection-card${task.done ? ' done' : ''}`);
    const main = element('div', 'card-main');
    main.append(element('h3', null, task.title || t('untitled')), element('p', null, options.meta));
    if (task.notes) main.append(element('p', null, task.notes));
    const actions = element('div', 'collection-actions');
    (options.actions || []).forEach(({ label, primary, onClick }) => { const button = element('button', primary ? 'primary' : '', label); button.addEventListener('click', onClick); actions.appendChild(button); });
    card.append(main, actions);
    return card;
  }

  function renderInboxPage(mount) {
    mount.appendChild(createViewHeader(t('allInbox'), t('inboxPageHint')));
    const list = element('div', 'view-grid');
    if (!state.inbox.length) list.appendChild(element('div', 'empty-state', t('inboxEmpty')));
    state.inbox.forEach((task) => list.appendChild(collectionCard(task, { meta: t(task.category), actions: [
      { label: t('edit'), onClick: () => openTaskDialog(task) },
      { label: '＋', primary: true, onClick: () => scheduleInboxTask(task) },
    ] })));
    mount.appendChild(list);
  }

  function renderFocusPage(mount) {
    mount.appendChild(createViewHeader(t('top3Page'), t('topPageHint')));
    const list = element('div', 'view-grid');
    const focusTasks = state.tasks.filter((task) => task.focus);
    if (!focusTasks.length) list.appendChild(element('div', 'empty-state', t('focusEmpty')));
    focusTasks.forEach((task) => list.appendChild(collectionCard(task, { meta: `${Task.minuteToTime(task.start)} – ${Task.minuteToTime(task.end)} · ${t(task.category)}`, actions: [{ label: t('edit'), onClick: () => openTaskDialog(task) }] })));
    mount.appendChild(list);
  }

  function reviewOrder(tasks) { return tasks.slice().sort((left, right) => Number(right.focus) - Number(left.focus) || left.start - right.start); }
  function renderReviewPage(mount) {
    mount.appendChild(createViewHeader(t('review'), t('reviewPageHint')));
    const complete = reviewOrder(state.tasks.filter((task) => task.done));
    const incomplete = reviewOrder(state.tasks.filter((task) => !task.done));
    const encouragement = state.tasks.length === 0 ? t('encouragementEmpty') : (incomplete.length === 0 ? t('encouragementDone') : t('encouragementProgress', { done: complete.length }));
    mount.appendChild(element('div', 'encouragement', encouragement));
    const stats = element('div', 'review-summary');
    [[t('planned'), state.tasks.length], [t('completed'), complete.length], [t('incomplete'), incomplete.length]].forEach(([label, count]) => { const stat = element('div', 'review-stat'); stat.append(element('strong', null, String(count)), element('span', null, label)); stats.appendChild(stat); });
    mount.appendChild(stats);
    if (!state.tasks.length) { mount.appendChild(element('div', 'empty-state', t('reviewEmpty'))); return; }
    const columns = element('div', 'review-columns');
    [[t('completed'), complete, true], [t('incomplete'), incomplete, false]].forEach(([label, tasks, isDone]) => { const section = element('section', 'review-section'); section.appendChild(element('h3', null, label)); const list = element('div', 'view-grid'); if (!tasks.length) list.appendChild(element('div', 'empty-state', '—')); tasks.forEach((task) => list.appendChild(collectionCard(task, { meta: `${Task.minuteToTime(task.start)} – ${Task.minuteToTime(task.end)}${task.focus ? ' · ★' : ''}`, actions: isDone ? [{ label: t('edit'), onClick: () => openTaskDialog(task) }] : [
      { label: t('moveTomorrow'), onClick: async () => { await window.dailyWidget.saveTask(Object.assign({}, task, { date: Task.addDays(state.date, 1) })); await reload(); } },
      { label: t('moveInbox'), onClick: async () => { await window.dailyWidget.moveToInbox(task.sourceId); await reload(); } },
    ] }))); section.appendChild(list); columns.appendChild(section); });
    mount.appendChild(columns);
  }

  function translateStatic() {
    document.documentElement.lang = language() === 'en' ? 'en' : 'zh-CN';
    document.querySelectorAll('[data-i18n]').forEach((node) => { node.textContent = t(node.dataset.i18n); });
    document.querySelectorAll('[data-i18n-placeholder]').forEach((node) => { node.placeholder = t(node.dataset.i18nPlaceholder); });
    $('#taskTitle').placeholder = t('taskPlaceholder'); $('#taskNotes').placeholder = t('notesPlaceholder'); $('#taskUrl').placeholder = t('linkPlaceholder');
    const labels = { taskTitle: 'title', taskDate: 'date', taskCategory: 'category', taskStart: 'start', taskEnd: 'end', taskRecurrence: 'repeat', taskUrl: 'link', taskNotes: 'notes' };
    Object.entries(labels).forEach(([id, key]) => { const label = document.querySelector(`label[for="${id}"]`); if (label) label.textContent = t(key); });
    $('#taskFocus').parentElement.lastChild.textContent = ` ${t('focus')}`;
    $('#deleteTask').textContent = t('delete'); $('#cancelTask').textContent = t('cancel'); $('#taskForm .save-btn').textContent = t('save'); $('#reviewDialog .modal-header h3').textContent = t('review'); $('#reviewDialog p').textContent = t('reviewIntro');
    const categorySelect = $('#taskCategory'); [...categorySelect.options].forEach((option) => { option.textContent = t(option.value); });
    const recurrenceSelect = $('#taskRecurrence'); [...recurrenceSelect.options].forEach((option) => { option.textContent = t(option.value); });
  }

  function renderHeader() {
    $('#dateHeading').textContent = isToday() ? t('todayHeading') : formattedDate();
    $('#dateSubheading').textContent = isToday() ? `${formattedDate()} · ${t('makeSpace')}` : state.date;
    $('#inboxCount').textContent = String(state.inbox.length);
    $('#reviewCount').textContent = scheduledIncomplete().length ? t('reviewPending', { count: scheduledIncomplete().length }) : t('reviewClear');
  }

  function renderSummary() {
    const total = state.tasks.length;
    const complete = state.tasks.filter((task) => task.done).length;
    const active = isToday() ? currentTask() : null;
    const upcoming = !active && isToday() ? nextTask() : state.tasks.find((task) => !task.done);
    $('#nowLabel').textContent = active ? active.title || t('current') : (upcoming ? upcoming.title || t('nextTask') : t('easyStart'));
    $('#nowCaption').textContent = active ? t('inProgress', { time: Task.minuteToTime(active.end) }) : (upcoming ? t('next', { time: Task.minuteToTime(upcoming.start) }) : t('makeSpace'));
    $('#progressLabel').textContent = `${complete} / ${total}`;
    const focusCount = state.tasks.filter((task) => task.focus).length;
    [...$('#progressPips').children].forEach((pip, index) => pip.classList.toggle('active', index < focusCount));
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function renderTimeline() {
    timeline.innerHTML = '';
    timeline.style.height = `${DAY_HEIGHT}px`;
    for (let hour = START_HOUR; hour <= END_HOUR; hour += 1) {
      const y = (hour - START_HOUR) * HOUR_HEIGHT;
      const line = element('div', 'hour-line'); line.style.top = `${y}px`; timeline.appendChild(line);
      const label = element('div', `hour-label${hour === START_HOUR ? ' first' : ''}`, hour === END_HOUR ? '24:00' : `${hour}:00`); label.style.top = `${y}px`; timeline.appendChild(label);
      if (hour < END_HOUR) { const half = element('div', 'hour-line half'); half.style.top = `${y + HOUR_HEIGHT / 2}px`; timeline.appendChild(half); }
    }
    const hitArea = element('div', 'grid-hit');
    hitArea.addEventListener('pointerdown', startCreateFromGrid);
    hitArea.addEventListener('dragover', (event) => { if (state.dragInboxId) { event.preventDefault(); hitArea.classList.add('drop-active'); } });
    hitArea.addEventListener('dragleave', () => hitArea.classList.remove('drop-active'));
    hitArea.addEventListener('drop', dropInboxOnTimeline);
    timeline.addEventListener('dragover', (event) => { if (state.dragInboxId) event.preventDefault(); });
    timeline.addEventListener('drop', dropInboxOnTimeline);
    timeline.appendChild(hitArea);
    if (isToday()) {
      const now = new Date(); const minute = now.getHours() * 60 + now.getMinutes();
      if (minute >= START_HOUR * 60 && minute <= END_HOUR * 60) { const line = element('div', 'now-line'); line.style.top = `${minuteToY(minute)}px`; timeline.appendChild(line); }
    }
    state.tasks.forEach((task) => timeline.appendChild(buildTask(task)));
  }

  async function dropInboxOnTimeline(event) {
    event.preventDefault();
    document.querySelectorAll('.grid-hit').forEach((target) => target.classList.remove('drop-active'));
    const task = state.inbox.find((item) => item.id === state.dragInboxId);
    state.dragInboxId = null;
    if (!task) return;
    const rect = timeline.getBoundingClientRect();
    const start = clampTimelineMinute(START_HOUR * 60 + (event.clientY - rect.top) / PIXELS_PER_MINUTE);
    await window.dailyWidget.saveTask(Object.assign({}, task, { date: state.date, start, end: Math.min(END_HOUR * 60, start + 30) }));
    await reload(); showToast(t('taskScheduled'));
  }

  function buildTask(task) {
    const category = categoryMap.get(task.category) || categoryMap.get('personal');
    const card = element('article', `task${task.done ? ' done' : ''}`);
    card.dataset.id = task.sourceId;
    card.style.top = `${minuteToY(task.start)}px`;
    card.style.height = `${Math.max(30, (task.end - task.start) * PIXELS_PER_MINUTE)}px`;
    card.style.background = category.fill;
    card.style.borderColor = category.border;
    const top = element('div', 'task-top');
    const check = document.createElement('input'); check.type = 'checkbox'; check.className = 'task-check'; check.checked = task.done; check.title = '完成任务';
    check.addEventListener('pointerdown', (event) => event.stopPropagation());
    check.addEventListener('change', async () => { await window.dailyWidget.updateOccurrence(task.sourceId, sourceOccurrenceDate(task), { done: check.checked }); await reload(); });
    const title = element('button', 'task-title', task.title || t('untitled')); title.type = 'button'; title.title = t('editTask');
    title.addEventListener('pointerdown', (event) => event.stopPropagation()); title.addEventListener('click', () => openTaskDialog(task));
    const actions = element('div', 'task-actions');
    const focus = element('button', 'task-action', task.focus ? '★' : '☆'); focus.type = 'button'; focus.title = task.focus ? '取消重点' : '设为重点';
    focus.addEventListener('pointerdown', (event) => event.stopPropagation()); focus.addEventListener('click', () => toggleFocus(task)); actions.appendChild(focus);
    if (task.url) { const link = element('button', 'task-action', '↗'); link.type = 'button'; link.title = '打开链接'; link.addEventListener('pointerdown', (event) => event.stopPropagation()); link.addEventListener('click', () => window.dailyWidget.openLink(task.url)); actions.appendChild(link); }
    const remove = element('button', 'task-action', '×'); remove.type = 'button'; remove.title = t('deleteTask'); remove.addEventListener('pointerdown', (event) => event.stopPropagation()); remove.addEventListener('click', async () => { await window.dailyWidget.deleteTask(task.sourceId); await reload(); showToast(t('taskDeleted')); }); actions.appendChild(remove);
    top.append(check, title, actions);
    const meta = element('div', 'task-meta', `${taskTimeLabel(task, task.start, task.end)} · ${t(task.category)}${task.recurrence !== 'none' ? ` · ${t('recurring')}` : ''}`);
    const resize = element('div', 'resize-handle'); resize.addEventListener('pointerdown', (event) => startResize(event, task, card));
    card.append(top, meta, resize);
    card.addEventListener('pointerdown', (event) => startMove(event, task, card));
    return card;
  }

  function startCreateFromGrid(event) {
    if (event.target !== event.currentTarget) return;
    event.preventDefault();
    const rect = event.currentTarget.getBoundingClientRect();
    const start = clampTimelineMinute(START_HOUR * 60 + (event.clientY - rect.top) / PIXELS_PER_MINUTE);
    const category = Task.CATEGORY_DEFINITIONS[state.tasks.length % Task.CATEGORY_DEFINITIONS.length];
    const preview = element('div', 'task preview'); preview.style.top = `${minuteToY(start)}px`; preview.style.height = '30px'; preview.style.background = category.fill; preview.style.borderColor = category.border; timeline.appendChild(preview);
    let finalStart = start; let finalEnd = Math.min(END_HOUR * 60, start + 30);
    function onMove(move) { const rawMinute = Math.round((move.clientY - rect.top) / PIXELS_PER_MINUTE / 15) * 15; const minute = Math.max(START_HOUR * 60, Math.min(END_HOUR * 120, rawMinute)); finalStart = Math.min(start, Math.min(END_HOUR * 60, minute)); finalEnd = Math.max(start + 15, minute); finalEnd = Math.min(END_HOUR * 120, finalEnd); preview.style.top = `${minuteToY(finalStart)}px`; preview.style.height = `${Math.max(30, (Math.min(finalEnd, END_HOUR * 60) - finalStart) * PIXELS_PER_MINUTE)}px`; }
    async function onUp() { document.removeEventListener('pointermove', onMove); document.removeEventListener('pointerup', onUp); preview.remove(); beginInlineTask({ id: Task.createId(), date: state.date, start: finalStart, end: finalEnd, title: '', category: category.id, recurrence: 'none', focus: false, notes: '', url: '', done: false }); }
    document.addEventListener('pointermove', onMove); document.addEventListener('pointerup', onUp);
  }

  function beginInlineTask(task) {
    const pending = Object.assign({ sourceId: task.id, focusDates: [], completedDates: [], deletedAt: null }, task);
    const card = buildTask(pending);
    timeline.appendChild(card);
    const titleButton = card.querySelector('.task-title');
    const input = document.createElement('input');
    input.className = 'task-inline-input'; input.placeholder = t('taskPlaceholder'); input.autocomplete = 'off';
    titleButton.replaceWith(input);
    let committed = false;
    async function commit() {
      if (committed) return;
      committed = true;
      const title = input.value.trim();
      if (!title) { card.remove(); return; }
      await window.dailyWidget.saveTask(Object.assign({}, pending, { title }));
      await reload();
    }
    input.addEventListener('pointerdown', (event) => event.stopPropagation());
    input.addEventListener('keydown', (event) => { if (event.key === 'Enter') { event.preventDefault(); input.blur(); } if (event.key === 'Escape') { committed = true; card.remove(); } });
    input.addEventListener('blur', commit);
    input.focus();
  }

  function startMove(event, task, card) {
    if (event.target.closest('button,input,.resize-handle')) return;
    if (task.isContinuation) return;
    event.preventDefault();
    const originalStart = task.sourceStart ?? task.start; const duration = (task.sourceEnd ?? task.end) - originalStart; const startY = event.clientY;
    card.classList.add('dragging');
    function onMove(move) { let start = clampTimelineMinute(originalStart + (move.clientY - startY) / PIXELS_PER_MINUTE); start = Math.min(start, END_HOUR * 60 - 15); const end = start + duration; card.style.top = `${minuteToY(start)}px`; card.style.height = `${Math.max(30, (Math.min(end, END_HOUR * 60) - start) * PIXELS_PER_MINUTE)}px`; card.querySelector('.task-meta').textContent = `${taskTimeLabel(Object.assign({}, task, { spansNextDay: end > END_HOUR * 60 }), start, end)} · ${t(task.category)}`; card.dataset.nextStart = String(start); }
    async function onUp() { document.removeEventListener('pointermove', onMove); document.removeEventListener('pointerup', onUp); const start = Number(card.dataset.nextStart || originalStart); card.classList.remove('dragging'); delete card.dataset.nextStart; if (start !== originalStart) { await window.dailyWidget.updateOccurrence(task.sourceId, sourceOccurrenceDate(task), { start, end: start + duration }); await reload(); } }
    document.addEventListener('pointermove', onMove); document.addEventListener('pointerup', onUp);
  }

  function startResize(event, task, card) {
    event.preventDefault(); event.stopPropagation(); const originalEnd = task.end; const startY = event.clientY;
    function onMove(move) { const end = Math.max(task.start + 15, clampTimelineMinute(originalEnd + (move.clientY - startY) / PIXELS_PER_MINUTE)); card.style.height = `${Math.max(30, (end - task.start) * PIXELS_PER_MINUTE)}px`; card.dataset.nextEnd = String(end); card.querySelector('.task-meta').textContent = `${Task.minuteToTime(task.start)} – ${Task.minuteToTime(end)} · ${t(task.category)}`; }
    async function onUp() { document.removeEventListener('pointermove', onMove); document.removeEventListener('pointerup', onUp); const end = Number(card.dataset.nextEnd || originalEnd); delete card.dataset.nextEnd; if (end !== originalEnd) { await window.dailyWidget.updateOccurrence(task.sourceId, sourceOccurrenceDate(task), { end: task.isContinuation ? END_HOUR * 60 + end : end }); await reload(); } }
    document.addEventListener('pointermove', onMove); document.addEventListener('pointerup', onUp);
  }

  function renderFocus() {
    const container = $('#focusList'); container.innerHTML = '';
    const focusTasks = state.tasks.filter((task) => task.focus);
    if (!focusTasks.length) { container.appendChild(element('div', 'empty-state', t('focusEmpty'))); return; }
    focusTasks.slice(0, 3).forEach((task) => { const item = element('div', 'focus-item'); const dot = element('i', 'category-dot'); dot.style.background = categoryMap.get(task.category).border; const text = element('span', null, task.title || '未命名任务'); if (task.done) text.style.textDecoration = 'line-through'; item.append(dot, text); container.appendChild(item); });
  }

  function renderInbox() {
    const container = $('#inboxList'); container.innerHTML = '';
    const isInboxView = state.activeView === 'inbox';
    container.classList.toggle('expanded', isInboxView);
    $('#inboxPanelTitle').textContent = isInboxView ? t('inboxPage') : t('inbox');
    $('#inboxContext').textContent = state.inbox.length ? t('inboxOverview', { count: state.inbox.length }) : '';
    if (!state.inbox.length) { container.appendChild(element('div', 'empty-state', t('inboxEmpty'))); return; }
    (isInboxView ? state.inbox : state.inbox.slice(0, 6)).forEach((task) => { const row = element('div', 'inbox-item'); row.draggable = true; row.title = t('inboxDragHint'); row.addEventListener('dragstart', (event) => { state.dragInboxId = task.id; event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('text/plain', task.id); row.classList.add('drag-source'); }); row.addEventListener('dragend', () => { state.dragInboxId = null; row.classList.remove('drag-source'); document.querySelectorAll('.grid-hit').forEach((target) => target.classList.remove('drop-active')); }); const title = element('strong', null, task.title || t('untitled')); const edit = element('button', null, '⋯'); edit.title = t('editTask'); edit.addEventListener('click', () => openTaskDialog(task)); const schedule = element('button', null, '＋'); schedule.title = t('scheduleToday'); schedule.addEventListener('click', () => scheduleInboxTask(task)); row.append(title, edit, schedule); container.appendChild(row); });
  }

  function renderSyncStatus() {
    const status = $('#syncStatus'); const settings = state.settings || {};
    if (!settings.syncFolder) { status.textContent = t('localOnly'); status.className = 'sync-status'; return; }
    if (settings.lastSyncError) { status.textContent = t('syncIssue', { error: settings.lastSyncError }); status.className = 'sync-status warn'; return; }
    status.textContent = settings.lastSyncAt ? t('synced', { time: new Date(settings.lastSyncAt).toLocaleTimeString(language() === 'en' ? 'en-US' : 'zh-CN', { hour: '2-digit', minute: '2-digit' }) }) : t('connected'); status.className = 'sync-status ok';
  }

  async function scheduleInboxTask(task) {
    const now = new Date(); const defaultStart = isToday() ? clampTimelineMinute(now.getHours() * 60 + now.getMinutes()) : 9 * 60;
    await window.dailyWidget.saveTask(Object.assign({}, task, { date: state.date, start: defaultStart, end: defaultStart + 30 }));
    await reload(); showToast(t('taskScheduled'));
  }

  async function toggleFocus(task) {
    if (!task.focus && state.tasks.filter((item) => item.focus && item.sourceId !== task.sourceId).length >= 3) { showToast(t('focusLimit')); return; }
    await window.dailyWidget.updateOccurrence(task.sourceId, sourceOccurrenceDate(task), { focus: !task.focus }); await reload();
  }

  function setField(id, value) { $(id).value = value === null || value === undefined ? '' : value; }
  function openTaskDialog(task) {
    state.editing = task && task.sourceId ? task : null;
    $('#taskDialogTitle').textContent = state.editing ? t('editTask') : t('newTask');
    setField('#taskId', state.editing ? state.editing.sourceId : '');
    setField('#taskDateOriginal', state.editing ? (state.editing.sourceDate || state.editing.date) : '');
    setField('#taskTitle', task && task.title); setField('#taskDate', task && (task.sourceDate || task.date)); setField('#taskStart', timeInputValue(task && (task.sourceStart ?? task.start))); setField('#taskEnd', timeInputValue(task && (task.sourceEnd ?? task.end))); setField('#taskCategory', (task && task.category) || 'personal'); setField('#taskRecurrence', (task && task.recurrence) || 'none'); setField('#taskUrl', task && task.url); setField('#taskNotes', task && task.notes);
    $('#taskFocus').checked = Boolean(task && task.focus); $('#deleteTask').style.visibility = state.editing ? 'visible' : 'hidden';
    taskDialog.showModal(); $('#taskTitle').focus();
  }

  async function saveTaskFromDialog(event) {
    event.preventDefault();
    const title = $('#taskTitle').value.trim(); if (!title) { showToast(t('titleRequired')); return; }
    const id = $('#taskId').value; const date = $('#taskDate').value || null; const start = timeToMinute($('#taskStart').value); let end = timeToMinute($('#taskEnd').value);
    if ((start === null) !== (end === null)) { showToast(t('bothTimes')); return; }
    if (start !== null && end === start) { showToast(t('validRange')); return; }
    if (start !== null && end < start) end += 24 * 60;
    const recurrence = $('#taskRecurrence').value;
    if (recurrence !== 'none' && !date) { showToast(t('recurringDate')); return; }
    if ($('#taskFocus').checked && !state.editing?.focus && state.tasks.filter((task) => task.focus).length >= 3) { showToast(t('focusLimit')); return; }
    const payload = { id: id || undefined, title, date, start, end, category: $('#taskCategory').value, recurrence, focus: $('#taskFocus').checked, url: $('#taskUrl').value, notes: $('#taskNotes').value };
    if (state.editing && state.editing.recurrence !== 'none') payload.date = $('#taskDateOriginal').value;
    await window.dailyWidget.saveTask(payload);
    taskDialog.close(); await reload(); showToast(t('taskSaved'));
  }

  async function deleteEditingTask() { if (!state.editing) return; await window.dailyWidget.deleteTask(state.editing.sourceId); taskDialog.close(); await reload(); showToast(t('taskDeleted')); }
  function closeTaskDialog() { taskDialog.close(); }

  function openReview() {
    const incomplete = scheduledIncomplete(); const container = $('#reviewList'); container.innerHTML = '';
    if (!incomplete.length) container.appendChild(element('div', 'empty-state', t('noReview')));
    incomplete.forEach((task) => { const row = element('div', 'review-item'); row.appendChild(element('span', null, task.title || t('untitled'))); const tomorrow = element('button', null, t('tomorrow')); tomorrow.addEventListener('click', async () => { await window.dailyWidget.saveTask(Object.assign({}, task, { date: Task.addDays(state.date, 1) })); await reload(); openReview(); }); const inbox = element('button', null, t('moveInbox')); inbox.addEventListener('click', async () => { await window.dailyWidget.moveToInbox(task.sourceId); await reload(); openReview(); }); row.append(tomorrow, inbox); container.appendChild(row); });
    reviewDialog.showModal();
  }

  async function addQuickTask() {
    const input = $('#quickInput'); const parsed = Task.parseQuickInput(input.value, state.date, new Date());
    if (!parsed.title) { showToast(t('writeTask')); return; }
    await window.dailyWidget.saveTask({ title: parsed.title, date: parsed.date, start: parsed.start, end: parsed.end, category: 'personal', recurrence: 'none' }); input.value = ''; await reload(); showToast(parsed.start === null ? t('addedInbox') : t('addedSchedule'));
  }

  function openExportMenu() { $('#exportDialogTitle').textContent = t('exportMarkdown'); $('#exportDialogHint').textContent = t('exportHint'); $('#exportStartLabel').textContent = t('exportStart'); $('#exportEndLabel').textContent = t('exportEnd'); $('#exportStartDate').value = state.date; $('#exportEndDate').value = state.date; $('#exportError').hidden = true; $('#closeExportSecondary').textContent = t('cancel'); $('#exportRangeButton').textContent = t('exportRange'); exportDialog.showModal(); }
  async function exportTasks() { const startDate = $('#exportStartDate').value; const endDate = $('#exportEndDate').value; const error = $('#exportError'); if (!Task.isDateKey(startDate) || !Task.isDateKey(endDate) || endDate < startDate) { error.textContent = t('exportInvalid'); error.hidden = false; return; } try { const result = await window.dailyWidget.exportRange(startDate, endDate); exportDialog.close(); try { await navigator.clipboard.writeText(result.markdown); showToast(t('exported')); } catch (_) { showToast(`${t('exported')} · ${result.filePath}`); } } catch (_) { error.textContent = t('exportInvalid'); error.hidden = false; } }
  async function syncNow() { const result = await window.dailyWidget.syncNow(); await reload(); showToast(result.ok ? t('syncedToast', { push: result.pushed || 0, pull: result.pulled || 0 }) : (result.message || t('chooseFolder'))); }
  async function chooseSyncFolder() { const result = await window.dailyWidget.chooseSyncFolder(); if (result.canceled) return; await syncNow(); }
  async function cycleTheme() { const themes = ['system', 'light', 'dark']; const next = themes[(themes.indexOf(state.settings.theme || 'system') + 1) % themes.length]; state.settings = await window.dailyWidget.updateSettings({ theme: next }); applyTheme(); showToast(next === 'system' ? t('themeSystem') : (next === 'dark' ? t('themeDark') : t('themeLight'))); }
  async function toggleLanguage() { state.settings = await window.dailyWidget.updateSettings({ language: language() === 'zh' ? 'en' : 'zh' }); render(); }
  async function changeDate(days) { state.date = Task.addDays(state.date, days); await reload(); }

  function bindEvents() {
    $('#previousDay').addEventListener('click', () => changeDate(-1)); $('#nextDay').addEventListener('click', () => changeDate(1)); $('#todayButton').addEventListener('click', async () => { state.date = Task.formatDateKey(new Date()); state.activeView = 'today'; await reload(); });
    $('#quickAdd').addEventListener('click', addQuickTask); $('#quickInput').addEventListener('keydown', (event) => { if (event.key === 'Enter') addQuickTask(); }); $('#newInbox').addEventListener('click', () => openTaskDialog({ date: null, start: null, end: null, category: 'personal', recurrence: 'none' }));
    $('#taskForm').addEventListener('submit', saveTaskFromDialog); $('#cancelTask').addEventListener('click', closeTaskDialog); $('#deleteTask').addEventListener('click', deleteEditingTask); $('#reviewButton').addEventListener('click', () => setActiveView('review')); $('#closeReview').addEventListener('click', () => reviewDialog.close());
    $('#exportButton').addEventListener('click', openExportMenu); $('#closeExport').addEventListener('click', () => exportDialog.close()); $('#closeExportSecondary').addEventListener('click', () => exportDialog.close()); $('#exportRangeButton').addEventListener('click', exportTasks); $('#syncButton').addEventListener('click', syncNow); $('#syncFolderBtn').addEventListener('click', chooseSyncFolder); $('#themeButton').addEventListener('click', cycleTheme); $('#languageButton').addEventListener('click', toggleLanguage); $('#clearFocus').addEventListener('click', () => showToast(t('focusManage')));
    document.querySelectorAll('[data-view]').forEach((button) => button.addEventListener('click', async () => { if (button.dataset.view === 'today') { state.date = Task.formatDateKey(new Date()); state.activeView = 'today'; await reload(); } else setActiveView(button.dataset.view); }));
    window.dailyWidget.onSyncChanged(async () => { await reload(); showToast(t('remoteChange')); });
    setInterval(() => { if (isToday()) { renderSummary(); renderTimeline(); } }, 60000);
  }

  async function boot() { await window.dailyWidget.init(); bindEvents(); await reload(); }
  boot().catch((error) => { console.error(error); showToast(`启动失败：${error.message}`); });
})();
