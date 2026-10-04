(function exposeTaskModel(root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.DailyWidgetTaskModel = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function taskModelFactory() {
  'use strict';

  const SCHEMA_VERSION = 2;
  const MINUTES_PER_DAY = 24 * 60;
  const TASK_COLOR_TOKENS = [
    { id: 'indigo', fill: '#dce8ff', border: '#7e9eea' },
    { id: 'mint', fill: '#d8f3e2', border: '#71b98d' },
    { id: 'amber', fill: '#fff0ca', border: '#dfb34e' },
    { id: 'rose', fill: '#fde0ec', border: '#dd8fae' },
    { id: 'violet', fill: '#e9defd', border: '#ad91dc' },
    { id: 'coral', fill: '#ffe2cf', border: '#de986d' },
    { id: 'sky', fill: '#d8efff', border: '#6caee4' },
  ];
  const COLOR_TOKEN_IDS = new Set(TASK_COLOR_TOKENS.map((token) => token.id));
  const CATEGORY_DEFINITIONS = [
    { id: 'personal', label: '个人', colorToken: 'indigo' },
    { id: 'health', label: '健康', colorToken: 'mint' },
    { id: 'home', label: '生活', colorToken: 'amber' },
    { id: 'social', label: '关系', colorToken: 'rose' },
    { id: 'learning', label: '学习', colorToken: 'violet' },
    { id: 'errands', label: '杂事', colorToken: 'coral' },
  ];
  const CATEGORY_IDS = new Set(CATEGORY_DEFINITIONS.map((category) => category.id));
  const RECURRENCES = new Set(['none', 'daily', 'weekdays', 'weekly']);

  function nowIso() {
    return new Date().toISOString();
  }

  function createId() {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
    return `task-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
  }

  function isDateKey(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const date = new Date(`${value}T12:00:00`);
    return !Number.isNaN(date.valueOf()) && formatDateKey(date) === value;
  }

  function dateFromKey(dateKey) {
    if (!isDateKey(dateKey)) throw new Error(`Invalid date key: ${dateKey}`);
    return new Date(`${dateKey}T12:00:00`);
  }

  function formatDateKey(date) {
    const d = date instanceof Date ? date : new Date(date);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  function addDays(dateKey, count) {
    const date = dateFromKey(dateKey);
    date.setDate(date.getDate() + count);
    return formatDateKey(date);
  }

  function clampMinute(value) {
    const minute = Number(value);
    if (!Number.isFinite(minute)) return null;
    return Math.max(0, Math.min(MINUTES_PER_DAY, Math.round(minute / 15) * 15));
  }

  function clampEndMinute(value) {
    const minute = Number(value);
    if (!Number.isFinite(minute)) return null;
    return Math.max(0, Math.min(MINUTES_PER_DAY * 2, Math.round(minute / 15) * 15));
  }

  function normalizeRecurrence(value) {
    const type = typeof value === 'string' ? value : value && value.type;
    return RECURRENCES.has(type) ? type : 'none';
  }

  function stableString(value) {
    return JSON.stringify(value, Object.keys(value || {}).sort());
  }

  function normalizeUrl(value) {
    if (typeof value !== 'string') return '';
    const trimmed = value.trim();
    if (!trimmed) return '';
    try {
      const url = new URL(trimmed);
      return ['http:', 'https:'].includes(url.protocol) ? url.href : '';
    } catch (_) {
      return '';
    }
  }

  function normalizeCompletedDates(value) {
    if (!Array.isArray(value)) return [];
    return [...new Set(value.filter(isDateKey))].sort();
  }

  function normalizeFocusDates(value) {
    return normalizeCompletedDates(value);
  }

  function categoryColorToken(category) {
    return (CATEGORY_DEFINITIONS.find((item) => item.id === category) || CATEGORY_DEFINITIONS[0]).colorToken;
  }

  function normalizeColorMode(value) {
    return value === 'custom' ? 'custom' : 'category';
  }

  function normalizeColorToken(value, category, mode) {
    if (mode === 'custom' && COLOR_TOKEN_IDS.has(value)) return value;
    return null;
  }

  function resolveTaskColor(task) {
    const category = CATEGORY_IDS.has(task && task.category) ? task.category : 'personal';
    const token = task && task.colorMode === 'custom' && COLOR_TOKEN_IDS.has(task.colorToken)
      ? task.colorToken
      : categoryColorToken(category);
    return TASK_COLOR_TOKENS.find((item) => item.id === token) || TASK_COLOR_TOKENS[0];
  }

  function normalizeTask(input, options) {
    const source = input || {};
    const config = options || {};
    const createdAt = typeof source.createdAt === 'string' ? source.createdAt : (config.now || nowIso());
    const updatedAt = typeof source.updatedAt === 'string' ? source.updatedAt : createdAt;
    const date = isDateKey(source.date) ? source.date : (isDateKey(config.date) ? config.date : null);
    const rawStart = source.start !== undefined ? source.start : source.startMin;
    const rawEnd = source.end !== undefined ? source.end : source.endMin;
    let start = clampMinute(rawStart);
    let end = clampEndMinute(rawEnd);
    if (!date || start === null || end === null) {
      start = null;
      end = null;
    } else if (end < start) {
      end += MINUTES_PER_DAY;
    } else if (end === start) {
      end = start + 30;
    }
    if (end !== null && start !== null) end = Math.min(start + MINUTES_PER_DAY, end);
    const title = String(source.title !== undefined ? source.title : (source.text || '')).trim();
    const category = CATEGORY_IDS.has(source.category) ? source.category : 'personal';
    const colorMode = normalizeColorMode(source.colorMode);
    return {
      schemaVersion: SCHEMA_VERSION,
      id: typeof source.id === 'string' && source.id ? source.id : createId(),
      date,
      start,
      end,
      title,
      done: Boolean(source.done),
      focus: Boolean(source.focus),
      focusDates: normalizeFocusDates(source.focusDates),
      category,
      colorMode,
      colorToken: normalizeColorToken(source.colorToken, category, colorMode),
      notes: typeof source.notes === 'string' ? source.notes : '',
      url: normalizeUrl(source.url),
      recurrence: normalizeRecurrence(source.recurrence),
      completedDates: normalizeCompletedDates(source.completedDates),
      createdAt,
      updatedAt,
      updatedBy: typeof source.updatedBy === 'string' ? source.updatedBy : (config.deviceId || 'local'),
      deletedAt: typeof source.deletedAt === 'string' ? source.deletedAt : null,
    };
  }

  function taskChanged(existing, next) {
    const a = Object.assign({}, existing, { updatedAt: undefined, updatedBy: undefined });
    const b = Object.assign({}, next, { updatedAt: undefined, updatedBy: undefined });
    return stableString(a) !== stableString(b);
  }

  function updateTask(existing, patch, options) {
    const config = options || {};
    const next = normalizeTask(Object.assign({}, existing, patch, {
      id: existing.id,
      createdAt: existing.createdAt,
      updatedAt: config.now || nowIso(),
      updatedBy: config.deviceId || existing.updatedBy,
    }), config);
    return taskChanged(existing, next) ? next : existing;
  }

  function isPrimaryOccurrenceOn(task, dateKey) {
    if (!task || task.deletedAt || !task.date || !isDateKey(dateKey) || dateKey < task.date) return false;
    const recurrence = normalizeRecurrence(task.recurrence);
    if (recurrence === 'none') return task.date === dateKey;
    if (recurrence === 'daily') return true;
    const selectedDay = dateFromKey(dateKey).getDay();
    if (recurrence === 'weekdays') return selectedDay >= 1 && selectedDay <= 5;
    return selectedDay === dateFromKey(task.date).getDay();
  }

  function occurrencesFor(task, dateKey) {
    if (!task || task.deletedAt || !task.date || !isDateKey(dateKey)) return [];
    const repeating = normalizeRecurrence(task.recurrence) !== 'none';
    const records = [];
    if (isPrimaryOccurrenceOn(task, dateKey)) {
      records.push(Object.assign({}, task, {
        date: dateKey,
        occurrenceId: repeating ? `${task.id}@${dateKey}` : task.id,
        sourceId: task.id,
        sourceDate: task.date,
        sourceOccurrenceDate: dateKey,
        sourceStart: task.start,
        sourceEnd: task.end,
        end: Math.min(task.end, MINUTES_PER_DAY),
        done: repeating ? task.completedDates.includes(dateKey) : task.done,
        focus: repeating ? task.focusDates.includes(dateKey) : task.focus,
        isOccurrence: repeating,
        spansNextDay: task.end > MINUTES_PER_DAY,
        isContinuation: false,
      }));
    }
    const previousDate = addDays(dateKey, -1);
    if (task.end > MINUTES_PER_DAY && isPrimaryOccurrenceOn(task, previousDate)) {
      records.push(Object.assign({}, task, {
        date: dateKey,
        occurrenceId: `${task.id}@${previousDate}:continuation`,
        sourceId: task.id,
        sourceDate: task.date,
        sourceOccurrenceDate: previousDate,
        sourceStart: task.start,
        sourceEnd: task.end,
        start: 0,
        end: task.end - MINUTES_PER_DAY,
        done: repeating ? task.completedDates.includes(previousDate) : task.done,
        focus: repeating ? task.focusDates.includes(previousDate) : task.focus,
        isOccurrence: true,
        spansNextDay: false,
        isContinuation: true,
      }));
    }
    return records;
  }

  function occursOn(task, dateKey) {
    return occurrencesFor(task, dateKey).length > 0;
  }

  function occurrenceFor(task, dateKey) {
    return occurrencesFor(task, dateKey).find((taskRecord) => !taskRecord.isContinuation) || null;
  }

  function sortTasks(tasks) {
    return tasks.slice().sort((a, b) => {
      const aStart = a.start === null ? Number.MAX_SAFE_INTEGER : a.start;
      const bStart = b.start === null ? Number.MAX_SAFE_INTEGER : b.start;
      return aStart - bStart || a.title.localeCompare(b.title) || a.id.localeCompare(b.id);
    });
  }

  function legacyTaskToRecord(legacyTask, dateKey, options) {
    const colorToCategory = {
      '#d3f2dd': 'health', '#fff3c4': 'home', '#ffd6e8': 'social', '#e6d9ff': 'learning', '#ffe0c2': 'errands',
    };
    return normalizeTask(Object.assign({}, legacyTask, {
      date: dateKey,
      title: legacyTask.title || legacyTask.text || '',
      category: colorToCategory[legacyTask.color] || 'personal',
    }), options);
  }

  function compareTasks(left, right) {
    const leftTime = Date.parse(left.updatedAt || '') || 0;
    const rightTime = Date.parse(right.updatedAt || '') || 0;
    if (leftTime !== rightTime) return leftTime - rightTime;
    return String(left.updatedBy || '').localeCompare(String(right.updatedBy || ''));
  }

  function mergeTaskRecords(local, remote) {
    if (!local) return { winner: remote, loser: null, conflict: false };
    if (!remote) return { winner: local, loser: null, conflict: false };
    const normalizedLocal = normalizeTask(local);
    const normalizedRemote = normalizeTask(remote);
    const equal = stableString(normalizedLocal) === stableString(normalizedRemote);
    if (equal) return { winner: normalizedLocal, loser: null, conflict: false };
    if (normalizedLocal.deletedAt && !normalizedRemote.deletedAt) return { winner: normalizedLocal, loser: normalizedRemote, conflict: true };
    if (normalizedRemote.deletedAt && !normalizedLocal.deletedAt) return { winner: normalizedRemote, loser: normalizedLocal, conflict: true };
    const remoteWins = compareTasks(normalizedLocal, normalizedRemote) <= 0;
    return {
      winner: remoteWins ? normalizedRemote : normalizedLocal,
      loser: remoteWins ? normalizedLocal : normalizedRemote,
      conflict: true,
    };
  }

  function escapeMarkdown(value) {
    return String(value || '').replace(/[\r\n]+/g, ' ').replace(/([\\`*_{}\[\]<>])/g, '\\$1');
  }

  function minuteToTime(minute) {
    const safe = ((Number(minute) || 0) % MINUTES_PER_DAY + MINUTES_PER_DAY) % MINUTES_PER_DAY;
    const hours = Math.floor(safe / 60);
    return `${String(hours).padStart(2, '0')}:${String(safe % 60).padStart(2, '0')}`;
  }

  function toMarkdown(tasks, dateKey) {
    const visible = sortTasks(tasks.filter((task) => !task.deletedAt));
    let markdown = `## Daily Tasks — ${dateKey}\n\n`;
    if (!visible.length) return `${markdown}_No tasks recorded._\n`;
    visible.forEach((task) => {
      const check = task.done ? '[x]' : '[ ]';
      const time = task.start === null ? '' : `${minuteToTime(task.start)}–${minuteToTime(task.end)}${task.spansNextDay ? ' (+1)' : ''} `;
      const title = escapeMarkdown(task.title || '(untitled task)');
      const link = task.url ? ` ([link](${task.url}))` : '';
      markdown += `- ${check} ${time}${title}${link}\n`;
    });
    return markdown;
  }

  function parseQuickInput(text, dateKey, now) {
    const original = String(text || '').trim();
    const fallbackDate = isDateKey(dateKey) ? dateKey : formatDateKey(now || new Date());
    let date = fallbackDate;
    let remainder = original.replace(/：/g, ':');
    if (/^(明天\s*|tomorrow\b\s*)/i.test(remainder)) {
      date = addDays(fallbackDate, 1);
      remainder = remainder.replace(/^(明天\s*|tomorrow\b\s*)/i, '');
    } else if (/^(今天\s*|today\b\s*)/i.test(remainder)) {
      remainder = remainder.replace(/^(今天\s*|today\b\s*)/i, '');
    }
    const durationMatch = remainder.match(/(\d+(?:\.5)?)\s*(m|min|分钟|h|hr|小时)\s*$/i);
    let duration = 30;
    if (durationMatch) {
      const amount = Number(durationMatch[1]);
      duration = /h|hr|小时/i.test(durationMatch[2]) ? amount * 60 : amount;
      duration = Math.max(15, Math.min(8 * 60, Math.round(duration / 15) * 15));
      remainder = remainder.slice(0, durationMatch.index).trim();
    }
    const timeMatch = remainder.match(/^(?:at\s*)?(\d{1,2})(?::(\d{2}))?\s*(.+)$/i);
    let start = null;
    let hasExplicitTime = false;
    if (timeMatch) {
      const hour = Number(timeMatch[1]);
      const minute = Number(timeMatch[2] || 0);
      if (hour <= 23 && minute <= 59) {
        start = clampMinute(hour * 60 + minute);
        remainder = timeMatch[3].trim();
        hasExplicitTime = true;
      }
    }
    if (start === null) {
      const chineseTime = remainder.match(/^([零一二三四五六七八九十两]+)\s*(?:点|時|时)\s*(?:(\d{1,2}|[零一二三四五六七八九十两]+)|半)?\s*(.*)$/);
      if (chineseTime) {
        const hour = chineseNumber(chineseTime[1]);
        const minute = chineseTime[2] === '半' ? 30 : (chineseTime[2] ? chineseNumber(chineseTime[2]) : 0);
        if (hour !== null && minute !== null && hour <= 23 && minute <= 59) {
          start = clampMinute(hour * 60 + minute);
          remainder = chineseTime[3].trim();
          hasExplicitTime = true;
        }
      }
    }
    const end = start === null ? null : start + duration;
    return { date: hasExplicitTime ? date : null, start, end, title: remainder || original, duration, hasExplicitTime };
  }

  function chineseNumber(value) {
    if (/^\d+$/.test(value)) return Number(value);
    const digits = { 零: 0, 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
    if (Object.prototype.hasOwnProperty.call(digits, value)) return digits[value];
    if (value === '十') return 10;
    const tenIndex = value.indexOf('十');
    if (tenIndex === -1) return null;
    const tens = tenIndex === 0 ? 1 : digits[value[0]];
    const ones = tenIndex === value.length - 1 ? 0 : digits[value[tenIndex + 1]];
    return tens === undefined || ones === undefined ? null : tens * 10 + ones;
  }

  return {
    SCHEMA_VERSION,
    MINUTES_PER_DAY,
    CATEGORY_DEFINITIONS,
    TASK_COLOR_TOKENS,
    addDays,
    clampMinute,
    createId,
    dateFromKey,
    escapeMarkdown,
    formatDateKey,
    isDateKey,
    legacyTaskToRecord,
    mergeTaskRecords,
    minuteToTime,
    normalizeTask,
    occurrenceFor,
    occurrencesFor,
    occursOn,
    parseQuickInput,
    resolveTaskColor,
    sortTasks,
    toMarkdown,
    updateTask,
  };
});
