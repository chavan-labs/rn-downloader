# 🚀 react-native-downloader

The easiest way to download files in React Native — with background support, pause/resume, and cache management built-in.

> 100% pure native code (Kotlin + Swift). Zero third-party dependencies.

## ✨ Features

- 📥 **Download with progress** — clean `0 → 100` progress natively, no UI freezing
- 🌙 **Background downloads** — survive app suspension (iOS background URLSession + Android DownloadManager)
- ⏸ **Pause & Resume** — resume mid-download using HTTP Range requests
- ❌ **Cancel** — cancel any active download, partial files are cleaned up automatically
- 📦 **Cache management** — list, delete individual files, or clear the entire cache
- 📂 **Smart file naming** — auto-detects filename from URL if not provided
- 🛠 **Structured errors** — `{ success: false, error: '...' }` instead of silent failures
- ⚡ **Lightweight** — zero dependencies

---

## 💻 Installation

```sh
npm install rn-downloader
# or
yarn add rn-downloader
```

> iOS: run `pod install` in your `ios/` directory after installing.

---

## 📖 API

### `download(options)`

```javascript
import { download, onDownloadComplete, onDownloadError } from 'rn-downloader';

// Foreground download
const result = await download({
  url: 'https://example.com/file.pdf',
  fileName: 'my_file.pdf',
  onProgress: (percent) => console.log(`Progress: ${percent}%`),
});
if (result.success) {
  console.log('Saved to:', result.filePath);
  console.log('Download ID:', result.downloadId);
}

// Background download (resolves immediately with downloadId)
const { downloadId } = await download({
  url: 'https://example.com/video.mp4',
  background: true,
});
const unsub = onDownloadComplete((r) => {
  console.log('Done:', r.filePath);
  unsub();
});
```

---

### Pause / Resume / Cancel

```javascript
import {
  download,
  pauseDownload,
  resumeDownload,
  cancelDownload,
} from 'rn-downloader';

const { downloadId } = await download({
  url: 'https://example.com/file.zip',
  onProgress: (p) => console.log(`${p}%`),
});

await pauseDownload(downloadId); // pause
await resumeDownload(downloadId); // resume from where it left off (HTTP Range)
await cancelDownload(downloadId); // cancel + delete partial file
```

---

### Cache Management

```javascript
import { getCachedFiles, deleteFile, clearCache } from 'rn-downloader';

const { files } = await getCachedFiles();
files?.forEach((f) => console.log(f.fileName, f.size));

await deleteFile('/path/to/file.pdf');
await clearCache();
```

---

## 📐 Type Reference

| Type              | Fields                                                    |
| ----------------- | --------------------------------------------------------- |
| `DownloadOptions` | `url`, `fileName?`, `background?`, `onProgress?`          |
| `DownloadResult`  | `success`, `filePath?`, `downloadId?`, `error?`           |
| `ActionResult`    | `success`, `error?`                                       |
| `CachedFile`      | `fileName`, `filePath`, `size` (bytes), `modifiedAt` (ms) |
| `CacheResult`     | `success`, `files?`, `error?`                             |

---

## 🔗 Links

- [GitHub](https://github.com/chavanRk/react-native-downloader)
- [npm](https://www.npmjs.com/package/rn-downloader)

---

_Made natively for the community 🤝_
