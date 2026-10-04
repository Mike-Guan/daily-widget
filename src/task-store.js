'use strict';

const crypto = require('crypto');
const childProcess = require('child_process');
const fs = require('fs');
const path = require('path');
const Task = require('./task-model');

function ensureDirectory(directory) {
  fs.mkdirSync(directory, { recursive: true });
}

async function ensureDirectoryAsync(directory) {
  await fs.promises.mkdir(directory, { recursive: true });
}

function safeReadJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function writeJsonAtomic(filePath, value) {
  ensureDirectory(path.dirname(filePath));
  const temporaryPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  fs.renameSync(temporaryPath, filePath);
}

async function writeJsonAtomicAsync(filePath, value) {
  await ensureDirectoryAsync(path.dirname(filePath));
  const temporaryPath = `${filePath}.${process.pid}.${Date.now()}.${crypto.randomUUID()}.tmp`;
  await fs.promises.writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  await fs.promises.rename(temporaryPath, filePath);
}

function listJsonFiles(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.json'))
    .map((entry) => path.join(directory, entry.name));
}

async function listJsonFilesAsync(directory) {
  try {
    const entries = await fs.promises.readdir(directory, { withFileTypes: true });
    return entries
      .filter((entry) => entry.isFile() && entry.name.endsWith('.json'))
      .map((entry) => path.join(directory, entry.name));
  } catch (error) {
    if (error && error.code === 'ENOENT') return [];
    throw error;
  }
}

function safeReadJsonIsolated(filePath, fallback, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = childProcess.spawn(process.execPath, [path.join(__dirname, 'read-json-child.js'), filePath], {
      env: Object.assign({}, process.env, { ELECTRON_RUN_AS_NODE: '1' }),
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    let output = '';
    let settled = false;
    let timer;
    const finish = (callback) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      callback();
    };
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.once('error', (error) => finish(() => reject(error)));
    child.once('close', () => finish(() => {
      try {
        const result = JSON.parse(output);
        if (result.ok) resolve(result.value);
        else if (['ENOENT', 'EISDIR'].includes(result.code)) resolve(fallback);
        else if (result.name === 'SyntaxError') resolve(fallback);
        else reject(Object.assign(new Error(result.message || 'Unable to read shared task file'), { code: result.code }));
      } catch (error) {
        reject(error);
      }
    }));
    timer = setTimeout(() => {
      child.kill('SIGKILL');
      finish(() => {
        const error = new Error(`A shared task file is not available offline yet: ${path.basename(filePath)}`);
        error.code = 'SYNC_FILE_UNAVAILABLE';
        reject(error);
      });
    }, timeoutMs);
  });
}

async function safeReadJsonAsync(filePath, fallback, timeoutMs) {
  if (timeoutMs) return safeReadJsonIsolated(filePath, fallback, timeoutMs);
  try {
    return JSON.parse(await fs.promises.readFile(filePath, 'utf8'));
  } catch (error) {
    if (error && ['ENOENT', 'EISDIR'].includes(error.code)) return fallback;
    if (error instanceof SyntaxError) return fallback;
    throw error;
  }
}

function normalizeFolder(folderPath) {
  if (typeof folderPath !== 'string' || !folderPath.trim()) return null;
  return path.resolve(folderPath.trim());
}

class TaskStore {
  constructor(options) {
    this.rootDirectory = path.resolve(options.rootDirectory);
    this.exportDirectory = path.resolve(options.exportDirectory);
    this.tasksDirectory = path.join(this.rootDirectory, 'tasks');
    this.backupDirectory = path.join(this.rootDirectory, 'backups');
    this.settingsPath = path.join(this.rootDirectory, 'settings.json');
    this.deviceId = options.deviceId || `desktop-${crypto.randomUUID()}`;
    this.watcher = null;
    this.watchTimer = null;
    this.isSyncing = false;
    this.ignoreWatchUntil = 0;
    this.onRemoteChange = options.onRemoteChange || (() => {});
  }

  init() {
    ensureDirectory(this.rootDirectory);
    ensureDirectory(this.tasksDirectory);
    ensureDirectory(this.exportDirectory);
    ensureDirectory(this.backupDirectory);
    this.ensureSettings();
    this.migrateLegacyDailyFiles();
    this.repairPartiallyScheduledTasks();
    this.watchConfiguredFolder();
    return this.getStatus();
  }

  ensureSettings() {
    const existing = safeReadJson(this.settingsPath, null);
    if (existing && typeof existing === 'object') {
      if (!existing.deviceId) {
        existing.deviceId = this.deviceId;
        writeJsonAtomic(this.settingsPath, existing);
      }
      this.deviceId = existing.deviceId;
      return existing;
    }
    const settings = {
      schemaVersion: Task.SCHEMA_VERSION,
      deviceId: this.deviceId,
      theme: 'system',
      language: 'zh',
      syncFolder: null,
      syncBookmark: null,
      lastSyncAt: null,
      lastSyncError: null,
      lastSyncErrorCode: null,
    };
    writeJsonAtomic(this.settingsPath, settings);
    return settings;
  }

  getSettings() {
    return this.ensureSettings();
  }

  updateSettings(patch) {
    const current = this.getSettings();
    const next = Object.assign({}, current, patch || {});
    if (next.syncFolder) next.syncFolder = normalizeFolder(next.syncFolder);
    writeJsonAtomic(this.settingsPath, next);
    if (Object.prototype.hasOwnProperty.call(patch || {}, 'syncFolder')) this.watchConfiguredFolder();
    return next;
  }

  taskPath(id, directory) {
    if (typeof id !== 'string' || !/^[a-zA-Z0-9@._-]+$/.test(id)) throw new Error('Invalid task ID');
    return path.join(directory || this.tasksDirectory, `${id}.json`);
  }

  allRecords(directory) {
    return listJsonFiles(directory || this.tasksDirectory)
      .map((filePath) => safeReadJson(filePath, null))
      .filter((value) => value && typeof value === 'object' && typeof value.id === 'string')
      .map((value) => Task.normalizeTask(value, { deviceId: value.updatedBy || this.deviceId }));
  }

  async allRecordsAsync(directory, options) {
    const files = await listJsonFilesAsync(directory || this.tasksDirectory);
    const values = await Promise.all(files.map((filePath) => safeReadJsonAsync(filePath, null, options && options.readTimeoutMs)));
    return values
      .filter((value) => value && typeof value === 'object' && typeof value.id === 'string')
      .map((value) => Task.normalizeTask(value, { deviceId: value.updatedBy || this.deviceId }));
  }

  readTask(id) {
    const filePath = this.taskPath(id);
    if (!fs.existsSync(filePath)) return null;
    const record = safeReadJson(filePath, null);
    return record ? Task.normalizeTask(record, { deviceId: record.updatedBy || this.deviceId }) : null;
  }

  saveTask(input) {
    const existing = input && input.id ? this.readTask(input.id) : null;
    const record = existing
      ? Task.updateTask(existing, input, { deviceId: this.deviceId })
      : Task.normalizeTask(input, { deviceId: this.deviceId });
    writeJsonAtomic(this.taskPath(record.id), record);
    return record;
  }

  saveTaskBatch(inputs) {
    return (inputs || []).map((input) => this.saveTask(input));
  }

  deleteTask(id) {
    const task = this.readTask(id);
    if (!task) return null;
    return this.saveTask(Object.assign({}, task, { deletedAt: new Date().toISOString() }));
  }

  restoreTask(id) {
    const task = this.readTask(id);
    if (!task) return null;
    return this.saveTask(Object.assign({}, task, { deletedAt: null }));
  }

  queryDate(dateKey) {
    return Task.sortTasks(this.allRecords()
      .flatMap((task) => Task.occurrencesFor(task, dateKey))
      .filter((task) => task && task.start !== null && task.end !== null));
  }

  queryInbox() {
    return Task.sortTasks(this.allRecords().filter((task) => !task.deletedAt && !task.date));
  }

  updateOccurrence(id, dateKey, patch) {
    const task = this.readTask(id);
    if (!task) throw new Error('Task not found');
    const occurrence = Task.occurrenceFor(task, dateKey);
    if (!occurrence) throw new Error('Task does not occur on this date');
    const nextPatch = Object.assign({}, patch || {});
    if (task.recurrence !== 'none') {
      if (Object.prototype.hasOwnProperty.call(nextPatch, 'done')) {
        const dates = new Set(task.completedDates);
        if (nextPatch.done) dates.add(dateKey); else dates.delete(dateKey);
        nextPatch.completedDates = [...dates].sort();
        delete nextPatch.done;
      }
      if (Object.prototype.hasOwnProperty.call(nextPatch, 'focus')) {
        const dates = new Set(task.focusDates || []);
        if (nextPatch.focus) dates.add(dateKey); else dates.delete(dateKey);
        nextPatch.focusDates = [...dates].sort();
        delete nextPatch.focus;
      }
      if (Object.prototype.hasOwnProperty.call(nextPatch, 'date')) delete nextPatch.date;
    }
    return this.saveTask(Object.assign({}, task, nextPatch));
  }

  moveToInbox(id) {
    const task = this.readTask(id);
    if (!task) return null;
    return this.saveTask(Object.assign({}, task, { date: null, start: null, end: null, focus: false }));
  }

  migrateLegacyDailyFiles() {
    const legacyFiles = listJsonFiles(this.rootDirectory)
      .filter((filePath) => Task.isDateKey(path.basename(filePath, '.json')));
    let migrated = 0;
    legacyFiles.forEach((filePath) => {
      const dateKey = path.basename(filePath, '.json');
      const records = safeReadJson(filePath, []);
      if (!Array.isArray(records)) return;
      records.forEach((legacyTask) => {
        const task = Task.legacyTaskToRecord(legacyTask, dateKey, { deviceId: this.deviceId });
        const destination = this.taskPath(task.id);
        if (!fs.existsSync(destination)) {
          writeJsonAtomic(destination, task);
          migrated += 1;
        }
      });
    });
    return migrated;
  }

  exportDate(dateKey) {
    const markdown = Task.toMarkdown(this.queryDate(dateKey), dateKey);
    const filePath = path.join(this.exportDirectory, `${dateKey}-tasks.md`);
    fs.writeFileSync(filePath, markdown, 'utf8');
    return { filePath, markdown };
  }

  exportWeek(dateKey) {
    const date = Task.dateFromKey(dateKey);
    const weekStart = new Date(date);
    const dayOffset = (date.getDay() + 6) % 7;
    weekStart.setDate(date.getDate() - dayOffset);
    const keys = Array.from({ length: 7 }, (_, index) => Task.formatDateKey(new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + index)));
    const markdown = `# Weekly Tasks — ${keys[0]} to ${keys[6]}\n\n${keys.map((key) => Task.toMarkdown(this.queryDate(key), key)).join('\n')}`;
    const filePath = path.join(this.exportDirectory, `${keys[0]}-week.md`);
    fs.writeFileSync(filePath, markdown, 'utf8');
    return { filePath, markdown, weekStart: keys[0], weekEnd: keys[6] };
  }

  exportRange(startDate, endDate) {
    if (!Task.isDateKey(startDate) || !Task.isDateKey(endDate) || endDate < startDate) throw new Error('Choose a valid date range');
    const keys = [];
    let key = startDate;
    while (key <= endDate) {
      keys.push(key);
      if (keys.length > 366) throw new Error('Date range is limited to one year');
      key = Task.addDays(key, 1);
    }
    const markdown = `# Tasks — ${startDate}${startDate === endDate ? '' : ` to ${endDate}`}\n\n${keys.map((dateKey) => Task.toMarkdown(this.queryDate(dateKey), dateKey)).join('\n')}`;
    const suffix = startDate === endDate ? `${startDate}-tasks.md` : `${startDate}-to-${endDate}-tasks.md`;
    const filePath = path.join(this.exportDirectory, suffix);
    fs.writeFileSync(filePath, markdown, 'utf8');
    return { filePath, markdown, startDate, endDate };
  }

  repairPartiallyScheduledTasks() {
    let repaired = 0;
    this.allRecords().forEach((task) => {
      if (task.deletedAt || !task.date) return;
      const parsed = Task.parseQuickInput(task.title, task.date);
      const missingTime = task.start === null || task.end === null;
      const offTimelineWithTimeInTitle = task.start !== null && task.start < 5 * 60 && parsed.hasExplicitTime && parsed.start >= 5 * 60;
      if (parsed.hasExplicitTime && (missingTime || offTimelineWithTimeInTitle)) {
        this.saveTask(Object.assign({}, task, { date: task.date, start: parsed.start, end: parsed.end, title: parsed.title }));
        repaired += 1;
      } else if (missingTime) {
        this.moveToInbox(task.id);
        repaired += 1;
      }
    });
    return repaired;
  }

  async setSyncFolder(folderPath, bookmark) {
    const resolved = normalizeFolder(folderPath);
    if (!resolved) return this.updateSettings({ syncFolder: null, syncBookmark: null });
    if (resolved === this.rootDirectory || resolved.startsWith(`${this.rootDirectory}${path.sep}`)) {
      throw new Error('Sync folder must be outside the app data folder');
    }
    await Promise.all([
      ensureDirectoryAsync(path.join(resolved, 'tasks')),
      ensureDirectoryAsync(path.join(resolved, 'backups')),
    ]);
    return this.updateSettings({ syncFolder: resolved, syncBookmark: bookmark || null, lastSyncError: null });
  }

  async writeConflictBackup(record, source) {
    if (!record) return;
    const directory = path.join(this.backupDirectory, 'conflicts');
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    await writeJsonAtomicAsync(path.join(directory, `${record.id}-${source}-${stamp}.json`), record);
  }

  async syncNow(reason) {
    const settings = this.getSettings();
    if (!settings.syncFolder) return { ok: false, reason: 'not-configured', message: 'Choose a shared folder first.' };
    if (this.isSyncing) return { ok: false, reason: 'busy', message: 'Sync already running.' };
    this.isSyncing = true;
    try {
      const remoteDirectory = path.join(settings.syncFolder, 'tasks');
      await ensureDirectoryAsync(remoteDirectory);
      const [localList, remoteList] = await Promise.all([
        this.allRecordsAsync(),
        this.allRecordsAsync(remoteDirectory, { readTimeoutMs: 6000 }),
      ]);
      const localRecords = new Map(localList.map((record) => [record.id, record]));
      const remoteRecords = new Map(remoteList.map((record) => [record.id, record]));
      const ids = new Set([...localRecords.keys(), ...remoteRecords.keys()]);
      let pulled = 0;
      let pushed = 0;
      let conflicts = 0;
      for (const id of ids) {
        const local = localRecords.get(id);
        const remote = remoteRecords.get(id);
        const merge = Task.mergeTaskRecords(local, remote);
        if (merge.conflict) {
          conflicts += 1;
          await this.writeConflictBackup(merge.loser, local === merge.loser ? 'local' : 'remote');
        }
        if (!merge.winner) continue;
        const localPath = this.taskPath(id, this.tasksDirectory);
        const remotePath = this.taskPath(id, remoteDirectory);
        if (!local || JSON.stringify(local) !== JSON.stringify(merge.winner)) {
          await writeJsonAtomicAsync(localPath, merge.winner);
          pulled += 1;
        }
        if (!remote || JSON.stringify(remote) !== JSON.stringify(merge.winner)) {
          await writeJsonAtomicAsync(remotePath, merge.winner);
          pushed += 1;
        }
      }
      this.ignoreWatchUntil = Date.now() + 2000;
      const completedAt = new Date().toISOString();
      this.updateSettings({ lastSyncAt: completedAt, lastSyncError: null, lastSyncErrorCode: null });
      return { ok: true, reason: reason || 'manual', pulled, pushed, conflicts, completedAt };
    } catch (error) {
      this.updateSettings({ lastSyncError: error.message, lastSyncErrorCode: error.code || null });
      return { ok: false, reason: 'error', code: error.code || null, message: error.message };
    } finally {
      this.isSyncing = false;
    }
  }

  watchConfiguredFolder() {
    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
    }
    const syncFolder = this.getSettings().syncFolder;
    if (!syncFolder) return;
    const tasksFolder = path.join(syncFolder, 'tasks');
    try {
      this.watcher = fs.watch(tasksFolder, () => {
        if (Date.now() < this.ignoreWatchUntil || this.isSyncing) return;
        clearTimeout(this.watchTimer);
        this.watchTimer = setTimeout(() => {
          this.syncNow('folder-change')
            .then((status) => this.onRemoteChange(status))
            .catch(() => {});
        }, 700);
      });
      this.watcher.on('error', () => {
        if (this.watcher) this.watcher.close();
        this.watcher = null;
      });
    } catch (_) {
      // Folder watching is a convenience only; manual/startup sync remains available.
    }
  }

  getStatus() {
    const settings = this.getSettings();
    return {
      syncFolder: settings.syncFolder,
      lastSyncAt: settings.lastSyncAt,
      lastSyncError: settings.lastSyncError,
      taskCount: this.allRecords().filter((task) => !task.deletedAt).length,
    };
  }

  dispose() {
    if (this.watcher) this.watcher.close();
    clearTimeout(this.watchTimer);
  }
}

module.exports = { TaskStore, safeReadJson, writeJsonAtomic };
