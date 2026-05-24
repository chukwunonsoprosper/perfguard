#!/usr/bin/env bash
# ================================================================
#  PerfGuard v2.2 — macOS System Performance Manager
#  https://github.com/chukwunonsoprosper/perfguard
# ================================================================

PERFGUARD_VERSION="2.2.0"
LOG_FILE="$HOME/.perfguard/perfguard.log"
WHITELIST_FILE="$HOME/.perfguard/whitelist"

# ── ANSI ────────────────────────────────────────────────────────
R="\033[0m"
B="\033[1m"
D="\033[2m"

# Palette — deep navy bg tones, electric accents
CW="\033[38;5;255m"   # pure white
CA="\033[38;5;45m"    # electric cyan/aqua
CG="\033[38;5;82m"    # neon green
CY="\033[38;5;220m"   # amber
CR="\033[38;5;196m"   # red alert
CV="\033[38;5;141m"   # soft violet
CO="\033[38;5;214m"   # orange
CS="\033[38;5;240m"   # slate/dim

# ── Bootstrap ───────────────────────────────────────────────────
bootstrap() {
  mkdir -p "$HOME/.perfguard"
  [ ! -f "$LOG_FILE" ]       && touch "$LOG_FILE"
  [ ! -f "$WHITELIST_FILE" ] && touch "$WHITELIST_FILE"
}

log() {
  printf "[%s] [%-5s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "${2:-INFO}" "$1" >> "$LOG_FILE"
}

# ── Whitelist ───────────────────────────────────────────────────
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
  [ -f "$WHITELIST_FILE" ] || return
  while IFS= read -r line; do
    [ -n "$line" ] && [ "${line:0:1}" != "#" ] && APPROVED_APPS+=("$line")
  done < "$WHITELIST_FILE"
}

is_approved() {
  local pname="$1" app
  for app in "${APPROVED_APPS[@]}"; do
    case "$pname" in *"$app"*) echo "true"; return ;; esac
    case "$app" in *"$pname"*) echo "true"; return ;; esac
  done
  echo "false"
}

# ── System Metrics ───────────────────────────────────────────────
get_ram_stats() {
  local total_bytes page_size free inactive
  total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 8589934592)
  page_size=$(vm_stat 2>/dev/null | awk '/page size/ {print $8+0}')
  [ -z "$page_size" ] || [ "$page_size" -eq 0 ] && page_size=16384
  free=$(vm_stat 2>/dev/null | awk '/^Pages free:/ {gsub(/\./,"",$3); print $3+0}')
  inactive=$(vm_stat 2>/dev/null | awk '/^Pages inactive:/ {gsub(/\./,"",$3); print $3+0}')
  [ -z "$free" ] && free=0
  [ -z "$inactive" ] && inactive=0
  local used_bytes
  used_bytes=$(( total_bytes - (free * page_size) - (inactive * page_size) ))
  local total_gb used_gb pressure
  total_gb=$(awk "BEGIN{printf \"%.1f\", $total_bytes/1073741824}")
  used_gb=$(awk  "BEGIN{printf \"%.1f\", $used_bytes/1073741824}")
  pressure=$(awk "BEGIN{printf \"%.0f\", $used_bytes*100/$total_bytes}")
  echo "${used_gb}|${total_gb}|${pressure}"
}

get_cpu_usage() {
  # BSD awk compatible — no match() capture groups
  top -l 2 -n 0 2>/dev/null | awk '
    /CPU usage/ { line = $0 }
    END {
      user = 0; sys = 0
      n = split(line, a, " ")
      for (i = 1; i <= n; i++) {
        val = a[i]+0
        if (a[i+1] == "user,") user = val
        if (a[i+1] == "sys,")  sys  = val
      }
      printf "%.0f", user + sys
    }
  ' || echo "0"
}

get_disk_stats() {
  df -h / 2>/dev/null | awk 'NR==2 {printf "%s|%s|%s", $3, $2, $5}' || echo "?|?|?"
}

get_battery() {
  pmset -g batt 2>/dev/null \
    | awk -F'[;%]' '/InternalBattery/ { gsub(/[^0-9]/,"",$2); if($2!="") print $2 }' \
    | head -1
}

get_swap() {
  sysctl -n vm.swapusage 2>/dev/null | awk '{print $4+0}' || echo "0"
}

# ── UI Primitives ───────────────────────────────────────────────
# Thick gradient bar using block characters
draw_bar() {
  local value="$1" max="${2:-100}" width="${3:-24}"
  local pct filled color
  pct=$(awk "BEGIN{ v=$value+0; m=$max+0; if(m<=0)m=1; r=int(v*100/m); if(r>100)r=100; if(r<0)r=0; print r }")
  filled=$(awk "BEGIN{ v=$value+0; m=$max+0; w=$width+0; if(m<=0)m=1; r=int(v*w/m); if(r>w)r=w; if(r<0)r=0; print r }")
  local empty=$(( width - filled ))

  if   [ "$pct" -lt 50 ] 2>/dev/null; then color=$CG
  elif [ "$pct" -lt 75 ] 2>/dev/null; then color=$CY
  else                                      color=$CR
  fi

  printf "${CS}▕${R}${color}"
  local i=0
  while [ $i -lt "$filled" ]; do printf "█"; i=$(( i + 1 )); done
  printf "${CS}"
  i=0
  while [ $i -lt "$empty" ]; do printf "░"; i=$(( i + 1 )); done
  printf "${CS}▏${R}"
}

# Top/bottom border lines
border_top() {
  local w="${1:-62}"
  printf "  ${CS}╔"
  local i=0; while [ $i -lt $w ]; do printf "═"; i=$(( i+1 )); done
  printf "╗${R}\n"
}
border_bot() {
  local w="${1:-62}"
  printf "  ${CS}╚"
  local i=0; while [ $i -lt $w ]; do printf "═"; i=$(( i+1 )); done
  printf "╝${R}\n"
}
border_mid() {
  local w="${1:-62}"
  printf "  ${CS}╠"
  local i=0; while [ $i -lt $w ]; do printf "═"; i=$(( i+1 )); done
  printf "╣${R}\n"
}
brow() {
  # Print a bordered row: brow "content string already formatted"
  printf "  ${CS}║${R}  %b${CS}║${R}\n" "$1"
}
brow_empty() {
  local w="${1:-62}"
  printf "  ${CS}║${R}"
  local i=0; while [ $i -lt $(( w + 2 )) ]; do printf " "; i=$(( i+1 )); done
  printf "${CS}║${R}\n"
}

thin_rule() {
  local w="${1:-58}"
  printf "  ${CS}╟"
  local i=0; while [ $i -lt $w ]; do printf "─"; i=$(( i+1 )); done
  printf "╢${R}\n"
}

pad_to() {
  # pad_to N "string" — pads string with spaces to N visible chars
  # (crude, ignores escape codes — use only for fixed-width labels)
  local n="$1" s="$2"
  printf "%s" "$s"
  local len=${#s}
  local pad=$(( n - len ))
  local i=0
  while [ $i -lt $pad ]; do printf " "; i=$(( i+1 )); done
}

# ── ASCII Header ─────────────────────────────────────────────────
print_banner() {
  printf "\n"
  printf "  ${CA}${B}██████╗ ███████╗██████╗ ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗ ██████╗${R}\n"
  printf "  ${CA}${B}██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝ ██║   ██║██╔══██╗██╔══██╗██╔══██╗${R}\n"
  printf "  ${CA}${B}██████╔╝█████╗  ██████╔╝█████╗  ██║  ███╗██║   ██║███████║██████╔╝██║  ██║${R}\n"
  printf "  ${CS}██╔═══╝ ██╔══╝  ██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██║██╔══██╗██║  ██║${R}\n"
  printf "  ${CS}██║     ███████╗██║  ██║██║     ╚██████╔╝╚██████╔╝██║  ██║██║  ██║██████╔╝${R}\n"
  printf "  ${CS}╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝${R}\n"
  printf "  ${CS}────────────────────────────────── ${CA}v%-6s${CS} ── macOS Performance Manager ──${R}\n\n" "$PERFGUARD_VERSION"
}

print_header() {
  printf "\n  ${CA}${B}PERFGUARD${R}  ${CS}v${PERFGUARD_VERSION}  ─────────────────────────────────────────────────${R}\n\n"
}

# ── STATUS ──────────────────────────────────────────────────────
cmd_status() {
  print_banner
  local used_gb total_gb ram_pct cpu disk_used disk_total disk_pct battery swap
  IFS='|' read -r used_gb total_gb ram_pct <<< "$(get_ram_stats)"
  cpu=$(get_cpu_usage)
  IFS='|' read -r disk_used disk_total disk_pct <<< "$(get_disk_stats)"
  battery=$(get_battery)
  swap=$(get_swap)

  local dp; dp=$(echo "$disk_pct" | tr -d '%'); [ -z "$dp" ] && dp=0

  local ram_lbl cpu_lbl bat_info
  if   [ "$ram_pct" -lt 50 ] 2>/dev/null; then ram_lbl="${CG}${B}HEALTHY${R}"
  elif [ "$ram_pct" -lt 75 ] 2>/dev/null; then ram_lbl="${CY}${B}MODERATE${R}"
  else                                          ram_lbl="${CR}${B}PRESSURE${R}"
  fi
  if   [ "${cpu:-0}" -lt 40 ] 2>/dev/null; then cpu_lbl="${CG}${B}IDLE${R}"
  elif [ "${cpu:-0}" -lt 70 ] 2>/dev/null; then cpu_lbl="${CY}${B}ACTIVE${R}"
  else                                          cpu_lbl="${CR}${B}HIGH LOAD${R}"
  fi
  [ -n "$battery" ] && bat_info="${battery}%" || bat_info="N/A"

  border_top 62
  brow "$(printf "${CS}  SYSTEM SNAPSHOT                        %s${R}" "$(date '+%a %d %b  %H:%M:%S')")"
  thin_rule 62
  brow_empty 62

  # RAM
  printf "  ${CS}║${R}  ${CS}RAM   ${R}  "
  draw_bar "$ram_pct" 100 28
  printf "  ${CW}${B}%5s${R}${CS}/%s GB${R}  %b" "$used_gb" "$total_gb" "$ram_lbl"
  printf "\n  ${CS}║${R}\n"

  # CPU
  printf "  ${CS}║${R}  ${CS}CPU   ${R}  "
  draw_bar "${cpu:-0}" 100 28
  printf "  ${CW}${B}%4s%%${R}           %b" "${cpu:-0}" "$cpu_lbl"
  printf "\n  ${CS}║${R}\n"

  # Disk
  printf "  ${CS}║${R}  ${CS}DISK  ${R}  "
  draw_bar "$dp" 100 28
  printf "  ${CW}${B}%5s${R}${CS}/%s${R}  ${CS}(%s)${R}" "$disk_used" "$disk_total" "$disk_pct"
  printf "\n"
  brow_empty 62

  thin_rule 62
  brow "$(printf "${CS}  BATTERY  ${CW}${B}%-8s${R}    ${CS}SWAP  ${CW}${B}%-8s${R}    ${CS}UPTIME  ${CW}${B}%s${R}" \
    "$bat_info" "${swap}MB" "$(uptime 2>/dev/null | awk -F'up ' '{print $2}' | cut -d',' -f1 | xargs)")"
  brow "$(printf "${CS}  PROCS    ${CW}${B}%-8s${R}" "$(ps ax 2>/dev/null | wc -l | tr -d ' ')")"
  brow_empty 62
  border_bot 62
  echo ""
}

# ── MENU ────────────────────────────────────────────────────────
cmd_menu() {
  while true; do
    clear

    # ── Live stats ──
    local used_gb total_gb ram_pct cpu disk_used disk_total disk_pct battery
    IFS='|' read -r used_gb total_gb ram_pct <<< "$(get_ram_stats)"
    cpu=$(get_cpu_usage)
    IFS='|' read -r disk_used disk_total disk_pct <<< "$(get_disk_stats)"
    battery=$(get_battery)
    local dp; dp=$(echo "$disk_pct" | tr -d '%'); [ -z "$dp" ] && dp=0
    local bat_info; [ -n "$battery" ] && bat_info="${battery}%" || bat_info="--"

    # ── Banner ──
    print_banner

    # ── Stats bar ──
    border_top 62
    brow "$(printf "${CS}  ◈ RAM   ${R}"; draw_bar "$ram_pct" 100 18; printf "  ${CW}${B}%s${R}${CS}/%sGB  ${R}${CS}◈ CPU  ${R}"; draw_bar "${cpu:-0}" 100 10; printf "  ${CW}${B}%s%%${R}" "${cpu:-0}")"
    brow "$(printf "${CS}  ◈ DISK  ${R}"; draw_bar "$dp" 100 18;     printf "  ${CW}${B}%s${R}${CS}/%s    ${R}${CS}◈ BATT ${CW}${B}%s${R}" "$disk_used" "$disk_total" "$bat_info")"
    border_mid 62

    # ── Menu items ──
    brow "$(printf "${CS}  ┌─ PERFORMANCE ─────────────────────────────────────────┐${R}")"
    brow "$(printf "  ${CS}│${R}  ${CA}${B} 1 ${R}  ${CW}System overview     ${CS}│${R}  ${CA}${B} 2 ${R}  ${CW}RAM boost  ${CS}(sudo)${R}     ${CS}│${R}")"
    brow "$(printf "  ${CS}│${R}  ${CA}${B} 3 ${R}  ${CW}Cache cleanup       ${CS}│${R}  ${CA}${B} 4 ${R}  ${CW}Deep system sweep  ${CS}│${R}")"
    brow "$(printf "  ${CS}│${R}  ${CA}${B} 5 ${R}  ${CW}Process manager     ${CS}│${R}  ${CA}${B} 6 ${R}  ${CW}Live monitor       ${CS}│${R}")"
    brow "$(printf "  ${CS}│${R}  ${CA}${B} 7 ${R}  ${CW}Full turbo sequence ${CS}│${R}                               ${CS}│${R}")"
    brow "$(printf "${CS}  └───────────────────────────────────────────────────────┘${R}")"
    brow_empty 62
    brow "$(printf "${CS}  ┌─ SYSTEM & DIAGNOSTICS ────────────────────────────────┐${R}")"
    brow "$(printf "  ${CS}│${R}  ${CV}${B} 8 ${R}  ${CW}DNS flush           ${CS}│${R}  ${CV}${B} 9 ${R}  ${CW}Network info       ${CS}│${R}")"
    brow "$(printf "  ${CS}│${R}  ${CV}${B} a ${R}  ${CW}Startup scan        ${CS}│${R}  ${CV}${B} b ${R}  ${CW}Disk breakdown     ${CS}│${R}")"
    brow "$(printf "  ${CS}│${R}  ${CV}${B} c ${R}  ${CW}Swap & VM info      ${CS}│${R}  ${CV}${B} d ${R}  ${CW}Pressure watch     ${CS}│${R}")"
    brow "$(printf "${CS}  └───────────────────────────────────────────────────────┘${R}")"
    brow_empty 62
    brow "$(printf "${CS}  ┌─ TOOLS ───────────────────────────────────────────────┐${R}")"
    brow "$(printf "  ${CS}│${R}  ${CO}${B} e ${R}  ${CW}Schedule cleanup    ${CS}│${R}  ${CO}${B} f ${R}  ${CW}Whitelist          ${CS}│${R}")"
    brow "$(printf "  ${CS}│${R}  ${CO}${B} g ${R}  ${CW}Activity log        ${CS}│${R}  ${CR}${B} q ${R}  ${CW}Quit               ${CS}│${R}")"
    brow "$(printf "${CS}  └───────────────────────────────────────────────────────┘${R}")"
    brow_empty 62

    border_bot 62
    printf "\n  ${CS}▶${R}  ${CW}${B}Enter option: ${R}"
    local choice
    read -r choice
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
      a|A) cmd_startup_scan ;;
      b|B) cmd_disk_usage ;;
      c|C) cmd_swap_info ;;
      d|D) cmd_pressure_watch ;;
      e|E) cmd_schedule ;;
      f|F) cmd_whitelist ;;
      g|G) cmd_log ;;
      q|Q) printf "  ${CS}Goodbye.${R}\n\n"; exit 0 ;;
      *) printf "  ${CY}Unknown option.${R}\n" ;;
    esac

    printf "\n  ${CS}▶  Press Enter to return...${R}"
    read -r
    clear
  done
}

# ── RAM BOOST ───────────────────────────────────────────────────
cmd_boost() {
  print_header
  printf "  ${CA}${B}RAM BOOST${R}\n"
  printf "  ${CS}Reclaiming inactive memory pages via purge...${R}\n\n"
  local used_before; IFS='|' read -r used_before _ _ <<< "$(get_ram_stats)"
  if sudo purge 2>/dev/null; then
    sleep 2
    local used_after _r _p; IFS='|' read -r used_after _r _p <<< "$(get_ram_stats)"
    local freed; freed=$(awk "BEGIN{printf \"%.1f\", $used_before - $used_after}")
    printf "  Before  ${CW}${B}%sGB${R}  →  After  ${CW}${B}%sGB${R}\n" "$used_before" "$used_after"
    printf "  Reclaimed  ${CG}${B}~%sGB${R}\n\n" "$freed"
    printf "  ${CG}${B}▶  COMPLETE${R}\n\n"
    log "RAM Boost: reclaimed ~${freed}GB"
  else
    printf "  ${CY}Requires sudo.${R}  Run: ${B}sudo perfguard boost${R}\n\n"
  fi
}

# ── CLEAN ───────────────────────────────────────────────────────
cmd_clean() {
  print_header
  printf "  ${CA}${B}CACHE CLEANUP${R}\n\n"
  local total_freed=0

  _crow() { printf "  ${CG}▸${R}  %-28s ${CS}%s${R}  ${CW}${B}%s${R}\n" "$1" "$2" "$3"; }

  local cache_dir="$HOME/Library/Caches"
  if [ -d "$cache_dir" ]; then
    local sb sa fk fm
    sb=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1+0}')
    find "$cache_dir" -mindepth 1 -maxdepth 2 -type f -mtime +1 -delete 2>/dev/null
    sa=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1+0}')
    fk=$(( ${sb:-0} - ${sa:-0} )); fm=$(awk "BEGIN{printf \"%.1fMB\", $fk/1024}")
    _crow "User app caches" "~/Library/Caches" "$fm"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $fk/1024}")
    log "Clean: user caches freed ${fm}"
  fi

  local log_dir="$HOME/Library/Logs"
  if [ -d "$log_dir" ]; then
    local sb sa fk fm
    sb=$(du -sk "$log_dir" 2>/dev/null | awk '{print $1+0}')
    find "$log_dir" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +7 -delete 2>/dev/null
    sa=$(du -sk "$log_dir" 2>/dev/null | awk '{print $1+0}')
    fk=$(( ${sb:-0} - ${sa:-0} )); fm=$(awk "BEGIN{printf \"%.1fMB\", $fk/1024}")
    _crow "Old log files" "~/Library/Logs >7d" "$fm"
    total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + $fk/1024}")
  fi

  local tmp_count
  tmp_count=$(find "$TMPDIR" -maxdepth 1 -type f -mtime +0 2>/dev/null | wc -l | tr -d ' ')
  find "$TMPDIR" -maxdepth 1 -type f -mtime +0 -delete 2>/dev/null
  _crow "Temp files" "\$TMPDIR" "${tmp_count} files"
  log "Clean: removed ${tmp_count} temp files"

  local crash_dir="$HOME/Library/Logs/DiagnosticReports"
  if [ -d "$crash_dir" ]; then
    local cnt; cnt=$(find "$crash_dir" -type f -mtime +14 2>/dev/null | wc -l | tr -d ' ')
    find "$crash_dir" -type f -mtime +14 -delete 2>/dev/null
    _crow "Crash reports" "DiagnosticReports >14d" "${cnt} files"
  fi

  local xcode_dd="$HOME/Library/Developer/Xcode/DerivedData"
  if [ -d "$xcode_dd" ]; then
    local xsz; xsz=$(du -sm "$xcode_dd" 2>/dev/null | awk '{print $1+0}')
    if [ "${xsz:-0}" -gt 200 ] 2>/dev/null; then
      rm -rf "${xcode_dd:?}"/* 2>/dev/null
      _crow "Xcode DerivedData" "Build artifacts" "${xsz}MB"
      total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + ${xsz:-0}}")
      log "Clean: Xcode freed ${xsz}MB"
    fi
  fi

  command -v npm  >/dev/null 2>&1 && npm cache clean --force >/dev/null 2>&1 && _crow "npm cache" "" "cleared" && log "Clean: npm"
  command -v pip3 >/dev/null 2>&1 && pip3 cache purge >/dev/null 2>&1 && _crow "pip cache" "" "cleared" && log "Clean: pip"
  if command -v brew >/dev/null 2>&1; then
    local bout; bout=$(brew cleanup --prune=7 2>/dev/null | grep -E "freed|Removed" | tail -1 || echo "done")
    _crow "Homebrew cache" "old versions" "$bout"
  fi

  echo ""
  printf "  ${CS}────────────────────────────────────${R}\n"
  printf "  Total freed  ${CG}${B}~%.0f MB${R}\n\n" "$total_freed"
}

# ── DEEP CLEAN ──────────────────────────────────────────────────
cmd_deep_clean() {
  print_header
  printf "  ${CA}${B}DEEP CLEAN${R}  ${CS}— Extended system sweep${R}\n\n"
  local total_freed=0
  _drow() { printf "  ${CG}▸${R}  %-28s ${CS}%s${R}  ${CW}${B}%s${R}\n" "$1" "$2" "$3"; }

  for browser_cache in \
    "$HOME/Library/Caches/com.apple.Safari:Safari cache" \
    "$HOME/Library/Caches/Google/Chrome:Chrome cache" \
    "$HOME/Library/Caches/Firefox:Firefox cache"
  do
    local dir lbl sz
    dir=$(echo "$browser_cache" | cut -d: -f1)
    lbl=$(echo "$browser_cache" | cut -d: -f2)
    if [ -d "$dir" ]; then
      sz=$(du -sm "$dir" 2>/dev/null | awk '{print $1+0}')
      find "$dir" \( -name "Cache" -o -name "cache2" \) -type d 2>/dev/null | \
        while read -r d; do rm -rf "${d:?}"/* 2>/dev/null; done
      rm -rf "${dir:?}"/* 2>/dev/null
      _drow "$lbl" "Website data" "~${sz}MB"
      total_freed=$(awk "BEGIN{printf \"%.1f\", $total_freed + ${sz:-0}}")
    fi
  done

  local ds_count
  ds_count=$(find "$HOME" -name ".DS_Store" -maxdepth 6 2>/dev/null | wc -l | tr -d ' ')
  find "$HOME" -name ".DS_Store" -maxdepth 6 -delete 2>/dev/null
  _drow ".DS_Store files" "Desktop metadata" "${ds_count} files"
  log "Deep: removed ${ds_count} .DS_Store files"

  local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
  if [ -d "$backup_dir" ]; then
    local bsz; bsz=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
    printf "  ${CY}!${R}  %-28s ${CS}Review in Finder${R}  ${CW}${B}%s${R}\n" "iOS backups (manual)" "${bsz:-0B}"
  fi

  echo ""
  printf "  ${CS}────────────────────────────────────${R}\n"
  printf "  Extended freed  ${CG}${B}~%.0f MB${R}\n\n" "$total_freed"
  log "Deep clean completed"
}

# ── DNS FLUSH ───────────────────────────────────────────────────
cmd_dns_flush() {
  print_header
  printf "  ${CA}${B}DNS CACHE FLUSH${R}\n\n"
  printf "  ${CS}Flushing resolver cache and restarting mDNSResponder...${R}\n"
  if sudo dscacheutil -flushcache 2>/dev/null && sudo killall -HUP mDNSResponder 2>/dev/null; then
    printf "  ${CG}${B}▶  COMPLETE${R}  DNS cache cleared.\n\n"
    log "DNS cache flushed"
  else
    printf "  ${CY}Requires sudo.${R}  Run: ${B}sudo perfguard dns-flush${R}\n\n"
  fi
}

# ── NETWORK ─────────────────────────────────────────────────────
cmd_network() {
  print_header
  printf "  ${CA}${B}NETWORK DIAGNOSTICS${R}\n\n"

  printf "  ${CS}Active interfaces:${R}\n"
  networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r svc; do
    local ip; ip=$(networksetup -getinfo "$svc" 2>/dev/null | awk '/^IP address:/{print $3}')
    [ -n "$ip" ] && [ "$ip" != "none" ] && \
      printf "  ${CA}  %-24s${R}  ${CW}%s${R}\n" "$svc" "$ip"
  done

  echo ""
  printf "  ${CS}Connectivity:${R}\n"
  for t in "8.8.8.8:Google DNS" "1.1.1.1:Cloudflare" "apple.com:Apple"; do
    local h l ms
    h=$(echo "$t" | cut -d: -f1); l=$(echo "$t" | cut -d: -f2)
    if ping -c 1 -W 1000 "$h" >/dev/null 2>&1; then
      ms=$(ping -c 1 "$h" 2>/dev/null | awk -F'/' '/round-trip/{printf "%.1f", $5}')
      printf "  ${CG}  ◈ %-18s${R}  ${CS}%s ms${R}\n" "$l" "${ms:-?}"
    else
      printf "  ${CR}  ✗ %-18s${R}  ${CS}unreachable${R}\n" "$l"
    fi
  done

  local wifi_signal
  wifi_signal=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/agrCtlRSSI/{print $2}')
  [ -n "$wifi_signal" ] && printf "\n  ${CS}Wi-Fi signal:${R}  ${CW}${B}%s dBm${R}\n" "$wifi_signal"
  echo ""
}

# ── STARTUP SCAN ────────────────────────────────────────────────
cmd_startup_scan() {
  print_header
  printf "  ${CA}${B}STARTUP ITEMS SCAN${R}\n\n"

  printf "  ${CS}Login Items:${R}\n"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | tr ',' '\n' | sed 's/^ //' | while IFS= read -r item; do
      [ -z "$item" ] && continue
      printf "  ${CA}  ◈ %s${R}\n" "$item"
    done

  echo ""
  printf "  ${CS}User Launch Agents:${R}\n"
  local agent_dir="$HOME/Library/LaunchAgents"
  if [ -d "$agent_dir" ]; then
    local found=0
    for plist in "$agent_dir"/*.plist; do
      [ -f "$plist" ] || continue
      local name dis
      name=$(basename "$plist" .plist)
      dis=$(defaults read "$plist" Disabled 2>/dev/null || echo "0")
      if [ "$dis" = "1" ]; then
        printf "  ${CS}  ◌ %-55s  disabled${R}\n" "$name"
      else
        printf "  ${CW}  ◈ %-55s  ${CG}active${R}\n" "$name"
      fi
      found=1
    done
    [ "$found" = "0" ] && printf "  ${CS}  none${R}\n"
  fi
  echo ""
}

# ── DISK USAGE ──────────────────────────────────────────────────
cmd_disk_usage() {
  print_header
  printf "  ${CA}${B}DISK USAGE BREAKDOWN${R}\n\n"

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

  declare -a labels sizes_arr
  local max_mb=1
  for entry in "${entries[@]}"; do
    local dir lbl sz
    dir=$(echo "$entry" | cut -d: -f1); lbl=$(echo "$entry" | cut -d: -f2)
    [ -d "$dir" ] && sz=$(du -sm "$dir" 2>/dev/null | awk '{print $1+0}') || sz=0
    labels+=("$lbl"); sizes_arr+=("$sz")
    [ "$sz" -gt "$max_mb" ] 2>/dev/null && max_mb=$sz
  done

  local idx=0
  for lbl in "${labels[@]}"; do
    local sz="${sizes_arr[$idx]}"; idx=$(( idx+1 ))
    printf "  ${CS}%-20s${R}  " "$lbl"
    local bw=26 filled
    filled=$(awk "BEGIN{r=int($sz*$bw/$max_mb); if(r>$bw)r=$bw; print r}")
    local col
    if   [ "$sz" -gt 10000 ] 2>/dev/null; then col=$CR
    elif [ "$sz" -gt 2000  ] 2>/dev/null; then col=$CY
    else                                        col=$CG
    fi
    printf "${col}"
    local i=0; while [ $i -lt "$filled" ]; do printf "█"; i=$(( i+1 )); done
    printf "${CS}"; i=$filled; while [ $i -lt $bw ]; do printf "░"; i=$(( i+1 )); done
    printf "${R}  ${CW}${B}"
    [ "$sz" -gt 1024 ] 2>/dev/null && awk "BEGIN{printf \"%.1f GB\", $sz/1024}" || printf "%s MB" "$sz"
    printf "${R}\n"
  done

  echo ""
  printf "  ${CS}Total disk:${R}  "
  df -h / 2>/dev/null | awk 'NR==2 {printf "%s used of %s (%s)\n", $3, $2, $5}'
  echo ""
}

# ── SWAP INFO ───────────────────────────────────────────────────
cmd_swap_info() {
  print_header
  printf "  ${CA}${B}SWAP & VIRTUAL MEMORY${R}\n\n"
  printf "  ${CS}Swap:${R}  ${CW}%s${R}\n\n" "$(sysctl -n vm.swapusage 2>/dev/null || echo 'N/A')"
  printf "  ${CS}VM Statistics:${R}\n"
  vm_stat 2>/dev/null | grep -E "(free|active|inactive|wired|compressed|pageins|pageouts|swapins|swapouts)" \
    | while IFS= read -r line; do printf "  ${CS}  %s${R}\n" "$line"; done
  echo ""
}

# ── PRESSURE WATCH ──────────────────────────────────────────────
cmd_pressure_watch() {
  print_header
  printf "  ${CA}${B}MEMORY PRESSURE WATCH${R}  ${CS}Ctrl+C to stop${R}\n\n"
  local threshold=80
  while true; do
    local ug tg pct; IFS='|' read -r ug tg pct <<< "$(get_ram_stats)"
    local ts; ts=$(date '+%H:%M:%S')
    printf "\r  ${CS}%s${R}  " "$ts"
    draw_bar "$pct" 100 32
    printf "  ${CW}${B}%s${R}${CS}/%sGB${R}  " "$ug" "$tg"
    if [ "${pct:-0}" -ge "$threshold" ] 2>/dev/null; then
      printf "${CR}${B}%s%%  ─  PRESSURE ALERT${R}   " "$pct"
      log "Memory pressure: ${pct}%" "WARN"
    else
      printf "${CG}${B}%s%%${R}   " "$pct"
    fi
    sleep 5
  done
}

# ── PROCESS MANAGER ─────────────────────────────────────────────
cmd_kill_unused() {
  load_whitelist
  print_header
  printf "  ${CA}${B}PROCESS MANAGER${R}  ${CS}Unauthorized processes >150MB${R}\n\n"
  local killed=0 found=0

  while IFS= read -r line; do
    local pid mem_kb name mem_mb
    pid=$(echo "$line" | awk '{print $1}')
    mem_kb=$(echo "$line" | awk '{print $2}')
    name=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
    mem_mb=$(awk "BEGIN{printf \"%.0f\", ${mem_kb:-0}/1024}")
    [ "${mem_mb:-0}" -le 150 ] 2>/dev/null && continue
    [ "$(is_approved "$name")" = "true" ] && continue

    found=1
    printf "  ${CR}▶${R}  ${B}%-40s${R}  ${CS}%sMB  PID %s${R}\n" "$name" "$mem_mb" "$pid"
    printf "     Kill? [y/N] "
    local c; read -r c
    if [ "$c" = "y" ] || [ "$c" = "Y" ]; then
      kill -9 "$pid" 2>/dev/null && printf "  ${CG}  Terminated.${R}\n" \
        && log "Killed: $name (PID $pid, ${mem_mb}MB)" "WARN" \
        && killed=$(( killed + 1 ))
    fi
  done < <(ps -axo pid,rss,comm 2>/dev/null | tail -n +2 | sort -k2 -rn | head -50)

  echo ""
  if [ "$found" = "0" ]; then
    printf "  ${CG}${B}▶  No unauthorized heavy processes found.${R}\n"
  else
    [ "$killed" -gt 0 ] && printf "  ${CR}${B}Terminated: %d process(es)${R}\n" "$killed"
  fi
  echo ""
}

# ── LIVE MONITOR ─────────────────────────────────────────────────
cmd_monitor() {
  load_whitelist
  local first="true"
  while true; do
    local ug tg pct cpu rp cp
    IFS='|' read -r ug tg pct <<< "$(get_ram_stats)"
    cpu=$(get_cpu_usage)
    rp=$(awk "BEGIN{printf \"%.0f\", $pct+0}")
    cp=$(awk "BEGIN{printf \"%.0f\", ${cpu:-0}+0}")

    [ "$first" = "false" ] && tput cuu 30 2>/dev/null
    first="false"

    printf "  ${CA}${B}PERFGUARD${R}  ${CS}Live Monitor  ─  %s  ─  Ctrl+C to exit${R}\n" "$(date '+%H:%M:%S')"
    printf "  ${CS}"; local i=0; while [ $i -lt 62 ]; do printf "─"; i=$(( i+1 )); done; printf "${R}\n"
    printf "  ${CS}RAM  ${R}"; draw_bar "$rp" 100 24; printf "  ${CW}${B}%s${R}${CS}/%sGB  ${R}${CS}CPU  ${R}"; draw_bar "$cp" 100 14; printf "  ${CW}${B}%s%%${R}\n\n" "$cp"

    printf "  ${CS}%-7s  %-36s  %8s  %6s  %-10s${R}\n" "PID" "PROCESS" "MEM" "CPU%" "STATUS"
    printf "  ${CS}"; i=0; while [ $i -lt 62 ]; do printf "─"; i=$(( i+1 )); done; printf "${R}\n"

    local count=0
    while IFS= read -r ln && [ "$count" -lt 22 ]; do
      local pid cp2 mk nm mb sc sl
      pid=$(echo "$ln" | awk '{print $1}')
      cp2=$(echo "$ln" | awk '{print $2}')
      mk=$(echo "$ln" | awk '{print $3}')
      nm=$(echo "$ln" | awk '{$1=$2=$3=""; print $0}' | xargs | cut -c1-36)
      mb=$(awk "BEGIN{printf \"%.0f\", ${mk:-0}/1024}")
      if [ "$(is_approved "$nm")" = "true" ]; then sc=$CG; sl="approved"
      else sc=$CR; sl="unknown"; fi
      printf "  ${CS}%-7s${R}  %-36s  ${CW}${B}%6sMB${R}  ${CS}%5s%%${R}  ${sc}%-10s${R}\n" \
        "$pid" "$nm" "$mb" "$cp2" "$sl"
      count=$(( count + 1 ))
    done < <(ps -axo pid,pcpu,rss,comm 2>/dev/null | tail -n +2 | sort -k3 -rn)
    sleep 3
  done
}

# ── TURBO ───────────────────────────────────────────────────────
cmd_turbo() {
  print_header
  printf "  ${CV}${B}TURBO MODE${R}  ${CS}Full optimization sequence${R}\n\n"
  printf "  ${CS}kill-unused → deep-clean → dns-flush → boost${R}\n\n"
  local i=0; while [ $i -lt 62 ]; do printf "${CS}═${R}"; i=$(( i+1 )); done; echo ""
  echo ""
  cmd_kill_unused; echo ""
  local i=0; while [ $i -lt 62 ]; do printf "${CS}─${R}"; i=$(( i+1 )); done; echo ""
  echo ""
  cmd_deep_clean; echo ""
  local i=0; while [ $i -lt 62 ]; do printf "${CS}─${R}"; i=$(( i+1 )); done; echo ""
  echo ""
  cmd_dns_flush; echo ""
  local i=0; while [ $i -lt 62 ]; do printf "${CS}─${R}"; i=$(( i+1 )); done; echo ""
  echo ""
  cmd_boost
  printf "  ${CG}${B}▶  ALL OPTIMIZATIONS COMPLETE${R}\n\n"
  log "Turbo mode completed"
}

# ── WHITELIST ───────────────────────────────────────────────────
cmd_whitelist() {
  load_whitelist
  print_header
  printf "  ${CA}${B}WHITELIST MANAGER${R}  ${CS}%d built-in entries${R}\n\n" "${#APPROVED_APPS[@]}"
  local col=0 app
  for app in "${APPROVED_APPS[@]}"; do
    printf "  ${CS}%-24s${R}" "$app"
    col=$(( col + 1 ))
    [ $(( col % 3 )) -eq 0 ] && echo ""
  done
  echo ""
  if [ -s "$WHITELIST_FILE" ]; then
    echo ""
    printf "  ${CS}User additions:${R}\n"
    while IFS= read -r line; do
      [ -n "$line" ] && printf "  ${CG}▸  %s${R}\n" "$line"
    done < "$WHITELIST_FILE"
  fi
  echo ""
  printf "  ${CS}Add:  ${R}echo 'AppName' >> ~/.perfguard/whitelist\n\n"
}

# ── SCHEDULE ────────────────────────────────────────────────────
cmd_schedule() {
  print_header
  printf "  ${CA}${B}AUTO-CLEANUP SCHEDULER${R}\n\n"
  local sp; sp=$(command -v perfguard 2>/dev/null || echo "$0")
  printf "  ${CS}Choose schedule:${R}\n\n"
  printf "  ${CA}1${R}  Every 30 minutes\n"
  printf "  ${CA}2${R}  Every hour\n"
  printf "  ${CA}3${R}  Daily at 3:00 AM\n\n"
  printf "  Select [1-3]: "
  local c; read -r c
  local cron_expr
  case "$c" in
    1) cron_expr="*/30 * * * *" ;;
    2) cron_expr="0 * * * *" ;;
    3) cron_expr="0 3 * * *" ;;
    *) printf "  ${CY}Invalid.${R}\n\n"; return ;;
  esac
  ( crontab -l 2>/dev/null | grep -v "perfguard"; echo "${cron_expr} ${sp} clean >> ${LOG_FILE} 2>&1" ) | crontab -
  printf "  ${CG}${B}▶  SCHEDULED${R}  ${CS}Cron entry added.${R}\n\n"
  log "Auto-cleanup scheduled: $cron_expr"
}

# ── LOG ─────────────────────────────────────────────────────────
cmd_log() {
  print_header
  printf "  ${CA}${B}ACTIVITY LOG${R}  ${CS}last 40 entries${R}\n\n"
  if [ -s "$LOG_FILE" ]; then
    tail -40 "$LOG_FILE" | while IFS= read -r line; do
      local lc=$CS
      echo "$line" | grep -q "WARN"  && lc=$CY
      echo "$line" | grep -q "ERROR" && lc=$CR
      printf "  ${lc}%s${R}\n" "$line"
    done
  else
    printf "  ${CS}No entries yet.${R}\n"
  fi
  echo ""
}

# ── HELP ────────────────────────────────────────────────────────
cmd_help() {
  print_header
  printf "  ${CS}Usage:${R}  perfguard ${CA}[command]${R}\n\n"
  local cmds=(
    "menu:Interactive menu (default)"
    "status:System snapshot — RAM, CPU, disk, battery"
    "boost:Flush inactive memory pages  (sudo)"
    "clean:Clear caches, temp, build artifacts"
    "deep-clean:Extended sweep — browsers, .DS_Store"
    "kill-unused:Interactive unauthorized process manager"
    "monitor:Live process monitor"
    "turbo:Full optimization sequence"
    "dns-flush:Flush macOS DNS resolver cache"
    "network:Interface, ping, Wi-Fi diagnostics"
    "startup-scan:Login items and launch agents audit"
    "disk-usage:Per-folder disk usage breakdown"
    "swap-info:Swap and virtual memory statistics"
    "pressure-watch:Live memory pressure alert"
    "schedule:Cron-based auto-cleanup setup"
    "whitelist:View and manage approved processes"
    "log:Activity log viewer"
    "version:Print version"
  )
  for cmd in "${cmds[@]}"; do
    local k v
    k=$(echo "$cmd" | cut -d: -f1)
    v=$(echo "$cmd" | cut -d: -f2)
    printf "  ${CA}%-18s${R}  ${CS}%s${R}\n" "$k" "$v"
  done
  echo ""
  printf "  ${CS}Config:${R}  ~/.perfguard/\n"
  printf "  ${CS}Log:${R}     %s\n\n" "$LOG_FILE"
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
  *) printf "\n  Unknown command. Run: perfguard help\n\n" ;;
esac