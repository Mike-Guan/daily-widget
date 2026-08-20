const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('routineStore', {
  load: (dateKey) => ipcRenderer.invoke('tasks:load', dateKey),
  save: (dateKey, tasks) => ipcRenderer.invoke('tasks:save', dateKey, tasks),
  export: (dateKey, markdown) => ipcRenderer.invoke('tasks:export', dateKey, markdown),
});
