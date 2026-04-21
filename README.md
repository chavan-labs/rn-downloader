# 🚀 rn-downloader

[![npm version](https://img.shields.io/npm/v/rn-downloader.svg?style=flat-square)](https://www.npmjs.com/package/rn-downloader)
[![npm downloads](https://img.shields.io/npm/dm/rn-downloader.svg?style=flat-square)](https://www.npmjs.com/package/rn-downloader)
[![license](https://img.shields.io/npm/l/rn-downloader.svg?style=flat-square)](https://github.com/chavanRk/react-native-downloader/blob/main/LICENSE)
[![TypeScript](https://img.shields.io/badge/TypeScript-Ready-blue.svg?style=flat-square)](https://www.typescriptlang.org/)
[![platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20Android-lightgrey.svg?style=flat-square)](https://github.com/chavanRk/react-native-downloader)

The easiest way to download files in React Native — with background support, pause/resume, upload, and cache management built-in.

> 100% pure native code (Kotlin + Swift). Zero third-party dependencies.

**Keywords:** react native download, react native file download, react native background download, react native download manager, react native file upload, react native download progress, react native pause resume download, react native cache manager, react native turbo module, expo download, iOS URLSession, Android DownloadManager, react native checksum validation

⭐ **Star this repo if you found it useful** — it helps others discover the project!

## 🤔 Why this project?

Most React Native file download solutions have one or more of these problems:

- **Complexity** — require configuring native modules, background tasks, and notification channels separately
- **Dependencies** — rely on heavy third-party libraries that bloat your app size
- **Limited features** — lack pause/resume, checksum validation, or proper background support
- **Poor DX** — complicated APIs that require managing multiple IDs, listeners, and cleanup logic

**rn-downloader** was built to solve these issues. It provides a simple, unified API while leveraging platform-native download managers (URLSession on iOS, DownloadManager on Android) for reliable, battery-efficient downloads. Everything works out of the box — background downloads, progress tracking, pause/resume — without wrestling with native configuration.

## ✨ Features

- 📥 **Download with progress** — clean `0 → 100` progress natively, no UI freezing
- 🌙 **Background downloads** — survive app suspension (iOS background URLSession + Android DownloadManager)
- ⏸ **Pause & Resume** — resume mid-download using HTTP Range requests
- ❌ **Cancel** — cancel any active download, partial files are cleaned up automatically
- 🔄 **Re-attach** — reconnect to background downloads after app restart
- 🔑 **Custom Headers** — support for Authorization tokens and custom metadata
- 📂 **Custom Destinations** — save to `downloads`, `cache`, or `documents` folders
- 📤 **Multipart Upload** — simple, native file uploading
- 🛡️ **Checksum Validation** — verify file integrity (MD5, SHA1, SHA256) after download
- 📱 **Expo Support** — includes a config plugin for zero-config integration
- ⚡ **TurboModules** — built on the React Native New Architecture
- 📦 **File management** — list, delete individual files, or clear all downloads

---

## 💻 Installation

```sh
npm install rn-downloader
```

---

## 📖 API

### `download(options)`

```javascript
import { download } from 'rn-downloader';

const result = await download({
  url: 'https://example.com/file.pdf',
  fileName: 'my_file.pdf',
  headers: { Authorization: 'Bearer <token>' },
  destination: 'documents', // 'downloads' | 'cache' | 'documents'
  checksum: {
    hash: 'd41d8cd98f00b204e9800998ecf8427e',
    algorithm: 'md5',
  },
  onProgress: (p) => console.log(`${p}%`),
});
```

---

### `upload(options)`

```javascript
import { upload } from 'rn-downloader';

const result = await upload({
  url: 'https://example.com/api/upload',
  filePath: '/path/to/my_image.jpg',
  fieldName: 'avatar', // default: 'file'
  parameters: {
    userId: '123',
  },
  headers: { 'X-Custom-Header': 'value' },
  onProgress: (p) => console.log(`Uploading: ${p}%`),
});

if (result.success) {
  console.log('Response:', result.data);
}
```

---

### Pause / Resume / Cancel

```javascript
import { pauseDownload, resumeDownload, cancelDownload } from 'rn-downloader';

await pauseDownload(downloadId);
await resumeDownload(downloadId);
await cancelDownload(downloadId);
```

---

### Cache Management

```javascript
import { getCachedFiles, deleteFile, clearCache } from 'rn-downloader';

// List all files in the cache/documents folders
const { files } = await getCachedFiles();

// Delete a specific file
await deleteFile('/path/to/file.pdf');

// Clear all managed files
await clearCache();
```

---

## 📐 Type Reference

| Type              | Fields                                                                                                          |
| ----------------- | --------------------------------------------------------------------------------------------------------------- |
| `DownloadOptions` | `url`, `fileName?`, `background?`, `headers?`, `destination?`, `notificationTitle?`, `checksum?`, `onProgress?` |
| `UploadOptions`   | `url`, `filePath`, `fieldName?`, `headers?`, `parameters?`, `onProgress?`                                       |
| `DownloadResult`  | `success`, `filePath?`, `downloadId?`, `error?`                                                                 |
| `UploadResult`    | `success`, `status?`, `data?`, `error?`                                                                         |
| `Checksum`        | `hash`, `algorithm: 'md5' \| 'sha1' \| 'sha256'`                                                                |

---

## � Articles & Resources

- [**Why Downloading Files in React Native is Still Broken in 2026 (and How to Fix It)**](https://medium.com/@chavanrohit413/why-downloading-files-in-react-native-is-still-broken-in-2026-and-how-to-fix-it-16ca47a6bd8b) — Deep dive into the problems with existing solutions and how rn-downloader solves them

---

## �🔗 Links

- [GitHub](https://github.com/chavanRk/react-native-downloader)
- [npm](https://www.npmjs.com/package/rn-downloader)

---

_Made natively for the community 🤝 by Rohit Chavan_
