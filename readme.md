<div align="center">

```
██████╗ ███████╗██████╗ ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗ ██████╗
██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝ ██║   ██║██╔══██╗██╔══██╗██╔══██╗
██████╔╝█████╗  ██████╔╝█████╗  ██║  ███╗██║   ██║███████║██████╔╝██║  ██║
██╔═══╝ ██╔══╝  ██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██║██╔══██╗██║  ██║
██║     ███████╗██║  ██║██║     ╚██████╔╝╚██████╔╝██║  ██║██║  ██║██████╔╝
╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝
```

**macOS System Performance Manager — Terminal UI**

![macOS](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)
![Shell](https://img.shields.io/badge/Shell-Bash-informational?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Version](https://img.shields.io/badge/Version-2.2.0-orange?style=flat-square)

</div>

---

PerfGuard is a macOS terminal tool that gives you real control over your system's performance — RAM, CPU, disk, processes, network, and startup items — from a single command.

## Install

One command. No dependencies. Works on macOS 12 Monterey and above.

```bash
curl -fsSL https://raw.githubusercontent.com/chukwunonsoprosper/perfguard/main/install.sh | bash
```

After install, open a new terminal and run:

```bash
perfguard
```

That's it. The interactive menu opens automatically.

---

## What it does

```
╔══════════════════════════════════════════════════════════════╗
║  ◈ RAM   ▕████████████░░░░░░░░░░▏  5.6/8.0GB               ║
║  ◈ CPU   ▕████░░░░░░░░░░░░░░░░░░▏  12%      ◈ BATT  87%    ║
║  ◈ DISK  ▕██████████████░░░░░░░░▏  9.6/113G               ║
╠══════════════════════════════════════════════════════════════╣
║  ┌─ PERFORMANCE ────────────────────────────────────────┐   ║
║  │  1  System overview     │  2  RAM boost (sudo)       │   ║
║  │  3  Cache cleanup       │  4  Deep system sweep      │   ║
║  │  5  Process manager     │  6  Live monitor           │   ║
║  │  7  Full turbo sequence │                            │   ║
║  └────────────────────────────────────────────────────────┘  ║
╚══════════════════════════════════════════════════════════════╝
```

---

## Commands

| Command | What it does |
|---|---|
| `perfguard` | Open interactive menu |
| `perfguard status` | RAM, CPU, disk, battery snapshot |
| `perfguard boost` | Flush inactive memory pages (`sudo`) |
| `perfguard clean` | Clear caches, temp files, build artifacts |
| `perfguard deep-clean` | Extended sweep — browsers, .DS_Store, crash logs |
| `perfguard kill-unused` | Interactive: review and kill unauthorized processes |
| `perfguard monitor` | Live top-like process view |
| `perfguard turbo` | Full optimization sequence (all of the above) |
| `perfguard dns-flush` | Flush macOS DNS resolver cache |
| `perfguard network` | Interface IPs, ping tests, Wi-Fi signal strength |
| `perfguard startup-scan` | Audit login items and launch agents |
| `perfguard disk-usage` | Visual per-folder disk breakdown |
| `perfguard swap-info` | Swap usage and virtual memory stats |
| `perfguard pressure-watch` | Live memory pressure alert monitor |
| `perfguard schedule` | Set up automatic cron-based cleanup |
| `perfguard whitelist` | View and manage approved process list |
| `perfguard log` | View activity log |
| `perfguard help` | All commands |

---

## How each feature works

**`clean`** removes files from:
- `~/Library/Caches` — app cache files older than 1 day
- `~/Library/Logs` — log files older than 7 days
- `$TMPDIR` — temp files from the current day
- `~/Library/Logs/DiagnosticReports` — crash reports older than 14 days
- `~/Library/Developer/Xcode/DerivedData` — when over 200MB
- npm, pip, and Homebrew package caches

**`deep-clean`** adds:
- Safari, Chrome, and Firefox website caches
- `.DS_Store` metadata files across your home directory
- iOS device backup size reporting

**`boost`** runs `sudo purge` to reclaim inactive memory pages — the same pages macOS would eventually recover on its own, just faster.

**`kill-unused`** scans the top 50 most memory-hungry processes, flags any that aren't on the approved whitelist, and asks before killing each one. Nothing is killed silently.

**`turbo`** runs `kill-unused → deep-clean → dns-flush → boost` in sequence.

**`pressure-watch`** polls memory pressure every 5 seconds and writes a warning to the log when it exceeds 80%.

---

## Customizing the whitelist

PerfGuard ships with an extensive whitelist of known macOS system processes and common apps. To add your own:

```bash
echo 'MyApp' >> ~/.perfguard/whitelist
```

View the current whitelist:

```bash
perfguard whitelist
```

---

## Files

| Path | Purpose |
|---|---|
| `/usr/local/bin/perfguard` | The installed executable |
| `~/.perfguard/whitelist` | Your custom process whitelist |
| `~/.perfguard/perfguard.log` | Activity and alert log |

---

## Update

Re-run the installer to update to the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/chukwunonsoprosper/perfguard/main/install.sh | bash
```

Or update just the script:

```bash
curl -fsSL https://raw.githubusercontent.com/chukwunonsoprosper/perfguard/main/perfguard.sh \
  | sudo tee /usr/local/bin/perfguard > /dev/null
```

---

## Uninstall

```bash
sudo rm /usr/local/bin/perfguard
rm -rf ~/.perfguard
```

---

## Requirements

- macOS 12 Monterey or later
- Bash 3.2+ (pre-installed on all Macs)
- `sudo` access for `boost`, `dns-flush`, and the installer

No Homebrew. No Python. No dependencies.

---

## License

MIT — do whatever you want with it.