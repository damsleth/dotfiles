const { app, BrowserWindow } = require('electron');
const path = require('path');

function createWindow() {
  const mainWindow = new BrowserWindow({
    width: 100,
    height: 100,
    transparent: true,
    frame: false,
    alwaysOnTop: true,
    show: false,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  mainWindow.loadFile('index.html');
}

app.whenReady().then(createWindow);

// On Windows, if there are no open windows, don't quit.
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
