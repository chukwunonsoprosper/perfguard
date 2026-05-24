#!/usr/bin/env bash
# ================================================================
#  PerfGuard v2.1 — macOS System Performance Manager
#  Install: curl -fsSL https://raw.githubusercontent.com/chukwunonsoprosper/perfguard/main/install.sh | bash
#  Usage:   perfguard [command]
# ================================================================

# NOTE: intentionally NO set -euo pipefail — macOS subcommands
# frequently return non-zero; we handle errors explicitly instead.

PERFGUARD_VERSION="2.1.0"
LOG_FILE="$HOME/.perfguard/perfguard.log"
WHITELIST_FILE="$HOME/.perfguard/whitelist"

# ── ANSI ────────────────────────────────────────────────────────
R="\033[0m"
B="\033[1m"
D="\033[2m"

C0="\033[38;5;255m"
C1="\033[38;5;39m"
C2="\033[38;5;82m"
C3="\033[38;5;220m"
C4="\033[38;5;196m"
C5="\033[38;5;135m"
C6="\033[38;5;208m"
C7="\033[38;5;51m"

# ── Bootstrap ───────────────────────────────────────────────────
bootstrap() {
  mkdir -p "$HOME/.perfguard"
  [ ! -f "$LOG_FILE" ]      && touch "$LOG_FILE"
  [ ! -f "$WHITELIST_FILE" ] && touch "$WHITELIST_FILE"
}

# ── Logging ─────────────────────────────────────────────────────
log() {
  local msg="$1"
  local level="${2:-INFO}"
  printf "[%s] [%-5s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$LOG_FILE"
}

# ── Approved process whitelist ───────────────────────────────────
APPROVED_APPS=(
  "Finder" "Safari" "Google Chrome" "Firefox" "Arc" "Brave Browser"
  "Code" "Cursor" "Terminal" "iTerm2" "Warp" "Alacritty"
  "Xcode" "Simulator" "Instruments"
  "Slack" "Zoom" "Teams" "Discord" "Telegram" "WhatsApp"
  "Mail" "Messages" "FaceTime" "Calendar" "Reminders" "Notes"
  "Music" "Spotify" "Photos" "Preview"
  "System Preferences" "System Settings" "System Information"
  "Activity Monitor" "Console" "Disk Utility" "Keychain Access"
  "Dock" "WindowServer" "loginwindow" "Spotlight"
  "ControlCenter" "controlcenter" "NotificationCenter"
  "coreaudiod" "coremediaiod" "useractivityd" "distnoted"
  "launchd" "kernel_task" "mds" "mds_stores" "mdworker"
  "bash" "zsh" "sh" "fish" "python3" "ruby" "node"
  "ssh" "git" "vim" "nvim" "emacs" "nano"
  "perfguard" "TextEdit"
  "UserEventAgent" "cfprefsd" "lsd" "nsurlsessiond"
  "trustd" "secinitd" "authd" "opendirectoryd"
  "networkd_privileged" "configd" "powerd" "thermalmonitord"
)

load_whitelist() {
  if [ -f "$WHITELIST_FILE" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && [ "${line:0:1}" != "#" ] && APPROVED_APPS+=("$line")
    done < "$WHITELIST_FILE"
  fi
}

is_approved() {
  local pname="$1"
  local app
  for app in "${APPROVED_APPS[@]}"; do
    case "$pname" in
      *"$app"*) echo "true"; return ;;
    esac
    case "$app" in
      *"$pname"*) echo "true"; return ;;
    esac
  done
  echo "false"
}

# ── System Info ─────────────────────────────────────────────────
get_ram_stats() {
  local total_bytes page_size free inactive
  total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 8589934592)
  page_size=$(vm_stat 2>/dev/null | awk '/page size/ {print $8}')
  [ -z "$page_size" ] && page_size=16384
  free=$(vm_stat 2>/dev/null | awk '/^Pages free:/ {gsub(/\./,"",$3); print $3+0}')
  inactive=$(vm_stat 2>/dev/null | awk '/^Pages inactive:/ {gsub(/\./,"",$3); print $3+0}')
  [ -z "$free" ] && free=0
  [ -z "$inactive" ] && inactive=0
  local free_bytes inactive_bytes used_bytes
  free_bytes=$(( free * page_size ))
  inactive_bytes=$(( inactive * page_size ))
  used_bytes=$(( total_bytes - free_bytes - inactive_bytes ))
  local total_gb used_gb pressure
  total_gb=$(awk "BEGIN{printf \"%.1f\", $total_bytes/1073741824}")
  used_gb=$(awk "BEGIN{printf \"%.1f\", $used_bytes/1073741824}")
  pressure=$(awk "BEGIN{printf \"%.1f\", $used_bytes*100/$total_bytes}")
  echo "${used_gb}|${total_gb}|${pressure}"
}

get_cpu_usage() {
  # Use top with a short sample — safe on all macOS versions
  local result
  result=$(top -l 2 -n 0 2>/dev/null | awk '/CPU usage/{
    last=$0
  } END {
    if (last ~ /CPU usage/) {
      match(last, /([0-9.]+)% user/, u)
      match(last, /([0-9.]+)% sys/, s)
      printf "%.1f", u[1]+s[1]
    } else {
      print "0.0"
    }
  }')
  [ -z "$result" ] && result="0.0"
  echo "$result"
}

get_disk_stats() {
  df -h / 2>/dev/null | awk 'NR==2 {printf "%s|%s|%s", $3, $2, $5}' || echo "?|?|?"
}

get_battery() {
  pmset -g batt 2>/dev/null | awk -F'[;%]' '/InternalBattery/ {
    gsub(/[^0-9]/,"",$2); if ($2 != "") print $2
  }' | head -1 || echo ""
}

# ── UI Primitives ───────────────────────────────────────────────
draw_bar() {
  local value="$1"
  local max="${2:-100}"
  local width="${3:-28}"
  local pct filled color empty
  pct=$(awk "BEGIN{v=$value; m=$max; if(m==0)m=1; r=int(v*100/m); if(r>100)r=100; if(r<0)r=0; print r}")
  filled=$(awk "BEGIN{v=$value; m=$max; w=$width; if(m==0)m=1; r=int(v*w/m); if(r>w)r=w; if(r<0)r=0; print r}")
  empty=$(( width - filled ))

  if   [ "$pct" -lt 50 ] 2>/dev/null; then color=$C2
  elif [ "$pct" -lt 75 ] 2>/dev/null; then color=$C3
  else                                      color=$C4
  fi

  printf "${color}${B}["
  local i=0
  while [ $i -lt "$filled" ]; do printf "▪"; i=$(( i + 1 )); done
  printf "${D}${R}"
  i=0
  while [ $i -lt "$empty" ]; do printf "·"; i=$(( i + 1 )); done
  printf "${color}${B}]${R}"
}

hr() {
  local width="${1:-64}"
  local char="${2:-─}"
  printf "${D}"
  local i=0
  while [ $i -lt "$width" ]; do printf "%s" "$char"; i=$(( i + 1 )); done
  printf "${R}\n"
}

# ── Header ──────────────────────────────────────────────────────
print_header() {
  echo ""
  printf "  ${C1}${B}PerfGuard${R}  ${D}v${PERFGUARD_VERSION}  —  macOS System Performance Manager${R}\n"
  printf "  ${D}"
  hr 54
  echo ""
}

# ── STATUS ──────────────────────────────────────────────────────
cmd_status() {
  print_header
  local used_gb total_gb pressure
  IFS='|' read -r used_gb total_gb pressure <<< "$(get_ram_stats)"

  local cpu
  cpu=$(get_cpu_usage)

  local disk_used disk_total disk_pct
  IFS='|' read -r disk_used disk_total disk_pct <<< "$(get_disk_stats)"

  local battery
  battery=$(get_battery)

  local ram_pct cpu_pct d_pct
  ram_pct=$(awk "BEGIN{printf \"%.0f\", $pressure+0}")
  cpu_pct=$(awk "BEGIN{printf \"%.0f\", $cpu+0}")
  d_pct=$(echo "$disk_pct" | tr -d '%')
  [ -z "$d_pct" ] && d_pct=0

  local ram_lbl cpu_lbl
  if   [ "$ram_pct" -lt 50 ] 2>/dev/null; then ram_lbl="${C2}${B}Healthy${R}"
  elif [ "$ram_pct" -lt 75 ] 2>/dev/null; then ram_lbl="${C3}${B}Moderate${R}"
  else                                          ram_lbl="${C4}${B}Pressure${R}"
  fi
  if   [ "$cpu_pct" -lt 40 ] 2>/dev/null; then cpu_lbl="${C2}${B}Idle${R}"
  elif [ "$cpu_pct" -lt 70 ] 2>/dev/null; then cpu_lbl="${C3}${B}Active${R}"
  else                                          cpu_lbl="${C4}${B}High${R}"
  fi

  printf "  ${D}%-12s${R}  " "Memory"
  draw_bar "$used_gb" "$total_gb" 28
  printf "  ${C0}${B}%s${R}${D} / %sGB${R}  %b\n" "${used_gb}GB" "$total_gb" "$ram_lbl"

  printf "  ${D}%-12s${R}  " "CPU"
  draw_bar "$cpu_pct" 100 28
  printf "  ${C0}${B}%s%%${R}           %b\n" "$cpu_pct" "$cpu_lbl"

  printf "  ${D}%-12s${R}  " "Disk"
  draw_bar "$d_pct" 100 28
  printf "  ${C0}${B}%s${R}${D} / %s  (%s)${R}\n" "$disk_used" "$disk_total" "$disk_pct"

  echo ""
  local proc_count uptime_str
  proc_count=$(ps ax 2>/dev/null | wc -l | tr -d ' ')
  uptime_str=$(uptime 2>/dev/null | awk -F'up ' '{print $2}' | cut -d',' -f1 | xargs)
  printf "  ${D}Processes${R}   ${C0}${B}%s${R}        " "$proc_count"
  printf "${D}Uptime${R}   ${C0}${B}%s${R}\n" "$uptime_str"
  if [ -n "$battery" ]; then
    printf "  ${D}Battery${R}     ${C0}${B}%s%%${R}\n" "$battery"
  fi
  echo ""
}

# ── RAM BOOST ───────────────────────────────────────────────────
cmd_boost() {
  print_header
  printf "  ${C1}${B}RAM Boost${R}\n"
  printf "  ${D}Reclaiming inactive memory pages via macOS purge...${R}\n\n"

  local used_before
  IFS='|' read -r used_before _ _ <<< "$(get_ram_stats)"

  if sudo purge 2>/dev/null; then
    sleep 2
    local used_after total_gb pressure
    IFS='|' read -r used_after total_gb pressure <<< "$(get_ram_stats)"
    local freed
    freed=$(awk "BEGIN{printf \"%.1f\", $used_before - $used_after}")
    printf "  Before  ${C0}${B}%sGB${R}  →  After  ${C0}${B}%sGB${R}\n" "$used_before" "$used_after"
    printf "  Reclaimed  ${C2}${B}~%sGB${R}\n" "$freed"
    log "RAM Boost: reclaimed ~${freed}GB"
    printf "\n  ${C2}${B}Complete.${R}\n\n"
  else
    printf "  ${C3}Requires elevated privileges.${R}\n"
    printf "  ${D}Run:  ${R}${B}sudo perfguard boost${R}\n\n"
  fi
}

# ── CACHE CLEAN ─────────────────────────────────────────────────
cmd_clean() {
  print_header
  printf "  ${C1}${B}Cache Cleanup${R}\n\n"
  local total_freed=0

  _clean_row() {
    printf "  ${C2}+${R}  %-28s ${D}%s${R}  ${C0}${B}%s${R}\n" "$1" "$2" "$3"
  }

  # User caches
  local cache_dir="$HOME/Library/Caches"
  if [ -d "$cache_dir" ]; then
    local s_before s_after freed_kb freed_mb
    s_before=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
    find "$cache_dir" -mindepth 1 -maxdepth 2 -type f -mtime +1 -delete 2>/dev/null
    s_after=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
    freed_kb=$(( ${s_before:-0} - ${s_after:-0} ))
    freed_mb=$(awk "BEGIN{printf \"%.1fMB\", $freed_kb/1024}")
    _clean_row "User app caches" "~/Library/Caches" "$freed_mb"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $freed_kb/1024}")
    log "Clean: user caches freed ${freed_mb}"
  fi

  # Log files
  local log_dir="$HOME/Library/Logs"
  if [ -d "$log_dir" ]; then
    local s_before s_after freed_kb freed_mb
    s_before=$(du -sk "$log_dir" 2>/dev/null | awk '{print $1}')
    find "$log_dir" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +7 -delete 2>/dev/null
    s_after=$(du -sk "$log_dir" 2>/dev/null | awk '{print $1}')
    freed_kb=$(( ${s_before:-0} - ${s_after:-0} ))
    freed_mb=$(awk "BEGIN{printf \"%.1fMB\", $freed_kb/1024}")
    _clean_row "Old log files" "~/Library/Logs (>7d)" "$freed_mb"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $freed_kb/1024}")
    log "Clean: log files freed ${freed_mb}"
  fi

  # Temp files
  local tmp_count
  tmp_count=$(find "$TMPDIR" -maxdepth 1 -type f -mtime +0 2>/dev/null | wc -l | tr -d ' ')
  find "$TMPDIR" -maxdepth 1 -type f -mtime +0 -delete 2>/dev/null
  _clean_row "Temp files" "\$TMPDIR" "${tmp_count} files"
  log "Clean: removed ${tmp_count} temp files"

  # Crash reports
  local crash_dir="$HOME/Library/Logs/DiagnosticReports"
  if [ -d "$crash_dir" ]; then
    local count
    count=$(find "$crash_dir" -type f -mtime +14 2>/dev/null | wc -l | tr -d ' ')
    find "$crash_dir" -type f -mtime +14 -delete 2>/dev/null
    _clean_row "Crash reports" "DiagnosticReports (>14d)" "${count} files"
  fi

  # Xcode DerivedData
  local xcode_dd="$HOME/Library/Developer/Xcode/DerivedData"
  if [ -d "$xcode_dd" ]; then
    local xcode_size
    xcode_size=$(du -sm "$xcode_dd" 2>/dev/null | awk '{print $1+0}')
    if [ "${xcode_size:-0}" -gt 200 ] 2>/dev/null; then
      rm -rf "${xcode_dd:?}"/* 2>/dev/null
      _clean_row "Xcode DerivedData" "Build artifacts" "${xcode_size}MB"
      total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + ${xcode_size:-0}}")
      log "Clean: Xcode DerivedData freed ${xcode_size}MB"
    fi
  fi

  # npm cache
  if command -v npm >/dev/null 2>&1; then
    npm cache clean --force >/dev/null 2>&1
    _clean_row "npm package cache" "" "cleared"
    log "Clean: npm cache cleared"
  fi

  # pip3 cache
  if command -v pip3 >/dev/null 2>&1; then
    pip3 cache purge >/dev/null 2>&1
    _clean_row "pip package cache" "" "cleared"
    log "Clean: pip cache cleared"
  fi

  # Homebrew
  if command -v brew >/dev/null 2>&1; then
    local brew_out
    brew_out=$(brew cleanup --prune=7 2>/dev/null | grep -E "freed|Removed" | tail -1 || echo "done")
    _clean_row "Homebrew cache" "old versions + cache" "$brew_out"
    log "Clean: Homebrew cleanup done"
  fi

  echo ""
  printf "  Total freed  ${C2}${B}~%.0fMB${R}\n\n" "$total_freed"
}

# ── DEEP CLEAN ──────────────────────────────────────────────────
cmd_deep_clean() {
  print_header
  printf "  ${C1}${B}Deep Clean${R}  ${D}— Extended system sweep${R}\n\n"

  local total_freed=0

  _drow() {
    printf "  ${C2}+${R}  %-28s ${D}%s${R}  ${C0}${B}%s${R}\n" "$1" "$2" "$3"
  }

  # Safari cache
  local safari_cache="$HOME/Library/Caches/com.apple.Safari"
  if [ -d "$safari_cache" ]; then
    local sz
    sz=$(du -sm "$safari_cache" 2>/dev/null | awk '{print $1+0}')
    rm -rf "${safari_cache:?}"/* 2>/dev/null
    _drow "Safari cache" "Website data" "~${sz}MB"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + ${sz:-0}}")
  fi

  # Chrome cache
  local chrome_cache="$HOME/Library/Caches/Google/Chrome"
  if [ -d "$chrome_cache" ]; then
    local sz
    sz=$(du -sm "$chrome_cache" 2>/dev/null | awk '{print $1+0}')
    find "$chrome_cache" -name "Cache" -type d 2>/dev/null | while read -r d; do rm -rf "${d:?}"/* 2>/dev/null; done
    _drow "Chrome cache" "Browser cache" "~${sz}MB"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + ${sz:-0}}")
  fi

  # Firefox cache
  local ff_cache="$HOME/Library/Caches/Firefox"
  if [ -d "$ff_cache" ]; then
    local sz
    sz=$(du -sm "$ff_cache" 2>/dev/null | awk '{print $1+0}')
    find "$ff_cache" -name "cache2" -type d 2>/dev/null | while read -r d; do rm -rf "${d:?}"/* 2>/dev/null; done
    _drow "Firefox cache" "Browser cache" "~${sz}MB"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + ${sz:-0}}")
  fi

  # .DS_Store files
  local ds_count
  ds_count=$(find "$HOME" -name ".DS_Store" -maxdepth 6 2>/dev/null | wc -l | tr -d ' ')
  find "$HOME" -name ".DS_Store" -maxdepth 6 -delete 2>/dev/null
  _drow ".DS_Store files" "Desktop metadata" "${ds_count} files"
  log "Deep clean: removed ${ds_count} .DS_Store files"

  # iOS device backups info
  local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
  if [ -d "$backup_dir" ]; then
    local backup_size
    backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
    printf "  ${C3}!${R}  %-28s ${D}Review in Finder${R}  ${C0}${B}%s${R}\n" "iOS backups (manual)" "${backup_size:-0B}"
  fi

  echo ""
  printf "  Extended total freed  ${C2}${B}~%.0fMB${R}\n\n" "$total_freed"
  log "Deep clean completed"
}

# ── DNS FLUSH ───────────────────────────────────────────────────
cmd_dns_flush() {
  print_header
  printf "  ${C1}${B}DNS Cache Flush${R}\n\n"
  printf "  ${D}Flushing macOS DNS resolver cache...${R}\n"
  if sudo dscacheutil -flushcache 2>/dev/null && sudo killall -HUP mDNSResponder 2>/dev/null; then
    printf "  ${C2}${B}Complete.${R}  DNS cache cleared and mDNSResponder reloaded.\n\n"
    log "DNS cache flushed"
  else
    printf "  ${C3}Requires elevated privileges.${R}  Run: ${B}sudo perfguard dns-flush${R}\n\n"
  fi
}

# ── NETWORK DIAGNOSTICS ─────────────────────────────────────────
cmd_network() {
  print_header
  printf "  ${C1}${B}Network Diagnostics${R}\n\n"

  printf "  ${D}Active interfaces:${R}\n"
  networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r svc; do
    local ip
    ip=$(networksetup -getinfo "$svc" 2>/dev/null | awk '/^IP address:/{print $3}')
    if [ -n "$ip" ] && [ "$ip" != "none" ]; then
      printf "  ${C7}  %-22s${R}  ${C0}%s${R}\n" "$svc" "$ip"
    fi
  done

  echo ""
  printf "  ${D}Connectivity tests:${R}\n"
  for entry in "8.8.8.8:Google DNS" "1.1.1.1:Cloudflare DNS" "apple.com:Apple"; do
    local host label ms
    host=$(echo "$entry" | cut -d: -f1)
    label=$(echo "$entry" | cut -d: -f2)
    if ping -c 1 -W 1000 "$host" >/dev/null 2>&1; then
      ms=$(ping -c 1 "$host" 2>/dev/null | awk -F'/' '/round-trip/{printf "%.1f", $5}')
      printf "  ${C2}  %-22s${R}  ${D}%s ms${R}\n" "$label" "${ms:-?}"
    else
      printf "  ${C4}  %-22s${R}  ${D}unreachable${R}\n" "$label"
    fi
  done

  echo ""
  local wifi_signal
  wifi_signal=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/agrCtlRSSI/{print $2}')
  if [ -n "$wifi_signal" ]; then
    printf "  ${D}Wi-Fi signal strength:${R}  ${C0}${B}%s dBm${R}\n" "$wifi_signal"
  fi
  echo ""
}

# ── STARTUP SCAN ────────────────────────────────────────────────
cmd_startup_scan() {
  print_header
  printf "  ${C1}${B}Startup Items Scan${R}  ${D}— Items that launch on login${R}\n\n"

  printf "  ${D}Login Items:${R}\n"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | tr ',' '\n' | sed 's/^ //' | while IFS= read -r item; do
      [ -z "$item" ] && continue
      printf "  ${C7}  %s${R}\n" "$item"
    done

  echo ""
  printf "  ${D}User Launch Agents:${R}\n"
  local agent_dir="$HOME/Library/LaunchAgents"
  if [ -d "$agent_dir" ]; then
    local found=0
    for plist in "$agent_dir"/*.plist; do
      [ -f "$plist" ] || continue
      local name disabled
      name=$(basename "$plist" .plist)
      disabled=$(defaults read "$plist" Disabled 2>/dev/null || echo "0")
      if [ "$disabled" = "1" ]; then
        printf "  ${D}  %-52s  disabled${R}\n" "$name"
      else
        printf "  ${C0}  %-52s  ${C2}active${R}\n" "$name"
      fi
      found=1
    done
    [ "$found" = "0" ] && printf "  ${D}  none${R}\n"
  fi
  echo ""
}

# ── DISK USAGE ──────────────────────────────────────────────────
cmd_disk_usage() {
  print_header
  printf "  ${C1}${B}Disk Usage Breakdown${R}\n\n"

  local entries=(
    "$HOME/Downloads:Downloads"
    "$HOME/Documents:Documents"
    "$HOME/Desktop:Desktop"
    "$HOME/Movies:Movies"
    "$HOME/Music:Music"
    "$HOME/Library/Caches:App Caches"
    "$HOME/Library/Application Support:App Data"
    "$HOME/.Trash:Trash"
  )

  # First pass: collect sizes
  local max_mb=1
  declare -a labels sizes_arr
  for entry in "${entries[@]}"; do
    local dir label sz
    dir=$(echo "$entry" | cut -d: -f1)
    label=$(echo "$entry" | cut -d: -f2)
    if [ -d "$dir" ]; then
      sz=$(du -sm "$dir" 2>/dev/null | awk '{print $1+0}')
    else
      sz=0
    fi
    labels+=("$label")
    sizes_arr+=("$sz")
    [ "$sz" -gt "$max_mb" ] 2>/dev/null && max_mb=$sz
  done

  # Second pass: print bars
  local idx=0
  for label in "${labels[@]}"; do
    local sz="${sizes_arr[$idx]}"
    idx=$(( idx + 1 ))
    printf "  ${D}%-22s${R}  " "$label"
    local bar_w=24
    local filled
    filled=$(awk "BEGIN{r=int($sz*$bar_w/$max_mb); if(r>$bar_w)r=$bar_w; if(r<0)r=0; print r}")
    local color
    if   [ "$sz" -gt 10000 ] 2>/dev/null; then color=$C4
    elif [ "$sz" -gt 2000  ] 2>/dev/null; then color=$C3
    else                                        color=$C2
    fi
    printf "${color}"
    local i=0
    while [ $i -lt "$filled" ]; do printf "▪"; i=$(( i + 1 )); done
    printf "${R}${D}"
    i=$filled
    while [ $i -lt $bar_w ]; do printf "·"; i=$(( i + 1 )); done
    printf "${R}  ${C0}${B}"
    if [ "$sz" -gt 1024 ] 2>/dev/null; then
      awk "BEGIN{printf \"%.1fGB\", $sz/1024}"
    else
      printf "%sMB" "$sz"
    fi
    printf "${R}\n"
  done

  echo ""
  printf "  ${D}Total disk:${R}  "
  df -h / 2>/dev/null | awk 'NR==2 {printf "%s used of %s (%s full)\n", $3, $2, $5}'
  echo ""
}

# ── SWAP INFO ───────────────────────────────────────────────────
cmd_swap_info() {
  print_header
  printf "  ${C1}${B}Swap & Virtual Memory${R}\n\n"
  local swapusage
  swapusage=$(sysctl -n vm.swapusage 2>/dev/null || echo "N/A")
  printf "  ${D}Swap:${R}   ${C0}%s${R}\n\n" "$swapusage"
  printf "  ${D}VM Statistics:${R}\n"
  vm_stat 2>/dev/null | grep -E "(free|active|inactive|wired|compressed|pageins|pageouts|swapins|swapouts)" \
    | while IFS= read -r line; do
      printf "  ${D}  %s${R}\n" "$line"
    done
  echo ""
}

# ── MEMORY PRESSURE WATCH ────────────────────────────────────────
cmd_pressure_watch() {
  print_header
  printf "  ${C1}${B}Memory Pressure Watch${R}  ${D}— Live (Ctrl+C to stop)${R}\n\n"
  local alert_threshold=80
  while true; do
    local used_gb total_gb pressure
    IFS='|' read -r used_gb total_gb pressure <<< "$(get_ram_stats)"
    local pct ts
    pct=$(awk "BEGIN{printf \"%.0f\", $pressure+0}")
    ts=$(date '+%H:%M:%S')
    printf "\r  ${D}%s${R}  " "$ts"
    draw_bar "$pct" 100 30
    printf "  ${C0}${B}%s${R}${D}/%sGB${R}  " "$used_gb" "$total_gb"
    if [ "$pct" -ge "$alert_threshold" ] 2>/dev/null; then
      printf "${C4}${B}%s%% — PRESSURE ALERT${R}   " "$pct"
      log "Memory pressure alert: ${pct}%" "WARN"
    else
      printf "${C2}${B}%s%%${R}   " "$pct"
    fi
    sleep 5
  done
}

# ── PROCESS MANAGER ─────────────────────────────────────────────
cmd_kill_unused() {
  load_whitelist
  print_header
  printf "  ${C1}${B}Process Manager${R}  ${D}— Unauthorized processes using >150MB${R}\n\n"

  local killed=0 skipped=0 found=0

  while IFS= read -r line; do
    local pid mem_kb name mem_mb
    pid=$(echo "$line" | awk '{print $1}')
    mem_kb=$(echo "$line" | awk '{print $2}')
    name=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
    mem_mb=$(awk "BEGIN{printf \"%.0f\", ${mem_kb:-0}/1024}")

    [ "${mem_mb:-0}" -le 150 ] 2>/dev/null && continue

    local approved
    approved=$(is_approved "$name")
    if [ "$approved" = "false" ]; then
      found=1
      printf "  ${C4}!${R}  ${B}%-40s${R}  ${D}%sMB  PID %s${R}\n" "$name" "$mem_mb" "$pid"
      printf "    Kill? [y/N] "
      local confirm
      read -r confirm
      if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if kill -9 "$pid" 2>/dev/null; then
          printf "  ${C2}  Terminated.${R}\n"
          log "Killed: $name (PID $pid, ${mem_mb}MB)" "WARN"
          killed=$(( killed + 1 ))
        fi
      else
        skipped=$(( skipped + 1 ))
      fi
    fi
  done < <(ps -axo pid,rss,comm 2>/dev/null | tail -n +2 | sort -k2 -rn | head -50)

  echo ""
  if [ "$found" = "0" ]; then
    printf "  ${C2}${B}No unauthorized heavy processes found.${R}\n"
  else
    [ "$killed" -gt 0 ] && printf "  Terminated  ${C4}${B}%d process(es)${R}\n" "$killed"
    [ "$skipped" -gt 0 ] && printf "  Skipped     ${C3}${B}%d process(es)${R}\n" "$skipped"
  fi
  echo ""
}

# ── LIVE MONITOR ─────────────────────────────────────────────────
cmd_monitor() {
  load_whitelist
  local first_run="true"
  while true; do
    local used_gb total_gb pressure cpu ram_pct cpu_pct
    IFS='|' read -r used_gb total_gb pressure <<< "$(get_ram_stats)"
    cpu=$(get_cpu_usage)
    ram_pct=$(awk "BEGIN{printf \"%.0f\", $pressure+0}")
    cpu_pct=$(awk "BEGIN{printf \"%.0f\", $cpu+0}")

    if [ "$first_run" = "false" ]; then
      tput cuu 28 2>/dev/null
    fi
    first_run="false"

    printf "  ${C1}${B}PerfGuard${R}  ${D}Live Monitor — %s — Ctrl+C to exit${R}\n" "$(date '+%H:%M:%S')"
    printf "  "
    hr 62
    printf "  ${D}Memory${R}  "
    draw_bar "$ram_pct" 100 26
    printf "  ${C0}${B}%s${R}${D}/%sGB${R}    ${D}CPU${R}  "
    draw_bar "$cpu_pct" 100 16
    printf "  ${C0}${B}%s%%${R}\n\n" "$cpu_pct"

    printf "  ${D}%-7s  %-36s  %8s  %6s  %-12s${R}\n" "PID" "PROCESS" "MEM" "CPU%" "STATUS"
    printf "  ${D}"; hr 62 "─"

    local count=0
    while IFS= read -r line && [ "$count" -lt 20 ]; do
      local pid cpu_p mem_kb name mem_mb sc sl
      pid=$(echo "$line" | awk '{print $1}')
      cpu_p=$(echo "$line" | awk '{print $2}')
      mem_kb=$(echo "$line" | awk '{print $3}')
      name=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | xargs | cut -c1-36)
      mem_mb=$(awk "BEGIN{printf \"%.0f\", ${mem_kb:-0}/1024}")
      local approved
      approved=$(is_approved "$name")
      if [ "$approved" = "true" ]; then sc=$C2; sl="approved"
      else sc=$C4; sl="unknown"; fi
      printf "  ${D}%-7s${R}  %-36s  ${C0}${B}%6sMB${R}  ${D}%5s%%${R}  ${sc}%-12s${R}\n" \
        "$pid" "$name" "$mem_mb" "$cpu_p" "$sl"
      count=$(( count + 1 ))
    done < <(ps -axo pid,pcpu,rss,comm 2>/dev/null | tail -n +2 | sort -k3 -rn)
    sleep 3
  done
}

# ── TURBO MODE ───────────────────────────────────────────────────
cmd_turbo() {
  print_header
  printf "  ${C5}${B}Turbo Mode${R}  ${D}— Full system optimization sequence${R}\n\n"
  printf "  ${D}kill-unused → deep-clean → dns-flush → boost${R}\n\n"
  hr 64
  echo ""
  cmd_kill_unused
  echo ""; hr 64; echo ""
  cmd_deep_clean
  echo ""; hr 64; echo ""
  cmd_dns_flush
  echo ""; hr 64; echo ""
  cmd_boost
  printf "  ${C2}${B}All optimizations complete.${R}\n\n"
  log "Turbo mode completed"
}

# ── WHITELIST MANAGER ────────────────────────────────────────────
cmd_whitelist() {
  load_whitelist
  print_header
  printf "  ${C1}${B}Whitelist Manager${R}\n\n"
  printf "  ${D}Built-in approved processes (%d):${R}\n" "${#APPROVED_APPS[@]}"
  local col=0
  local app
  for app in "${APPROVED_APPS[@]}"; do
    printf "  ${D}%-24s${R}" "$app"
    col=$(( col + 1 ))
    [ $(( col % 3 )) -eq 0 ] && echo ""
  done
  echo ""
  if [ -s "$WHITELIST_FILE" ]; then
    echo ""
    printf "  ${D}User-added entries:${R}\n"
    while IFS= read -r line; do
      [ -n "$line" ] && printf "  ${C2}+${R}  %s\n" "$line"
    done < "$WHITELIST_FILE"
  fi
  echo ""
  printf "  ${D}Add:${R}  ${C0}echo 'AppName' >> ~/.perfguard/whitelist${R}\n\n"
}

# ── SCHEDULE ────────────────────────────────────────────────────
cmd_schedule() {
  print_header
  printf "  ${C1}${B}Auto-Cleanup Scheduler${R}\n\n"
  local script_path
  script_path=$(command -v perfguard 2>/dev/null || echo "$0")

  printf "  ${D}Choose schedule:${R}\n\n"
  printf "  ${C1}1${R}  Every 30 minutes\n"
  printf "  ${C1}2${R}  Every hour\n"
  printf "  ${C1}3${R}  Daily at 3:00 AM\n"
  echo ""
  printf "  Select [1-3]: "
  local choice
  read -r choice

  local cron_expr
  case "$choice" in
    1) cron_expr="*/30 * * * *" ;;
    2) cron_expr="0 * * * *" ;;
    3) cron_expr="0 3 * * *" ;;
    *) printf "  ${C4}Invalid selection.${R}\n\n"; return ;;
  esac

  local cron_job="${cron_expr} ${script_path} clean >> ${LOG_FILE} 2>&1"
  ( crontab -l 2>/dev/null | grep -v "perfguard"; echo "$cron_job" ) | crontab -
  printf "  ${C2}${B}Scheduled.${R}  Cron entry added.\n"
  printf "  ${D}To remove: ${R}crontab -e  ${D}and delete the perfguard line.${R}\n\n"
  log "Auto-cleanup scheduled: $cron_expr"
}

# ── LOG VIEWER ───────────────────────────────────────────────────
cmd_log() {
  print_header
  printf "  ${C1}${B}Activity Log${R}  ${D}— last 40 entries${R}\n\n"
  if [ -s "$LOG_FILE" ]; then
    tail -40 "$LOG_FILE" | while IFS= read -r line; do
      printf "  ${D}%s${R}\n" "$line"
    done
  else
    printf "  ${D}No entries recorded yet.${R}\n"
  fi
  echo ""
}

# ── INTERACTIVE MENU ─────────────────────────────────────────────
cmd_menu() {
  while true; do
    clear
    print_header

    local used_gb total_gb pressure cpu ram_pct cpu_pct disk_info
    IFS='|' read -r used_gb total_gb pressure <<< "$(get_ram_stats)"
    cpu=$(get_cpu_usage)
    ram_pct=$(awk "BEGIN{printf \"%.0f\", $pressure+0}")
    cpu_pct=$(awk "BEGIN{printf \"%.0f\", $cpu+0}")
    disk_info=$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2}')

    printf "  ${D}Memory${R}  "
    draw_bar "$ram_pct" 100 22
    printf "  ${C0}${B}%s${R}${D}/%sGB${R}    " "$used_gb" "$total_gb"
    printf "${D}CPU${R}  "
    draw_bar "$cpu_pct" 100 14
    printf "  ${C0}${B}%s%%${R}    ${D}Disk${R} ${C0}${B}%s${R}\n\n" "$cpu_pct" "$disk_info"

    printf "  "
    hr 54
    echo ""

    printf "  ${C1}1${R}  System overview\n"
    printf "  ${C1}2${R}  RAM boost  ${D}(sudo)${R}\n"
    printf "  ${C1}3${R}  Cache cleanup\n"
    printf "  ${C1}4${R}  Deep system sweep\n"
    printf "  ${C1}5${R}  Process manager\n"
    printf "  ${C1}6${R}  Live process monitor\n"
    printf "  ${C1}7${R}  Full optimization sequence\n"
    echo ""
    printf "  "
    hr 40
    echo ""
    printf "  ${C1}8${R}  DNS cache flush\n"
    printf "  ${C1}9${R}  Network diagnostics\n"
    printf "  ${C1}a${R}  Startup items scan\n"
    printf "  ${C1}b${R}  Disk usage breakdown\n"
    printf "  ${C1}c${R}  Swap & virtual memory\n"
    printf "  ${C1}d${R}  Memory pressure watch\n"
    printf "  ${C1}e${R}  Schedule auto-cleanup\n"
    printf "  ${C1}f${R}  Manage process whitelist\n"
    printf "  ${C1}g${R}  View activity log\n"
    echo ""
    printf "  ${C4}q${R}  Quit\n"
    echo ""
    printf "  "
    hr 54
    printf "\n  ${D}Enter option:${R}  "

    # Use plain read (requires Enter) — reliable across all terminals
    local choice
    read -r choice

    case "$choice" in
      1) cmd_status ;;
      2) cmd_boost ;;
      3) cmd_clean ;;
      4) cmd_deep_clean ;;
      5) cmd_kill_unused ;;
      6) cmd_monitor ;;
      7) cmd_turbo ;;
      8) cmd_dns_flush ;;
      9) cmd_network ;;
      a|A) cmd_startup_scan ;;
      b|B) cmd_disk_usage ;;
      c|C) cmd_swap_info ;;
      d|D) cmd_pressure_watch ;;
      e|E) cmd_schedule ;;
      f|F) cmd_whitelist ;;
      g|G) cmd_log ;;
      q|Q) echo ""; exit 0 ;;
      *) printf "\n  ${C3}Unknown option. Try again.${R}\n" ;;
    esac

    echo ""
    printf "  ${D}Press Enter to return to menu...${R}"
    read -r
    clear
  done
}

# ── HELP ────────────────────────────────────────────────────────
cmd_help() {
  print_header
  printf "  ${D}Usage:${R}  perfguard ${C1}[command]${R}\n\n"
  local cmds=(
    "menu:Interactive menu (default)"
    "status:RAM, CPU, disk, uptime overview"
    "boost:Flush inactive memory  (sudo)"
    "clean:Clear caches, temp files, build artifacts"
    "deep-clean:Extended sweep — browsers, .DS_Store"
    "kill-unused:Interactive unauthorized process manager"
    "monitor:Live top-like process view"
    "turbo:Full optimization sequence"
    "dns-flush:Clear macOS DNS resolver cache"
    "network:Interface info, ping, diagnostics"
    "startup-scan:Login items and launch agents audit"
    "disk-usage:Per-folder disk usage breakdown"
    "swap-info:Swap and virtual memory statistics"
    "pressure-watch:Live memory pressure alert monitor"
    "schedule:Cron-based auto-cleanup"
    "whitelist:View and manage approved process list"
    "log:Activity log viewer"
    "version:Print version"
  )
  for cmd in "${cmds[@]}"; do
    local key val
    key=$(echo "$cmd" | cut -d: -f1)
    val=$(echo "$cmd" | cut -d: -f2)
    printf "  ${C1}%-18s${R}  ${D}%s${R}\n" "$key" "$val"
  done
  echo ""
  printf "  ${D}Whitelist:  ${R}echo 'AppName' >> ~/.perfguard/whitelist\n"
  printf "  ${D}Log:        ${R}%s\n\n" "$LOG_FILE"
}

# ── Entrypoint ───────────────────────────────────────────────────
bootstrap

case "${1:-menu}" in
  menu)           cmd_menu ;;
  status)         cmd_status ;;
  boost)          cmd_boost ;;
  clean)          cmd_clean ;;
  deep-clean)     cmd_deep_clean ;;
  kill-unused)    cmd_kill_unused ;;
  monitor)        cmd_monitor ;;
  turbo)          cmd_turbo ;;
  dns-flush)      cmd_dns_flush ;;
  network)        cmd_network ;;
  startup-scan)   cmd_startup_scan ;;
  disk-usage)     cmd_disk_usage ;;
  swap-info)      cmd_swap_info ;;
  pressure-watch) cmd_pressure_watch ;;
  schedule)       cmd_schedule ;;
  whitelist)      cmd_whitelist ;;
  log)            cmd_log ;;
  help|--help|-h) cmd_help ;;
  version|--version) printf "\nPerfGuard %s\n\n" "$PERFGUARD_VERSION" ;;
  *)              printf "\n  Unknown command. Run: perfguard help\n\n" ;;
esac