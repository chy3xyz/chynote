import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "path";

export default defineConfig({
  base: "./",
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      "@tauri-apps/api": path.resolve(__dirname, "./src/@tauri-apps/api"),
      "@tauri-apps/api/core": path.resolve(__dirname, "./src/@tauri-apps/api/core"),
      "@tauri-apps/api/event": path.resolve(__dirname, "./src/@tauri-apps/api/event"),
      "@tauri-apps/api/window": path.resolve(__dirname, "./src/@tauri-apps/api/window"),
      "@tauri-apps/api/webview": path.resolve(__dirname, "./src/@tauri-apps/api/webview"),
      "@tauri-apps/plugin-opener": path.resolve(__dirname, "./src/@tauri-apps/plugin-opener"),
      "@tauri-apps/plugin-dialog": path.resolve(__dirname, "./src/@tauri-apps/plugin-dialog"),
      "@tauri-apps/plugin-process": path.resolve(__dirname, "./src/@tauri-apps/plugin-process"),
      "@tauri-apps/plugin-updater": path.resolve(__dirname, "./src/@tauri-apps/plugin-updater"),
      "@tauri-apps/api/dpi": path.resolve(__dirname, "./src/@tauri-apps/api/dpi"),
      "@tauri-apps/api/webviewWindow": path.resolve(__dirname, "./src/@tauri-apps/api/webviewWindow"),
    },
  },
});
