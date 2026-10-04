'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const Task = require('../src/task-model');
const { TaskStore, writeJsonAtomic } = require('../src/task-store');

test('quick input understands Chinese relative date, time, and duration', () => {
  const parsed = Task.parseQuickInput('明天 9:30 跑步 45m', '2026-08-20', new Date('2026-08-20T08:00:00'));
  assert.deepEqual(parsed, { date: '2026-08-21', start: 570, end: 615, title: '跑步', duration: 45, hasExplicitTime: true });
});

test('quick input handles full-width punctuation and tightly written Chinese time', () => {
  const parsed = Task.parseQuickInput('明天9：30跑步45分钟', '2026-08-22', new Date('2026-08-22T08:00:00'));
  assert.deepEqual(parsed, { date: '2026-08-23', start: 570, end: 615, title: '跑步', duration: 45, hasExplicitTime: true });
});

test('recurring weekday tasks yield an occurrence only on weekdays', () => {
  const task = Task.normalizeTask({ id: 'morning', date: '2026-08-17', start: 480, end: 510, title: '阅读', recurrence: 'weekdays' });
  assert.equal(Task.occurrenceFor(task, '2026-08-21').done, false);
  assert.equal(Task.occurrenceFor(task, '2026-08-22'), null);
  task.completedDates = ['2026-08-21'];
  assert.equal(Task.occurrenceFor(task, '2026-08-21').done, true);
});

test('repeating task focus is scoped to an occurrence date', () => {
  const task = Task.normalizeTask({ id: 'focus-repeat', date: '2026-08-17', start: 480, end: 510, title: 'Stretch', recurrence: 'daily', focusDates: ['2026-08-20'] });
  assert.equal(Task.occurrenceFor(task, '2026-08-20').focus, true);
  assert.equal(Task.occurrenceFor(task, '2026-08-21').focus, false);
});

test('an overnight task renders one linked segment on each day', () => {
  const task = Task.normalizeTask({ id: 'overnight', date: '2026-08-21', start: 23 * 60, end: 60, title: 'Night train' });
  assert.equal(task.end, 25 * 60);
  const firstDay = Task.occurrencesFor(task, '2026-08-21');
  const nextDay = Task.occurrencesFor(task, '2026-08-22');
  assert.deepEqual([firstDay[0].start, firstDay[0].end, firstDay[0].spansNextDay], [1380, 1440, true]);
  assert.deepEqual([nextDay[0].start, nextDay[0].end, nextDay[0].isContinuation], [0, 60, true]);
});

test('date keys reject rolled-over calendar dates', () => {
  assert.equal(Task.isDateKey('2026-02-29'), false);
  assert.equal(Task.isDateKey('2028-02-29'), true);
});

test('newer task record wins a sync collision deterministically', () => {
  const local = Task.normalizeTask({ id: 'same', title: '旧标题', updatedAt: '2026-08-20T01:00:00.000Z', updatedBy: 'mac' });
  const remote = Task.normalizeTask({ id: 'same', title: '新标题', updatedAt: '2026-08-20T02:00:00.000Z', updatedBy: 'iphone' });
  const result = Task.mergeTaskRecords(local, remote);
  assert.equal(result.winner.title, '新标题');
  assert.equal(result.loser.title, '旧标题');
  assert.equal(result.conflict, true);
});

test('task color defaults to category and supports a stable custom token', () => {
  const automatic = Task.normalizeTask({ id: 'auto-color', title: 'Walk', category: 'health' });
  assert.equal(automatic.colorMode, 'category');
  assert.equal(automatic.colorToken, null);
  assert.equal(Task.resolveTaskColor(automatic).id, 'mint');

  const custom = Task.normalizeTask({ id: 'custom-color', title: 'Walk', category: 'health', colorMode: 'custom', colorToken: 'violet' });
  assert.equal(custom.colorMode, 'custom');
  assert.equal(Task.resolveTaskColor(custom).id, 'violet');
});

test('moving a one-off overnight task to tomorrow preserves its time range', () => {
  const task = Task.normalizeTask({ id: 'move-night', title: 'Night train', date: '2026-08-21', start: 23 * 60, end: 60 });
  const moved = Task.updateTask(task, { date: Task.addDays(task.date, 1), start: task.start, end: task.end }, { now: '2026-08-21T12:00:00.000Z', deviceId: 'mac' });
  assert.equal(moved.date, '2026-08-22');
  assert.equal(moved.start, 1380);
  assert.equal(moved.end, 1500);
  assert.equal(Task.occurrencesFor(moved, '2026-08-23')[0].end, 60);
});

test('store migrates legacy day files, exports, and pulls shared records', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'daily-widget-test-'));
  try {
    const root = path.join(temp, 'data');
    const exportsDir = path.join(temp, 'exports');
    const cloud = path.join(temp, 'cloud');
    fs.mkdirSync(root, { recursive: true });
    writeJsonAtomic(path.join(root, '2026-08-20.json'), [{ id: 'legacy-one', start: 540, end: 600, text: '旧任务', color: '#d3f2dd', done: false }]);
    const store = new TaskStore({ rootDirectory: root, exportDirectory: exportsDir, deviceId: 'mac-test' });
    store.init();
    const day = store.queryDate('2026-08-20');
    assert.equal(day.length, 1);
    assert.equal(day[0].title, '旧任务');
    assert.equal(day[0].category, 'health');
    const output = store.exportDate('2026-08-20');
    assert.match(output.markdown, /旧任务/);
    assert.equal(fs.existsSync(output.filePath), true);
    await store.setSyncFolder(cloud);
    assert.equal((await store.syncNow()).ok, true);
    const secondRoot = path.join(temp, 'second-data');
    const second = new TaskStore({ rootDirectory: secondRoot, exportDirectory: path.join(temp, 'second-exports'), deviceId: 'phone-test' });
    second.init(); await second.setSyncFolder(cloud);
    const sync = await second.syncNow();
    assert.equal(sync.ok, true);
    assert.equal(second.queryDate('2026-08-20')[0].title, '旧任务');
    store.dispose(); second.dispose();
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
});

test('store keeps a conflict backup and synchronizes a tombstone', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'daily-widget-conflict-'));
  let local;
  let remote;
  try {
    const cloud = path.join(temp, 'cloud');
    const localRoot = path.join(temp, 'local');
    const remoteRoot = path.join(temp, 'remote');
    local = new TaskStore({ rootDirectory: localRoot, exportDirectory: path.join(temp, 'local-exports'), deviceId: 'mac' });
    remote = new TaskStore({ rootDirectory: remoteRoot, exportDirectory: path.join(temp, 'remote-exports'), deviceId: 'phone' });
    local.init(); remote.init();
    const initial = local.saveTask({ id: 'conflicted', date: '2026-08-20', start: 600, end: 630, title: 'Original' });
    await local.setSyncFolder(cloud); await local.syncNow();
    await remote.setSyncFolder(cloud); await remote.syncNow();
    writeJsonAtomic(local.taskPath('conflicted'), Object.assign({}, initial, { title: 'Mac edit', updatedAt: '2030-08-20T01:00:00.000Z' }));
    writeJsonAtomic(remote.taskPath('conflicted'), Object.assign({}, remote.readTask('conflicted'), { title: 'Phone edit', updatedAt: '2030-08-20T02:00:00.000Z' }));
    await remote.syncNow();
    const result = await local.syncNow();
    assert.equal(result.conflicts, 1);
    assert.equal(local.readTask('conflicted').title, 'Phone edit');
    assert.equal(fs.readdirSync(path.join(localRoot, 'backups', 'conflicts')).length, 1);
    const tombstone = remote.deleteTask('conflicted');
    writeJsonAtomic(remote.taskPath('conflicted'), Object.assign({}, tombstone, { deletedAt: '2030-08-20T03:00:00.000Z', updatedAt: '2030-08-20T03:00:00.000Z' }));
    await remote.syncNow(); await local.syncNow();
    assert.notEqual(local.readTask('conflicted').deletedAt, null);
  } finally {
    local?.dispose(); remote?.dispose();
    fs.rmSync(temp, { recursive: true, force: true });
  }
});

test('store repairs an old quick-add record that was incorrectly placed at midnight', () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'daily-widget-repair-'));
  try {
    const root = path.join(temp, 'data');
    const store = new TaskStore({ rootDirectory: root, exportDirectory: path.join(temp, 'exports'), deviceId: 'mac' });
    store.init();
    writeJsonAtomic(store.taskPath('bad-quick-add'), Task.normalizeTask({ id: 'bad-quick-add', date: '2026-08-23', start: 0, end: 30, title: '9：30 跑步45分钟' }, { deviceId: 'mac' }));
    assert.equal(store.repairPartiallyScheduledTasks(), 1);
    const repaired = store.readTask('bad-quick-add');
    assert.equal(repaired.start, 570);
    assert.equal(repaired.end, 615);
    assert.equal(repaired.title, '跑步');
    const weekly = store.exportWeek('2026-08-23');
    assert.match(weekly.markdown, /2026-08-23/);
    assert.match(weekly.markdown, /跑步/);
    const range = store.exportRange('2026-08-22', '2026-08-23');
    assert.match(range.markdown, /2026-08-22/);
    assert.match(range.markdown, /2026-08-23/);
    store.dispose();
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
});
