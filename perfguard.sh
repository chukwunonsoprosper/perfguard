#!/usr/bin/env bash
# ================================================================
#  PerfGuard v2.0 — macOS System Performance Manager
#  Install: curl -fsSL https://raw.githubusercontent.com/perfguard/perfguard/main/install.sh | bash
#  Usage:   perfguard [command]
# ================================================================

set -euo pipefail

PERFGUARD_VERSION="2.0.0"
LOG_FILE="$HOME/.perfguard/perfguard.log"
WHITELIST_FILE="$HOME/.perfguard/whitelist"
CONFIG_FILE="$HOME/.perfguard/config"

# ── ANSI ────────────────────────────────────────────────────────
R="\033[0m"
B="\033[1m"
D="\033[2m"
UL="\033[4m"

C0="\033[38;5;255m"   # bright white
C1="\033[38;5;39m"    # azure
C2="\033[38;5;82m"    # lime green
C3="\033[38;5;220m"   # amber
C4="\033[38;5;196m"   # red
C5="\033[38;5;135m"   # violet
C6="\033[38;5;208m"   # orange
C7="\033[38;5;51m"    # cyan

BG1="\033[48;5;234m"  # near-black bg
BG2="\033[48;5;236m"  # panel bg

# ── Bootstrap ───────────────────────────────────────────────────
bootstrap() {
  mkdir -p "$HOME/.perfguard"
  [[ ! -f "$LOG_FILE" ]] && touch "$LOG_FILE"
  [[ ! -f "$WHITELIST_FILE" ]] && touch "$WHITELIST_FILE"
}

# ── Logging ─────────────────────────────────────────────────────
log() {
  local level="${2:-INFO}"
  printf "[%s] [%-5s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$1" >> "$LOG_FILE"
}

# ── Approved process whitelist ───────────────────────────────────
APPROVED_APPS=(
  "Finder" "Safari" "Google Chrome" "Firefox" "Arc" "Brave Browser"
  "Code" "Cursor" "Terminal" "iTerm2" "Warp" "Alacritty"
  "Xcode" "Simulator" "Instruments"
  "Slack" "Zoom" "Teams" "Discord" "Telegram" "WhatsApp"
  "Mail" "Messages" "FaceTime" "Calendar" "Reminders" "Notes"
  "Music" "Spotify" "Podcast" "Photos" "Preview"
  "System Preferences" "System Settings" "System Information"
  "Activity Monitor" "Console" "Disk Utility" "Keychain Access"
  "Dock" "WindowServer" "loginwindow" "Spotlight"
  "ControlCenter" "controlcenter" "NotificationCenter"
  "coreaudiod" "coremediaiod" "useractivityd" "distnoted"
  "launchd" "kernel_task" "mds" "mds_stores" "mdworker"
  "bash" "zsh" "sh" "fish" "python3" "ruby" "node"
  "ssh" "git" "vim" "nvim" "emacs" "nano"
  "perfguard" "TextEdit" "Finder"
  "UserEventAgent" "cfprefsd" "lsd" "nsurlsessiond"
  "trustd" "secinitd" "authd" "opendirectoryd"
  "networkd_privileged" "configd" "powerd" "thermalmonitord"
)

load_whitelist() {
  if [[ -f "$WHITELIST_FILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" && "${line:0:1}" != "#" ]] && APPROVED_APPS+=("$line")
    done < "$WHITELIST_FILE"
  fi
}

is_approved() {
  local pname="$1"
  for app in "${APPROVED_APPS[@]}"; do
    if [[ "$pname" == *"$app"* ]] || [[ "$app" == *"$pname"* ]]; then
      echo "true"; return
    fi
  done
  echo "false"
}

# ── System Info ─────────────────────────────────────────────────
get_ram_stats() {
  local total_bytes page_size free inactive wired active
  total_bytes=$(sysctl -n hw.memsize)
  page_size=$(vm_stat | awk '/page size/ {print $8}')
  [[ -z "$page_size" ]] && page_size=16384
  free=$(vm_stat | awk '/^Pages free:/ {gsub(/\./,"",$3); print $3}')
  inactive=$(vm_stat | awk '/^Pages inactive:/ {gsub(/\./,"",$3); print $3}')
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
  top -l 1 -n 0 2>/dev/null | awk '/CPU usage/ {
    gsub(/%/,""); split($0,a,"[:,%]");
    user=0; sys=0;
    for(i=1;i<=length(a);i++){
      if(a[i]~/user/) user=a[i+1];
      if(a[i]~/sys/) sys=a[i+1];
    }
    printf "%.1f", user+sys
  }' || echo "0.0"
}

get_disk_stats() {
  df -h / 2>/dev/null | awk 'NR==2 {
    gsub(/Gi/,""); printf "%s|%s|%s", $3, $2, $5
  }'
}

get_cpu_temp() {
  if command -v osx-cpu-temp &>/dev/null; then
    osx-cpu-temp 2>/dev/null | tr -d '°C' || echo "N/A"
  elif command -v istats &>/dev/null; then
    istats cpu temp --value-only 2>/dev/null || echo "N/A"
  else
    echo "N/A"
  fi
}

get_battery() {
  pmset -g batt 2>/dev/null | awk -F'[;%]' '/InternalBattery/ {
    gsub(/[^0-9]/,"",$2); print $2
  }' | head -1 || echo "N/A"
}

# ── UI Primitives ───────────────────────────────────────────────
draw_bar() {
  local value=$1 max=${2:-100} width=${3:-28}
  local pct filled color
  pct=$(awk "BEGIN{printf \"%.0f\", $value*100/$max}")
  filled=$(awk "BEGIN{printf \"%.0f\", $value*$width/$max}")
  local empty=$(( width - filled ))

  if   (( pct < 50 )); then color=$C2
  elif (( pct < 75 )); then color=$C3
  else                      color=$C4
  fi

  printf "${color}${B}["
  for ((i=0; i<filled; i++)); do printf "▪"; done
  printf "${D}${R}"
  for ((i=0; i<empty; i++)); do printf "·"; done
  printf "${color}${B}]${R}"
}

hr() {
  local width=${1:-64} char=${2:-─}
  printf "${D}"
  for ((i=0; i<width; i++)); do printf "%s" "$char"; done
  printf "${R}\n"
}

label_color() {
  local pct=$1
  if   (( $(awk "BEGIN{print ($pct < 50)}") == 1 )); then echo "$C2"
  elif (( $(awk "BEGIN{print ($pct < 75)}") == 1 )); then echo "$C3"
  else echo "$C4"; fi
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
  IFS='|' read -r used_gb total_gb pressure <<< "$(get_ram_stats)"
  local cpu disk_used disk_total disk_pct battery
  cpu=$(get_cpu_usage)
  IFS='|' read -r disk_used disk_total disk_pct <<< "$(get_disk_stats)"
  battery=$(get_battery)

  local ram_pct
  ram_pct=$(awk "BEGIN{printf \"%.0f\", $pressure}")
  local cpu_pct
  cpu_pct=$(awk "BEGIN{printf \"%.0f\", $cpu}")
  local d_pct
  d_pct=$(echo "$disk_pct" | tr -d '%')

  local ram_lbl cpu_lbl
  if   (( ram_pct < 50 )); then ram_lbl="${C2}${B}Healthy${R}"
  elif (( ram_pct < 75 )); then ram_lbl="${C3}${B}Moderate${R}"
  else                          ram_lbl="${C4}${B}Pressure${R}"
  fi
  if   (( cpu_pct < 40 )); then cpu_lbl="${C2}${B}Idle${R}"
  elif (( cpu_pct < 70 )); then cpu_lbl="${C3}${B}Active${R}"
  else                          cpu_lbl="${C4}${B}High${R}"
  fi

  printf "  ${D}%-12s${R}  " "Memory"
  draw_bar "$used_gb" "$total_gb" 28
  printf "  ${C0}${B}%s${R}${D} / %sGB${R}  %s\n" "${used_gb}GB" "$total_gb" "$ram_lbl"

  printf "  ${D}%-12s${R}  " "CPU"
  draw_bar "$cpu_pct" 100 28
  printf "  ${C0}${B}%s%%${R}           %s\n" "$cpu_pct" "$cpu_lbl"

  printf "  ${D}%-12s${R}  " "Disk"
  draw_bar "$d_pct" 100 28
  printf "  ${C0}${B}%s${R}${D} / %s  (%s)${R}\n" "$disk_used" "$disk_total" "$disk_pct"

  echo ""
  local proc_count uptime_str
  proc_count=$(ps ax | wc -l | tr -d ' ')
  uptime_str=$(uptime | awk -F'up ' '{print $2}' | cut -d',' -f1 | xargs)
  printf "  ${D}Processes${R}   ${C0}${B}%s${R}        " "$proc_count"
  printf "${D}Uptime${R}   ${C0}${B}%s${R}\n" "$uptime_str"
  [[ "$battery" != "N/A" && -n "$battery" ]] && \
    printf "  ${D}Battery${R}     ${C0}${B}%s%%${R}\n" "$battery"
  echo ""
}

# ── RAM BOOST ───────────────────────────────────────────────────
cmd_boost() {
  print_header
  printf "  ${C1}${B}RAM Boost${R}\n"
  printf "  ${D}Reclaiming inactive memory pages via macOS purge...${R}\n\n"

  IFS='|' read -r used_before _ _ <<< "$(get_ram_stats)"

  if sudo purge 2>/dev/null; then
    sleep 2
    IFS='|' read -r used_after total_gb pressure <<< "$(get_ram_stats)"
    local freed
    freed=$(awk "BEGIN{printf \"%.1f\", $used_before - $used_after}")

    printf "  Before   ${C0}${B}%sGB${R}  →  After   ${C0}${B}%sGB${R}\n" "$used_before" "$used_after"
    if (( $(awk "BEGIN{print ($freed > 0)}") == 1 )); then
      printf "  Reclaimed  ${C2}${B}~%sGB${R}\n" "$freed"
      log "RAM Boost: reclaimed ~${freed}GB"
    fi
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

  _clean_item() {
    local label="$1" freed_mb="$2" detail="$3"
    printf "  ${C2}+${R}  %-28s ${D}%s${R}  ${C0}${B}%s${R}\n" "$label" "$detail" "$freed_mb"
  }

  # User caches
  local cache_dir="$HOME/Library/Caches"
  if [[ -d "$cache_dir" ]]; then
    local s_before s_after freed_kb freed_mb
    s_before=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
    find "$cache_dir" -mindepth 1 -maxdepth 2 -type f -mtime +1 -delete 2>/dev/null || true
    s_after=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
    freed_kb=$(( s_before - s_after ))
    freed_mb=$(awk "BEGIN{printf \"%.1fMB\", $freed_kb/1024}")
    _clean_item "User app caches" "$freed_mb" "~/Library/Caches"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $freed_kb/1024}")
    log "Clean: user caches freed ${freed_mb}" "INFO"
  fi

  # Log files
  local log_dir="$HOME/Library/Logs"
  if [[ -d "$log_dir" ]]; then
    local s_before s_after freed_kb freed_mb
    s_before=$(du -sk "$log_dir" 2>/dev/null | awk '{print $1}')
    find "$log_dir" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +7 -delete 2>/dev/null || true
    s_after=$(du -sk "$log_dir" 2>/dev/null | awk '{print $1}')
    freed_kb=$(( s_before - s_after ))
    freed_mb=$(awk "BEGIN{printf \"%.1fMB\", $freed_kb/1024}")
    _clean_item "Old log files" "$freed_mb" "~/Library/Logs (>7d)"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $freed_kb/1024}")
    log "Clean: log files freed ${freed_mb}" "INFO"
  fi

  # Temp files
  local tmp_count
  tmp_count=$(find "$TMPDIR" -maxdepth 1 -type f -mtime +0 2>/dev/null | wc -l | tr -d ' ')
  find "$TMPDIR" -maxdepth 1 -type f -mtime +0 -delete 2>/dev/null || true
  _clean_item "Temp files" "${tmp_count} files" "\$TMPDIR"
  log "Clean: removed ${tmp_count} temp files" "INFO"

  # Crash reports
  local crash_dir="$HOME/Library/Logs/DiagnosticReports"
  if [[ -d "$crash_dir" ]]; then
    local count
    count=$(find "$crash_dir" -type f -mtime +14 2>/dev/null | wc -l | tr -d ' ')
    find "$crash_dir" -type f -mtime +14 -delete 2>/dev/null || true
    _clean_item "Crash reports" "${count} files" "DiagnosticReports (>14d)"
  fi

  # iOS device backups summary
  local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
  if [[ -d "$backup_dir" ]]; then
    local backup_size
    backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
    printf "  ${C3}!${R}  %-28s ${D}%s${R}  ${C0}${B}%s${R}\n" \
      "iOS backups (manual)" "Review in Finder" "${backup_size:-0B} total"
  fi

  # Xcode derived data
  local xcode_dd="$HOME/Library/Developer/Xcode/DerivedData"
  if [[ -d "$xcode_dd" ]]; then
    local xcode_size
    xcode_size=$(du -sm "$xcode_dd" 2>/dev/null | awk '{print $1}')
    if (( xcode_size > 200 )); then
      rm -rf "${xcode_dd:?}"/* 2>/dev/null || true
      _clean_item "Xcode DerivedData" "${xcode_size}MB" "Build artifacts"
      total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $xcode_size}")
      log "Clean: Xcode DerivedData freed ${xcode_size}MB" "INFO"
    fi
  fi

  # npm cache
  if command -v npm &>/dev/null; then
    npm cache clean --force &>/dev/null 2>&1 || true
    _clean_item "npm package cache" "cleared" "$(npm root -g 2>/dev/null || echo '')"
    log "Clean: npm cache cleared" "INFO"
  fi

  # pip/pip3 cache
  if command -v pip3 &>/dev/null; then
    pip3 cache purge &>/dev/null 2>&1 || true
    _clean_item "pip package cache" "cleared" ""
    log "Clean: pip cache cleared" "INFO"
  fi

  # Homebrew cache
  if command -v brew &>/dev/null; then
    local brew_freed
    brew_freed=$(brew cleanup --prune=7 2>/dev/null | grep "freed" | grep -oE '[0-9.]+[KMG]B' | tail -1 || echo "0MB")
    _clean_item "Homebrew packages" "$brew_freed" "cache + old versions"
    log "Clean: Homebrew freed ${brew_freed}" "INFO"
  fi

  # Gradle/Maven (if developer)
  local gradle_cache="$HOME/.gradle/caches"
  if [[ -d "$gradle_cache" ]]; then
    local gs
    gs=$(du -sm "$gradle_cache" 2>/dev/null | awk '{print $1}')
    if (( gs > 500 )); then
      find "$gradle_cache" -type d -name "*.lock" -delete 2>/dev/null || true
      _clean_item "Gradle build cache" "${gs}MB" "partial (lock files)"
    fi
  fi

  echo ""
  printf "  Total freed  ${C2}${B}~%.0fMB${R}\n\n" "$total_freed"
}

# ── DEEP CLEAN ──────────────────────────────────────────────────
cmd_deep_clean() {
  print_header
  printf "  ${C1}${B}Deep Clean${R}  ${D}— Extended system sweep${R}\n\n"

  # Run standard clean first
  local cache_dir="$HOME/Library/Caches"
  local log_dir="$HOME/Library/Logs"
  local total_freed=0

  printf "  ${D}Running standard cleanup...${R}\n"
  cmd_clean 2>/dev/null

  printf "  ${D}Extended sweep:${R}\n\n"

  # Safari caches
  local safari_cache="$HOME/Library/Caches/com.apple.Safari"
  if [[ -d "$safari_cache" ]]; then
    local sz; sz=$(du -sm "$safari_cache" 2>/dev/null | awk '{print $1}')
    rm -rf "${safari_cache:?}"/* 2>/dev/null || true
    printf "  ${C2}+${R}  %-28s ${D}Safari website cache${R}   ${C0}${B}~%sMB${R}\n" "Safari cache" "$sz"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $sz}")
  fi

  # Chrome caches
  local chrome_cache="$HOME/Library/Caches/Google/Chrome"
  if [[ -d "$chrome_cache" ]]; then
    local sz; sz=$(du -sm "$chrome_cache" 2>/dev/null | awk '{print $1}')
    find "$chrome_cache" -name "Cache" -type d -exec rm -rf {}/* \; 2>/dev/null || true
    printf "  ${C2}+${R}  %-28s ${D}Chrome cache${R}           ${C0}${B}~%sMB${R}\n" "Chrome cache" "$sz"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $sz}")
  fi

  # Firefox caches
  local ff_cache="$HOME/Library/Caches/Firefox"
  if [[ -d "$ff_cache" ]]; then
    local sz; sz=$(du -sm "$ff_cache" 2>/dev/null | awk '{print $1}')
    find "$ff_cache" -name "cache2" -type d -exec rm -rf {}/* \; 2>/dev/null || true
    printf "  ${C2}+${R}  %-28s ${D}Firefox cache${R}          ${C0}${B}~%sMB${R}\n" "Firefox cache" "$sz"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $sz}")
  fi

  # Mail attachments cache
  local mail_cache="$HOME/Library/Mail/V*/MailData/Attachments"
  local mail_sz
  mail_sz=$(du -sm $mail_cache 2>/dev/null | awk '{sum+=$1} END{print sum+0}')
  if (( mail_sz > 100 )); then
    printf "  ${C3}!${R}  %-28s ${D}Mail attachments (~%sMB)${R}  ${D}Manual review recommended${R}\n" \
      "Mail attachments" "$mail_sz"
  fi

  # ~/.DS_Store sweep
  local ds_count
  ds_count=$(find "$HOME" -name ".DS_Store" -maxdepth 6 2>/dev/null | wc -l | tr -d ' ')
  find "$HOME" -name ".DS_Store" -maxdepth 6 -delete 2>/dev/null || true
  printf "  ${C2}+${R}  %-28s ${D}Desktop metadata files${R}  ${C0}${B}%s files${R}\n" ".DS_Store files" "$ds_count"
  log "Deep clean: removed ${ds_count} .DS_Store files" "INFO"

  # Sleep image (if large)
  local sleep_img="/private/var/vm/sleepimage"
  if [[ -f "$sleep_img" ]] && sudo test -f "$sleep_img" 2>/dev/null; then
    local sz; sz=$(sudo du -sm "$sleep_img" 2>/dev/null | awk '{print $1}')
    printf "  ${C3}!${R}  %-28s ${D}Hibernation image${R}      ${C0}${B}~%sMB${R}  ${D}(sudo required to remove)${R}\n" \
      "Sleep image" "$sz"
  fi

  echo ""
  printf "  Extended total freed  ${C2}${B}~%.0fMB${R}\n\n" "$total_freed"
  log "Deep clean completed" "INFO"
}

# ── DNS FLUSH ───────────────────────────────────────────────────
cmd_dns_flush() {
  print_header
  printf "  ${C1}${B}DNS Cache Flush${R}\n\n"
  printf "  ${D}Flushing macOS DNS resolver cache...${R}\n"

  if sudo dscacheutil -flushcache 2>/dev/null && \
     sudo killall -HUP mDNSResponder 2>/dev/null; then
    printf "  ${C2}${B}Complete.${R}  DNS cache cleared and mDNSResponder reloaded.\n"
    log "DNS cache flushed" "INFO"
  else
    printf "  ${C3}Requires elevated privileges.${R}  Run: ${B}sudo perfguard dns-flush${R}\n"
  fi
  echo ""
}

# ── NETWORK DIAGNOSTICS ─────────────────────────────────────────
cmd_network() {
  print_header
  printf "  ${C1}${B}Network Diagnostics${R}\n\n"

  # Interface info
  printf "  ${D}Active interfaces:${R}\n"
  networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while read -r svc; do
    local ip
    ip=$(networksetup -getinfo "$svc" 2>/dev/null | awk '/^IP address:/{print $3}')
    [[ -n "$ip" && "$ip" != "none" ]] && \
      printf "  ${C7}  %-20s${R}  ${C0}%s${R}\n" "$svc" "$ip"
  done

  echo ""
  printf "  ${D}Connectivity tests:${R}\n"

  local tests=("8.8.8.8:Google DNS" "1.1.1.1:Cloudflare DNS" "apple.com:Apple")
  for t in "${tests[@]}"; do
    local host label
    host=$(echo "$t" | cut -d: -f1)
    label=$(echo "$t" | cut -d: -f2)
    if ping -c 1 -W 1000 "$host" &>/dev/null 2>&1; then
      local ms
      ms=$(ping -c 1 "$host" 2>/dev/null | awk -F'/' '/round-trip/{print $5}' || echo "?")
      printf "  ${C2}  %-20s${R}  ${D}%s ms${R}\n" "$label" "$ms"
    else
      printf "  ${C4}  %-20s${R}  ${D}unreachable${R}\n" "$label"
    fi
  done

  echo ""
  printf "  ${D}DNS resolve test (apple.com):${R}  "
  if dns_result=$(dscacheutil -q host -a name apple.com 2>/dev/null | awk '/ip_address/{print $2}' | head -1); then
    printf "${C2}%s${R}\n" "$dns_result"
  else
    printf "${C4}failed${R}\n"
  fi

  # Wi-Fi signal
  local wifi_signal
  wifi_signal=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/agrCtlRSSI/{print $2}')
  if [[ -n "$wifi_signal" ]]; then
    echo ""
    printf "  ${D}Wi-Fi signal strength:${R}  ${C0}${B}%s dBm${R}\n" "$wifi_signal"
  fi
  echo ""
}

# ── STARTUP SCAN ────────────────────────────────────────────────
cmd_startup_scan() {
  print_header
  printf "  ${C1}${B}Startup Items Scan${R}  ${D}— Items that launch on login${R}\n\n"

  local total=0

  # Login items
  printf "  ${D}Login Items:${R}\n"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | tr ',' '\n' | sed 's/^ //' | while read -r item; do
      [[ -z "$item" ]] && continue
      printf "  ${C7}  %s${R}\n" "$item"
      (( total++ )) || true
    done

  # LaunchAgents
  echo ""
  printf "  ${D}User Launch Agents:${R}\n"
  local agent_dir="$HOME/Library/LaunchAgents"
  if [[ -d "$agent_dir" ]]; then
    local count=0
    while IFS= read -r plist; do
      local name
      name=$(basename "$plist" .plist)
      local disabled
      disabled=$(defaults read "$plist" Disabled 2>/dev/null || echo "0")
      if [[ "$disabled" == "1" ]]; then
        printf "  ${D}  %-55s  disabled${R}\n" "$name"
      else
        printf "  ${C0}  %-55s  ${C2}active${R}\n" "$name"
      fi
      (( count++ )) || true
    done < <(find "$agent_dir" -name "*.plist" 2>/dev/null | sort)
    (( count == 0 )) && printf "  ${D}  none${R}\n"
  fi

  echo ""
  printf "  ${D}System Launch Daemons (user-installed):${R}\n"
  local daemon_dir="$HOME/Library/LaunchDaemons"
  if [[ -d "$daemon_dir" ]]; then
    local count=0
    while IFS= read -r plist; do
      printf "  ${C3}  %s${R}\n" "$(basename "$plist" .plist)"
      (( count++ )) || true
    done < <(find "$daemon_dir" -name "*.plist" 2>/dev/null | sort)
    (( count == 0 )) && printf "  ${D}  none${R}\n"
  fi
  echo ""
}

# ── MEMORY PRESSURE WATCH ────────────────────────────────────────
cmd_pressure_watch() {
  print_header
  printf "  ${C1}${B}Memory Pressure Watch${R}  ${D}— Live monitor (Ctrl+C to stop)${R}\n\n"

  local alert_threshold=80
  local interval=5

  while true; do
    IFS='|' read -r used_gb total_gb pressure <<< "$(get_ram_stats)"
    local pct; pct=$(awk "BEGIN{printf \"%.0f\", $pressure}")
    local ts; ts=$(date '+%H:%M:%S')
    local lc; lc=$(label_color "$pct")

    printf "\r  ${D}%s${R}  " "$ts"
    draw_bar "$pct" 100 30
    printf "  ${C0}${B}%s${R}${D}/%sGB${R}  ${lc}${B}%s%%${R}   " "$used_gb" "$total_gb" "$pct"

    if (( pct >= alert_threshold )); then
      printf "${C4}${B}PRESSURE ALERT${R}  "
      log "Memory pressure alert: ${pct}%" "WARN"
    fi

    sleep "$interval"
  done
}

# ── DISK USAGE BREAKDOWN ─────────────────────────────────────────
cmd_disk_usage() {
  print_header
  printf "  ${C1}${B}Disk Usage Breakdown${R}\n\n"

  local dirs=(
    "$HOME/Downloads:Downloads"
    "$HOME/Documents:Documents"
    "$HOME/Desktop:Desktop"
    "$HOME/Movies:Movies"
    "$HOME/Music:Music"
    "$HOME/Library/Caches:App Caches"
    "$HOME/Library/Application Support:App Data"
    "$HOME/.Trash:Trash"
  )

  local max_mb=1
  declare -A sizes
  for entry in "${dirs[@]}"; do
    local dir label
    dir=$(echo "$entry" | cut -d: -f1)
    label=$(echo "$entry" | cut -d: -f2)
    if [[ -d "$dir" ]]; then
      local sz; sz=$(du -sm "$dir" 2>/dev/null | awk '{print $1}')
      sizes["$label"]=$sz
      (( sz > max_mb )) && max_mb=$sz
    fi
  done

  for entry in "${dirs[@]}"; do
    local label
    label=$(echo "$entry" | cut -d: -f2)
    local sz="${sizes[$label]:-0}"
    printf "  ${D}%-22s${R}  " "$label"
    local bar_w=24
    local filled; filled=$(awk "BEGIN{printf \"%.0f\", $sz*$bar_w/$max_mb}")
    local color
    if   (( sz > 10000 )); then color=$C4
    elif (( sz > 2000  )); then color=$C3
    else                        color=$C2
    fi
    printf "${color}"
    for ((i=0; i<filled; i++)); do printf "▪"; done
    printf "${R}${D}"
    for ((i=filled; i<bar_w; i++)); do printf "·"; done
    printf "${R}  ${C0}${B}"
    if (( sz > 1024 )); then
      awk "BEGIN{printf \"%.1fGB\", $sz/1024}"
    else
      printf "%sMB" "$sz"
    fi
    printf "${R}\n"
  done

  echo ""
  printf "  ${D}Total disk:${R}  "
  df -h / | awk 'NR==2 {printf "%s used of %s (%s full)\n", $3, $2, $5}'
  echo ""
}

# ── SWAP INFO ───────────────────────────────────────────────────
cmd_swap_info() {
  print_header
  printf "  ${C1}${B}Swap & Virtual Memory${R}\n\n"

  local swapusage
  swapusage=$(sysctl -n vm.swapusage 2>/dev/null || echo "N/A")
  printf "  ${D}Swap:${R}   ${C0}%s${R}\n" "$swapusage"
  echo ""

  printf "  ${D}VM Statistics:${R}\n"
  vm_stat | grep -E "(free|active|inactive|wired|compressed|pageins|pageouts|swapins|swapouts)" \
    | while IFS= read -r line; do
      printf "  ${D}  %s${R}\n" "$line"
    done
  echo ""
}

# ── PROCESS MANAGER ─────────────────────────────────────────────
cmd_kill_unused() {
  load_whitelist
  print_header
  printf "  ${C1}${B}Process Manager${R}  ${D}— Unauthorized processes using >150MB${R}\n\n"

  local killed=0 flagged=0

  while IFS= read -r line; do
    local pid mem_kb name mem_mb
    pid=$(awk '{print $1}' <<< "$line")
    mem_kb=$(awk '{print $2}' <<< "$line")
    name=$(awk '{$1=$2=""; print $0}' <<< "$line" | xargs)
    mem_mb=$(awk "BEGIN{printf \"%.0f\", $mem_kb/1024}")

    (( mem_mb <= 150 )) && continue

    local approved; approved=$(is_approved "$name")
    if [[ "$approved" == "false" ]]; then
      printf "  ${C4}!${R}  ${B}%-40s${R}  ${D}%sMB  PID %s${R}\n" "$name" "$mem_mb" "$pid"
      read -rp "    Kill this process? [y/N] " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        kill -9 "$pid" 2>/dev/null && \
          printf "  ${C2}  Terminated.${R}\n" && \
          log "Killed: $name (PID $pid, ${mem_mb}MB)" "WARN" && \
          (( killed++ )) || true
      else
        (( flagged++ )) || true
      fi
    fi
  done < <(ps -axo pid,rss,comm | tail -n +2 | sort -k2 -rn | head -50)

  echo ""
  if (( killed == 0 && flagged == 0 )); then
    printf "  ${C2}${B}No unauthorized heavy processes found.${R}\n"
  else
    (( killed > 0 )) && printf "  Terminated   ${C4}${B}%d process(es)${R}\n" "$killed"
    (( flagged > 0 )) && printf "  Skipped      ${C3}${B}%d process(es)${R}\n" "$flagged"
  fi
  echo ""
}

# ── LIVE MONITOR ─────────────────────────────────────────────────
cmd_monitor() {
  load_whitelist
  local first_run=true

  while true; do
    IFS='|' read -r used_gb total_gb pressure <<< "$(get_ram_stats)"
    local cpu; cpu=$(get_cpu_usage)
    local ram_pct; ram_pct=$(awk "BEGIN{printf \"%.0f\", $pressure}")
    local cpu_pct; cpu_pct=$(awk "BEGIN{printf \"%.0f\", $cpu}")

    if [[ "$first_run" == "false" ]]; then
      tput cuu 28 2>/dev/null || true
    fi
    first_run=false

    printf "  ${C1}${B}PerfGuard${R}  ${D}Live Monitor  —  %s  —  Ctrl+C to exit${R}\n" "$(date '+%H:%M:%S')"
    printf "  "
    hr 62
    printf "  ${D}Memory${R}  "
    draw_bar "$ram_pct" 100 26
    printf "  ${C0}${B}%s${R}${D}/%sGB${R}    ${D}CPU${R}  "
    draw_bar "$cpu_pct" 100 16
    printf "  ${C0}${B}%s%%${R}\n\n" "$cpu_pct"

    printf "  ${D}%-7s  %-36s  %8s  %6s  %-12s${R}\n" "PID" "PROCESS" "MEM" "CPU%" "STATUS"
    printf "  ${D}"; hr 62 "─"; printf "${R}"

    local count=0
    while IFS= read -r line && (( count < 20 )); do
      local pid cpu_p mem_kb name mem_mb
      pid=$(awk '{print $1}' <<< "$line")
      cpu_p=$(awk '{print $2}' <<< "$line")
      mem_kb=$(awk '{print $3}' <<< "$line")
      name=$(awk '{$1=$2=$3=""; print $0}' <<< "$line" | xargs | cut -c1-36)
      mem_mb=$(awk "BEGIN{printf \"%.0f\", $mem_kb/1024}")

      local approved; approved=$(is_approved "$name")
      local sc sl
      if [[ "$approved" == "true" ]]; then sc=$C2; sl="approved"
      else sc=$C4; sl="unknown"; fi

      printf "  ${D}%-7s${R}  %-36s  ${C0}${B}%6sMB${R}  ${D}%5s%%${R}  ${sc}%-12s${R}\n" \
        "$pid" "$name" "$mem_mb" "$cpu_p" "$sl"
      (( count++ )) || true
    done < <(ps -axo pid,pcpu,rss,comm | tail -n +2 | sort -k3 -rn)

    sleep 3
  done
}

# ── TURBO MODE ───────────────────────────────────────────────────
cmd_turbo() {
  print_header
  printf "  ${C5}${B}Turbo Mode${R}  ${D}— Full system optimization sequence${R}\n\n"
  printf "  ${D}Executing: kill-unused → deep-clean → dns-flush → boost${R}\n\n"
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
  log "Turbo mode completed" "INFO"
}

# ── WHITELIST MANAGER ────────────────────────────────────────────
cmd_whitelist() {
  load_whitelist
  print_header
  printf "  ${C1}${B}Whitelist Manager${R}\n\n"

  printf "  ${D}Built-in approved processes (%d):${R}\n" "${#APPROVED_APPS[@]}"
  local col=0
  for app in "${APPROVED_APPS[@]}"; do
    printf "  ${D}%-24s${R}" "$app"
    (( col++ )) || true
    (( col % 3 == 0 )) && echo ""
  done
  echo ""

  if [[ -s "$WHITELIST_FILE" ]]; then
    echo ""
    printf "  ${D}User-added entries:${R}\n"
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf "  ${C2}+${R}  %s\n" "$line"
    done < "$WHITELIST_FILE"
  fi

  echo ""
  printf "  ${D}Add an entry:${R}  ${C0}echo 'AppName' >> ~/.perfguard/whitelist${R}\n\n"
}

# ── SCHEDULE ────────────────────────────────────────────────────
cmd_schedule() {
  print_header
  printf "  ${C1}${B}Auto-Cleanup Scheduler${R}\n\n"

  local script_path; script_path="$(command -v perfguard 2>/dev/null || echo "$0")"
  local schedules=(
    "*/30 * * * *:Every 30 minutes"
    "0 * * * *:Every hour"
    "0 3 * * *:Daily at 3:00 AM"
  )

  printf "  ${D}Choose schedule:${R}\n\n"
  for i in "${!schedules[@]}"; do
    local label; label=$(echo "${schedules[$i]}" | cut -d: -f2)
    printf "  ${C1}%d${R}  %s\n" "$((i+1))" "$label"
  done
  echo ""
  read -rp "  Select [1-3]: " choice

  local cron_expr
  case "$choice" in
    1) cron_expr="*/30 * * * *" ;;
    2) cron_expr="0 * * * *" ;;
    3) cron_expr="0 3 * * *" ;;
    *) printf "  ${C4}Invalid selection.${R}\n\n"; return ;;
  esac

  local cron_job="${cron_expr} ${script_path} clean >> ${LOG_FILE} 2>&1"
  ( crontab -l 2>/dev/null | grep -v "perfguard"; echo "$cron_job" ) | crontab -

  printf "  ${C2}${B}Scheduled.${R}  ${D}Cron entry added.${R}\n"
  printf "  ${D}To remove: ${R}crontab -e  ${D}and delete the perfguard line.${R}\n\n"
  log "Auto-cleanup scheduled: $cron_expr" "INFO"
}

# ── LOG VIEWER ───────────────────────────────────────────────────
cmd_log() {
  print_header
  printf "  ${C1}${B}Activity Log${R}  ${D}— last 40 entries${R}\n\n"
  if [[ -s "$LOG_FILE" ]]; then
    tail -40 "$LOG_FILE" | while IFS= read -r line; do
      local ts msg level
      ts=$(echo "$line" | awk '{print $1, $2}')
      level=$(echo "$line" | awk '{print $3}')
      msg=$(echo "$line" | cut -d']' -f3- | sed 's/^ //')
      local lc=$C7
      [[ "$level" == *"WARN"* ]] && lc=$C3
      [[ "$level" == *"ERROR"* ]] && lc=$C4
      printf "  ${D}%s${R}  ${lc}%s${R}\n" "$ts" "$msg"
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

    IFS='|' read -r used_gb total_gb pressure <<< "$(get_ram_stats)"
    local cpu; cpu=$(get_cpu_usage)
    local ram_pct; ram_pct=$(awk "BEGIN{printf \"%.0f\", $pressure}")
    local cpu_pct; cpu_pct=$(awk "BEGIN{printf \"%.0f\", $cpu}")
    local disk_info; disk_info=$(df -h / | awk 'NR==2 {print $3"/"$2}')

    printf "  ${D}Memory${R}  "
    draw_bar "$ram_pct" 100 22
    printf "  ${C0}${B}%s${R}${D}/%sGB${R}    " "$used_gb" "$total_gb"
    printf "${D}CPU${R}  "
    draw_bar "$cpu_pct" 100 14
    printf "  ${C0}${B}%s%%${R}    ${D}Disk${R} ${C0}${B}%s${R}\n\n" "$cpu_pct" "$disk_info"

    printf "  "; hr 54
    echo ""

    local items=(
      "1:status:System overview"
      "2:boost:RAM boost  ${D}(sudo)${R}"
      "3:clean:Cache cleanup"
      "4:deep-clean:Deep system sweep"
      "5:kill-unused:Process manager"
      "6:monitor:Live process monitor"
      "7:turbo:Full optimization sequence"
      "8:dns-flush:DNS cache flush"
      "9:network:Network diagnostics"
      "a:startup-scan:Startup items scan"
      "b:disk-usage:Disk usage breakdown"
      "c:swap-info:Swap & virtual memory"
      "d:pressure-watch:Memory pressure watch"
      "e:schedule:Schedule auto-cleanup"
      "f:whitelist:Manage process whitelist"
      "g:log:View activity log"
    )

    local i=0
    for item in "${items[@]}"; do
      local key label
      key=$(echo "$item" | cut -d: -f1)
      label=$(echo "$item" | cut -d: -f3-)
      printf "  ${C1}%-2s${R}  %b\n" "$key" "$label"
      (( i++ )) || true
      # Divider after core actions
      (( i == 7 )) && printf "\n  "; (( i == 7 )) && hr 40; (( i == 7 )) && echo ""
    done

    echo ""
    printf "  ${C4}q${R}  ${D}Quit${R}\n"
    echo ""
    printf "  "; hr 54
    printf "\n  ${D}→${R}  "
    read -rn1 choice
    echo ""

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
      a) cmd_startup_scan ;;
      b) cmd_disk_usage ;;
      c) cmd_swap_info ;;
      d) cmd_pressure_watch ;;
      e) cmd_schedule ;;
      f) cmd_whitelist ;;
      g) cmd_log ;;
      q|Q) echo ""; exit 0 ;;
      *) printf "\n  ${C3}Unknown option.${R}\n" ;;
    esac

    echo ""
    printf "  ${D}Press any key to return...${R}"
    read -rn1
    clear
  done
}

# ── HELP ────────────────────────────────────────────────────────
cmd_help() {
  print_header
  printf "  ${D}Usage:${R}  perfguard ${C1}[command]${R}\n\n"

  local cmds=(
    "menu          :Interactive menu (default)"
    "status        :RAM, CPU, disk, uptime overview"
    "boost         :Flush inactive memory pages  (sudo)"
    "clean         :Clear caches, temp files, build artifacts"
    "deep-clean    :Extended sweep: browsers, mail, .DS_Store"
    "kill-unused   :Interactive process termination"
    "monitor       :Live top-like process view"
    "turbo         :Full optimization sequence"
    "dns-flush     :Clear macOS DNS resolver cache"
    "network       :Interface info, ping, DNS diagnostics"
    "startup-scan  :Login items and launch agents audit"
    "disk-usage    :Per-folder disk usage breakdown"
    "swap-info     :Swap and virtual memory statistics"
    "pressure-watch:Live memory pressure alert monitor"
    "schedule      :Cron-based auto-cleanup configuration"
    "whitelist     :View and manage approved process list"
    "log           :Activity log viewer"
  )

  for cmd in "${cmds[@]}"; do
    local key val
    key=$(echo "$cmd" | cut -d: -f1)
    val=$(echo "$cmd" | cut -d: -f2)
    printf "  ${C1}%-16s${R}  ${D}%s${R}\n" "$key" "$val"
  done

  echo ""
  printf "  ${D}Whitelist:   ${R}echo 'AppName' >> ~/.perfguard/whitelist\n"
  printf "  ${D}Log file:    ${R}%s\n\n" "$LOG_FILE"
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
  *)              printf "\n  Unknown command. Run: ${B}perfguard help${R}\n\n" ;;
esac
