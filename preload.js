const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dailyWidget', {
  init: () => ipcRenderer.invoke('app:init'),
  getDay: (dateKey) => ipcRenderer.invoke('tasks:day', dateKey),
  getInbox: () => ipcRenderer.invoke('tasks:inbox'),
  saveTask: (task) => ipcRenderer.invoke('tasks:save', task),
  updateOccurrence: (id, dateKey, patch) => ipcRenderer.invoke('tasks:update-occurrence', id, dateKey, patch),
  deleteTask: (id) => ipcRenderer.invoke('tasks:delete', id),
  moveToInbox: (id) => ipcRenderer.invoke('tasks:inbox-move', id),
  exportDay: (dateKey) => ipcRenderer.invoke('tasks:export', dateKey),
  exportWeek: (dateKey) => ipcRenderer.invoke('tasks:export-week', dateKey),
  exportRange: (startDate, endDate) => ipcRenderer.invoke('tasks:export-range', startDate, endDate),
  getSettings: () => ipcRenderer.invoke('settings:get'),
  updateSettings: (patch) => ipcRenderer.invoke('settings:update', patch),
  getSyncStatus: () => ipcRenderer.invoke('sync:status'),
  syncNow: () => ipcRenderer.invoke('sync:now'),
  chooseSyncFolder: () => ipcRenderer.invoke('sync:choose-folder'),
  openLink: (url) => ipcRenderer.invoke('links:open', url),
  onSyncChanged: (callback) => ipcRenderer.on('sync:changed', () => callback()),
});
