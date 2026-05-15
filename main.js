const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const { startServer } = require('./server-embed');

let mainWindow;
let serverInstance;
const PORT = 3847;

// Single instance lock
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

app.on('second-instance', () => {
  if (mainWindow) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  }
});

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 900,
    minHeight: 600,
    title: 'License Checker',
    icon: path.join(__dirname, 'assets', 'icon.png'),
    backgroundColor: '#0a0a0f',
    show: false,
    autoHideMenuBar: true,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  // Remove default menu
  mainWindow.setMenu(null);

  // Start embedded server then load
  serverInstance = startServer(PORT, getScanScriptPath());
  mainWindow.loadURL(`http://localhost:${PORT}`);

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function getScanScriptPath() {
  // In production (packaged), the scan.ps1 is in extraResources
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'scan.ps1');
  }
  return path.join(__dirname, 'scan.ps1');
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (serverInstance) {
    serverInstance.close();
  }
  app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});
