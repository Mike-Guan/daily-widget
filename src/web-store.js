(function webStoreFallback() {
  'use strict';
  if (window.dailyWidget) return;
  const Task = window.DailyWidgetTaskModel;
  const PREFIX = 'daily-widget-v1:';
  const SETTINGS_KEY = `${PREFIX}settings`;
  function read(key, fallback) { try { const value = localStorage.getItem(key); return value ? JSON.parse(value) : fallback; } catch (_) { return fallback; } }
  function write(key, value) { localStorage.setItem(key, JSON.stringify(value)); return value; }
  function settings() { return read(SETTINGS_KEY, { schemaVersion: 1, deviceId: 'browser-local', theme: 'system', language: 'zh', syncFolder: null, lastSyncAt: null, lastSyncError: null }); }
  function all() { return read(`${PREFIX}tasks`, []); }
  function saveAll(records) { write(`${PREFIX}tasks`, records); }
  function migrateLegacy() {
    const records = all();
    if (records.length) return;
    Object.keys(localStorage).filter((key) => key.startsWith('daily-widget:')).forEach((key) => {
      const date = key.slice('daily-widget:'.length);
      const legacy = read(key, []);
      if (Task.isDateKey(date) && Array.isArray(legacy)) records.push(...legacy.map((entry) => Task.legacyTaskToRecord(entry, date, { deviceId: 'browser-local' })));
    });
    saveAll(records);
  }
  function find(id) { return all().find((record) => record.id === id) || null; }
  window.dailyWidget = {
    init: async () => { migrateLegacy(); return { syncFolder: null }; },
    getDay: async (date) => Task.sortTasks(all().map((record) => Task.occurrenceFor(record, date)).filter(Boolean)),
    getInbox: async () => Task.sortTasks(all().filter((record) => !record.deletedAt && !record.date)),
    saveTask: async (input) => { const records = all(); const index = input.id ? records.findIndex((record) => record.id === input.id) : -1; const record = index >= 0 ? Task.updateTask(records[index], input, { deviceId: 'browser-local' }) : Task.normalizeTask(input, { deviceId: 'browser-local' }); if (index >= 0) records[index] = record; else records.push(record); saveAll(records); return record; },
    updateOccurrence: async (id, date, patch) => { const existing = find(id); if (!existing) throw new Error('Task not found'); let next = Object.assign({}, patch); if (existing.recurrence !== 'none' && Object.prototype.hasOwnProperty.call(next, 'done')) { const completed = new Set(existing.completedDates); if (next.done) completed.add(date); else completed.delete(date); next.completedDates = [...completed].sort(); delete next.done; } if (existing.recurrence !== 'none' && Object.prototype.hasOwnProperty.call(next, 'focus')) { const focusDates = new Set(existing.focusDates || []); if (next.focus) focusDates.add(date); else focusDates.delete(date); next.focusDates = [...focusDates].sort(); delete next.focus; } return window.dailyWidget.saveTask(Object.assign({}, existing, next)); },
    deleteTask: async (id) => { const existing = find(id); return existing ? window.dailyWidget.saveTask(Object.assign({}, existing, { deletedAt: new Date().toISOString() })) : null; },
    moveToInbox: async (id) => { const existing = find(id); return existing ? window.dailyWidget.saveTask(Object.assign({}, existing, { date: null, start: null, end: null, focus: false })) : null; },
    exportDay: async (date) => { const tasks = await window.dailyWidget.getDay(date); const markdown = Task.toMarkdown(tasks, date); download(markdown, `${date}-tasks.md`); return { markdown, filePath: 'browser download' }; },
    exportWeek: async (date) => { const selected = Task.dateFromKey(date); const start = new Date(selected); start.setDate(selected.getDate() - ((selected.getDay() + 6) % 7)); const keys = Array.from({ length: 7 }, (_, index) => Task.formatDateKey(new Date(start.getFullYear(), start.getMonth(), start.getDate() + index))); const markdown = `# Weekly Tasks — ${keys[0]} to ${keys[6]}\n\n${(await Promise.all(keys.map(async (key) => Task.toMarkdown(await window.dailyWidget.getDay(key), key)))).join('\n')}`; download(markdown, `${keys[0]}-week.md`); return { markdown, filePath: 'browser download', weekStart: keys[0], weekEnd: keys[6] }; },
    exportRange: async (startDate, endDate) => { if (!Task.isDateKey(startDate) || !Task.isDateKey(endDate) || endDate < startDate) throw new Error('Choose a valid date range'); const keys = []; let key = startDate; while (key <= endDate) { keys.push(key); if (keys.length > 366) throw new Error('Date range is limited to one year'); key = Task.addDays(key, 1); } const markdown = `# Tasks — ${startDate}${startDate === endDate ? '' : ` to ${endDate}`}\n\n${(await Promise.all(keys.map(async (date) => Task.toMarkdown(await window.dailyWidget.getDay(date), date)))).join('\n')}`; const filename = startDate === endDate ? `${startDate}-tasks.md` : `${startDate}-to-${endDate}-tasks.md`; download(markdown, filename); return { markdown, filePath: 'browser download', startDate, endDate }; },
    getSettings: async () => settings(),
    updateSettings: async (patch) => write(SETTINGS_KEY, Object.assign({}, settings(), patch)),
    getSyncStatus: async () => ({ syncFolder: null, lastSyncAt: null, lastSyncError: null }),
    syncNow: async () => ({ ok: false, message: '浏览器版无法直接访问共享文件夹；请使用桌面或 iPhone app。' }),
    chooseSyncFolder: async () => ({ canceled: true }),
    openLink: async (url) => { window.open(url, '_blank', 'noopener'); return true; },
    onSyncChanged: () => {},
  };

  function download(markdown, filename) { const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob([markdown], { type: 'text/markdown' })); link.download = filename; link.click(); URL.revokeObjectURL(link.href); }
})();
