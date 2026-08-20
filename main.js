const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');

const DATA_DIR = path.join(__dirname, 'data');
const EXPORTS_DIR = path.join(__dirname, 'exports');

if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(EXPORTS_DIR)) fs.mkdirSync(EXPORTS_DIR, { recursive: true });

function isValidDateKey(key) {
  return /^\d{4}-\d{2}-\d{2}$/.test(key);
}

function dataFilePath(dateKey) {
  if (!isValidDateKey(dateKey)) throw new Error('Invalid date key: ' + dateKey);
  return path.join(DATA_DIR, dateKey + '.json');
}

ipcMain.handle('tasks:load', (event, dateKey) => {
  const file = dataFilePath(dateKey);
  if (!fs.existsSync(file)) return [];
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    return [];
  }
});

ipcMain.handle('tasks:save', (event, dateKey, tasks) => {
  const file = dataFilePath(dateKey);
  fs.writeFileSync(file, JSON.stringify(tasks, null, 2), 'utf8');
  return true;
});

ipcMain.handle('tasks:export', (event, dateKey, markdown) => {
  const file = path.join(EXPORTS_DIR, dateKey + '-tasks.md');
  fs.writeFileSync(file, markdown, 'utf8');
  return file;
});

function createWindow() {
  const win = new BrowserWindow({
    width: 480,
    height: 760,
    title: 'Daily Routine',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.setMenuBarVisibility(false);
  win.loadFile('index.html');
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  app.quit();
});
