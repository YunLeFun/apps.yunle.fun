// Electron's sandboxed preload exposes process but cannot import node:process.
/* eslint node/prefer-global/process: off */
import { contextBridge, ipcRenderer } from 'electron'
import { GUEST_ENVIRONMENT } from '../shared/desktop'

if (process.isMainFrame) {
  contextBridge.exposeInMainWorld('yunleHost', {
    version: 1,
    getEnvironment: () => ipcRenderer.invoke(GUEST_ENVIRONMENT),
  })
}
