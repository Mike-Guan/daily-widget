const { app, BrowserWindow, dialog, ipcMain, shell } = require('electron');
const path = require('path');
const { TaskStore } = require('./src/task-store');

let store;
let stopAccessingSyncFolder;

function activateSyncBookmark(settings) {
  if (!process.mas || !settings || !settings.syncBookmark) return;
  if (stopAccessingSyncFolder) stopAccessingSyncFolder();
  stopAccessingSyncFolder = app.startAccessingSecurityScopedResource(settings.syncBookmark);
}

function storageDirectories() {
  if (!app.isPackaged) {
    return { data: path.join(__dirname, 'data'), exports: path.join(__dirname, 'exports') };
  }
  const root = path.join(app.getPath('userData'), 'Daily Widget');
  return { data: path.join(root, 'data'), exports: path.join(root, 'exports') };
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1180,
    height: 820,
    minWidth: 760,
    minHeight: 620,
    title: 'Daily Widget',
    backgroundColor: '#f6f7fb',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  win.setMenuBarVisibility(false);
  win.loadFile('index.html');
}

function registerIpc() {
  ipcMain.handle('app:init', () => store.init());
  ipcMain.handle('tasks:day', (_, dateKey) => store.queryDate(dateKey));
  ipcMain.handle('tasks:inbox', () => store.queryInbox());
  ipcMain.handle('tasks:save', (_, task) => store.saveTask(task));
  ipcMain.handle('tasks:update-occurrence', (_, id, dateKey, patch) => store.updateOccurrence(id, dateKey, patch));
  ipcMain.handle('tasks:delete', (_, id) => store.deleteTask(id));
  ipcMain.handle('tasks:inbox-move', (_, id) => store.moveToInbox(id));
  ipcMain.handle('tasks:export', (_, dateKey) => store.exportDate(dateKey));
  ipcMain.handle('tasks:export-week', (_, dateKey) => store.exportWeek(dateKey));
  ipcMain.handle('tasks:export-range', (_, startDate, endDate) => store.exportRange(startDate, endDate));
  ipcMain.handle('settings:get', () => store.getSettings());
  ipcMain.handle('settings:update', (_, patch) => store.updateSettings(patch));
  ipcMain.handle('sync:status', () => store.getStatus());
  ipcMain.handle('sync:now', () => store.syncNow('manual'));
  ipcMain.handle('sync:choose-folder', async (event) => {
    const result = await dialog.showOpenDialog(BrowserWindow.fromWebContents(event.sender), {
      title: 'Choose your shared Daily Widget folder',
      buttonLabel: 'Use this folder',
      properties: ['openDirectory', 'createDirectory'],
      securityScopedBookmarks: true,
    });
    if (result.canceled || !result.filePaths[0]) return { canceled: true };
    const settings = await store.setSyncFolder(result.filePaths[0], result.bookmarks && result.bookmarks[0]);
    activateSyncBookmark(settings);
    return { canceled: false, settings };
  });
  ipcMain.handle('links:open', async (_, rawUrl) => {
    let url;
    try { url = new URL(rawUrl); } catch (_) { return false; }
    if (!['http:', 'https:'].includes(url.protocol)) return false;
    await shell.openExternal(url.href);
    return true;
  });
}

app.whenReady().then(() => {
  const directories = storageDirectories();
  store = new TaskStore({
    rootDirectory: directories.data,
    exportDirectory: directories.exports,
    onRemoteChange: () => BrowserWindow.getAllWindows().forEach((win) => win.webContents.send('sync:changed')),
  });
  registerIpc();
  store.init();
  const settings = store.getSettings();
  activateSyncBookmark(settings);
  createWindow();
  if (settings.syncFolder) void store.syncNow('startup');
});

app.on('window-all-closed', () => app.quit());
app.on('before-quit', () => { if (stopAccessingSyncFolder) stopAccessingSyncFolder(); if (store) store.dispose(); });
