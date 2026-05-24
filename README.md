# ⚡ PerfGuard — macOS Menu Bar Performance Manager

A native Swift menu bar app that keeps your MacBook fast by managing RAM, killing background processes, and auto-cleaning caches.

---

## Features

| Feature | Description |
|---|---|
| 📊 RAM Dashboard | Live memory pressure bar + used/total display |
| ⚡ RAM Boost | Triggers macOS to flush inactive/purgeable memory |
| 🔴 Kill Unused | Terminates unauthorized background apps using >50MB RAM |
| 🧹 Cache Cleanup | Deletes user caches + temp files on demand |
| 🕐 Auto-Cleanup | Runs every 30 minutes automatically |
| ✅ App Whitelist | Approve/block any running process |
| 📋 Process List | Real-time list with CPU + memory usage |
| 📝 Activity Log | Tracks every cleanup/kill action |

---

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later
- Apple Silicon or Intel Mac

---

## Setup (5 minutes)

### Step 1 — Open in Xcode
```bash
open PerfGuard.xcodeproj
```

### Step 2 — Set your Team
1. Click **PerfGuard** in the project navigator
2. Select the **PerfGuard** target
3. Under **Signing & Capabilities** → set your Apple ID as the Team

### Step 3 — Build & Run
Press **⌘R** — the app will appear as a ⚡🛡 icon in your menu bar.

---

## How to Use

### Dashboard Tab
- See live RAM usage and memory pressure
- **RAM Boost** → flushes inactive memory pages
- **Kill Unused** → terminates heavy unauthorized background apps
- **Clean Cache** → clears user caches and temp files

### Processes Tab
- See every running process with memory + CPU usage
- Green dot = approved app, Red dot = unauthorized
- Click **Block** to mark an app as unauthorized
- Click **✕** to immediately kill a process

### Cleanup Tab
- Run full cleanup manually anytime
- View the activity log of all past actions
- Auto-cleanup runs silently every 30 minutes

---

## Customizing the Whitelist

Edit `approvedApps` in `PerformanceManager.swift` to add your own apps:

```swift
@Published var approvedApps: Set<String> = [
    "Finder", "Safari", "Chrome", "Slack", "Zoom",
    "YourAppName",  // ← add yours here
    ...
]
```

You can also approve/block apps live from the **Processes** tab.

---

## Tips for 8GB MacBooks

- Run **RAM Boost** before launching heavy apps (Xcode, Chrome, etc.)
- Use **Kill Unused** when things feel sluggish
- Keep the approved list tight — fewer background apps = more RAM for you
- The auto-cleanup every 30 min handles cache buildup automatically

---

## Permissions Note

Some operations (killing system processes) may require disabling SIP or running with elevated privileges. The app gracefully skips processes it can't kill.
