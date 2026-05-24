#!/usr/bin/env bash
# ================================================================
#  PerfGuard v2.3 — macOS System Performance Manager
#  https://github.com/chukwunonsoprosper/perfguard
# ================================================================

PERFGUARD_VERSION="2.3.0"
LOG_FILE="$HOME/.perfguard/perfguard.log"
WHITELIST_FILE="$HOME/.perfguard/whitelist"

# ── ANSI ────────────────────────────────────────────────────────
R="\033[0m"
B="\033[1m"
D="\033[2m"
CW="\033[38;5;255m"
CA="\033[38;5;45m"
CG="\033[38;5;82m"
CY="\033[38;5;220m"
CR="\033[38;5;196m"
CV="\033[38;5;141m"
CO="\033[38;5;214m"
CS="\033[38;5;240m"

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
  local used_bytes=$(( total_bytes - (free * page_size) - (inactive * page_size) ))
  echo "$(awk "BEGIN{printf \"%.1f\", $used_bytes/1073741824}")|$(awk "BEGIN{printf \"%.1f\", $total_bytes/1073741824}")|$(awk "BEGIN{printf \"%.0f\", $used_bytes*100/$total_bytes}")"
}

get_cpu_usage() {
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
  # Use /usr/bin/head explicitly to avoid Perl head collision
  pmset -g batt 2>/dev/null \
    | awk -F'[;%]' '/InternalBattery/ { gsub(/[^0-9]/,"",$2); if($2!="") print $2 }' \
    | /usr/bin/head -1
}

get_swap() {
  sysctl -n vm.swapusage 2>/dev/null | awk '{
    for(i=1;i<=NF;i++) if($i~/^[0-9]/ && $(i-1)~/used/) { printf "%.0f", $i+0; exit }
  }' || echo "0"
}

# ── Draw bar — no brow() wrapping, standalone lines ─────────────
# Returns a fixed visible-width string: ▕████░░░░░▏
draw_bar() {
  local value="$1" max="${2:-100}" width="${3:-20}"
  local pct filled color
  pct=$(awk "BEGIN{ v=$value+0; m=$max+0; if(m<=0)m=1; r=int(v*100/m); if(r>100)r=100; if(r<0)r=0; print r }")
  filled=$(awk "BEGIN{ v=$value+0; m=$max+0; w=$width+0; if(m<=0)m=1; r=int(v*w/m); if(r>w)r=w; if(r<0)r=0; print r }")
  local empty=$(( width - filled ))
  if   [ "$pct" -lt 50 ] 2>/dev/null; then color=$CG
  elif [ "$pct" -lt 75 ] 2>/dev/null; then color=$CY
  else                                      color=$CR
  fi
  printf "${CS}▕${R}${color}${B}"
  local i=0; while [ $i -lt "$filled" ]; do printf "█"; i=$(( i+1 )); done
  printf "${CS}"
  i=0; while [ $i -lt "$empty" ]; do printf "░"; i=$(( i+1 )); done
  printf "${CS}▏${R}"
}

# ── Fixed-width border system ────────────────────────────────────
# All borders are exactly 64 chars wide (2 spaces indent + ║ + 60 content + ║)
# Content must be exactly 60 visible characters — we build each row explicitly
# using printf with fixed field widths, never relying on escape-code-aware math.

W=60  # inner visible width

_line() {
  # _line LEFT FILL MID FILL RIGHT — draws a border line
  local l="$1" f="$2" m="$3" r="$4"
  printf "  ${CS}%s" "$l"
  local i=0; while [ $i -lt 30 ]; do printf "%s" "$f"; i=$(( i+1 )); done
  printf "%s" "$m"
  i=0; while [ $i -lt 30 ]; do printf "%s" "$f"; i=$(( i+1 )); done
  printf "%s${R}\n" "$r"
}

top_line()    { _line "╔" "═" "═" "╗"; }   # no mid divider variant
top_line_h()  { _line "╔" "═" "╤" "╗"; }   # with mid divider
mid_line()    { _line "╠" "═" "═" "╣"; }
mid_line_h()  { _line "╠" "═" "╪" "╣"; }
bot_line()    { _line "╚" "═" "═" "╝"; }
bot_line_h()  { _line "╚" "═" "╧" "╝"; }
sep_line()    { _line "╟" "─" "─" "╢"; }
sep_line_h()  { _line "╟" "─" "┼" "╢"; }

# Empty row
empty_row() {
  printf "  ${CS}║${R}%60s${CS}║${R}\n" ""
}

# Label row — full width, left-aligned, padded to exactly 60 chars visible
# Usage: label_row COLOR "text"
label_row() {
  local col="$1" text="$2"
  # visible len of text (no escapes)
  local vlen=${#text}
  local pad=$(( 60 - vlen - 2 ))
  printf "  ${CS}║${R} ${col}${B}%s${R}" "$text"
  local i=0; while [ $i -lt $pad ]; do printf " "; i=$(( i+1 )); done
  printf " ${CS}║${R}\n"
}

# Two-column row — each column exactly 30 chars visible (including ║ border)
# Usage: two_col  LEFT_KEY LEFT_COLOR LEFT_TEXT  RIGHT_KEY RIGHT_COLOR RIGHT_TEXT
two_col() {
  local lk="$1" lc="$2" lt="$3"
  local rk="$4" rc="$5" rt="$6"
  # Left cell: " key  text" padded to 29 chars + │
  # Right cell: " key  text" padded to 29 chars
  local left_vis=$(( 1 + ${#lk} + 2 + ${#lt} ))
  local right_vis=$(( 1 + ${#rk} + 2 + ${#rt} ))
  local lpad=$(( 29 - left_vis ))
  local rpad=$(( 29 - right_vis ))
  printf "  ${CS}║${R} ${lc}${B}%s${R}  ${CW}%s${R}" "$lk" "$lt"
  local i=0; while [ $i -lt $lpad ]; do printf " "; i=$(( i+1 )); done
  printf "${CS}│${R} ${rc}${B}%s${R}  ${CW}%s${R}" "$rk" "$rt"
  i=0; while [ $i -lt $rpad ]; do printf " "; i=$(( i+1 )); done
  printf " ${CS}║${R}\n"
}

# Stat row — single bar row
# Usage: stat_row "LABEL" BAR_VALUE BAR_MAX BAR_WIDTH "VALUE_STRING" "STATE_STRING" STATE_COLOR
stat_row() {
  local lbl="$1" val="$2" max="$3" bw="$4" vstr="$5" sstr="$6" sc="$7"
  # Layout: ║ LABEL(5) space bar(bw+2) space VALUE(12) space STATE(rest) ║
  # Fixed: label=5, gap=1, bar=bw+2 (▕...▏), gap=1, vstr=12, gap=1, sstr=10 = 5+1+(bw+2)+1+12+1+10=32+bw
  # bw=20 → 52 chars + 2 margins = 54 visible inside → pad remainder
  printf "  ${CS}║${R} ${CS}%-5s${R} " "$lbl"
  draw_bar "$val" "$max" "$bw"
  printf " ${CW}${B}%-12s${R} ${sc}${B}%-9s${R}" "$vstr" "$sstr"
  # Pad: 60 - (1+5+1+bw+2+1+12+1+9) = 60 - (32+bw)
  local used=$(( 32 + bw ))
  local pad=$(( 60 - used ))
  local i=0; while [ $i -lt $pad ]; do printf " "; i=$(( i+1 )); done
  printf "${CS}║${R}\n"
}

# Section header row inside box
section_row() {
  local col="$1" text="$2"
  local vlen=${#text}
  local pad=$(( 58 - vlen ))
  printf "  ${CS}║${R} ${col}${D}%s${R}" "$text"
  local i=0; while [ $i -lt $pad ]; do printf " "; i=$(( i+1 )); done
  printf " ${CS}║${R}\n"
}

# ── Header / Banner ──────────────────────────────────────────────
print_header() {
  printf "\n  ${CA}${B}PERFGUARD${R}  ${CS}v${PERFGUARD_VERSION}  ─────────────────────────────────────────────────${R}\n\n"
}

print_banner() {
  printf "\n"
  # Compact 5-line banner — fits in 62 chars with 2-space indent
  printf "  ${CA}${B}██████╗ ███████╗██████╗ ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗${R}\n"
  printf "  ${CA}${B}██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝ ██║   ██║██╔══██╗██╔══██╗${R}\n"
  printf "  ${CA}${B}██████╔╝█████╗  ██████╔╝█████╗  ██║  ███╗██║   ██║███████║██████╔╝${R}\n"
  printf "  ${CS}██╔═══╝ ██╔══╝  ██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██║██╔══██╗${R}\n"
  printf "  ${CS}╚══════╝╚══════╝╚═════╝ ╚══════╝╚══════╝ ╚══════╝ ╚═════╝ ╚═════╝${R}\n"
  printf "  ${CS}─────────────────── ${CA}v%s${CS} ── macOS Performance Manager ─────${R}\n\n" "$PERFGUARD_VERSION"
}

# ── STATUS ──────────────────────────────────────────────────────
cmd_status() {
  print_header
  local ug tg rp cpu du dt dp bat swap
  IFS='|' read -r ug tg rp <<< "$(get_ram_stats)"
  cpu=$(get_cpu_usage)
  IFS='|' read -r du dt dp <<< "$(get_disk_stats)"
  bat=$(get_battery)
  swap=$(get_swap)
  local d_num; d_num=$(echo "$dp" | tr -d '%'); [ -z "$d_num" ] && d_num=0
  local bat_s; [ -n "$bat" ] && bat_s="${bat}%" || bat_s="N/A"
  local up; up=$(uptime 2>/dev/null | awk -F'up ' '{print $2}' | cut -d',' -f1 | xargs)

  local ram_st ram_sc cpu_st cpu_sc
  if   [ "$rp" -lt 50 ] 2>/dev/null; then ram_st="HEALTHY";  ram_sc=$CG
  elif [ "$rp" -lt 75 ] 2>/dev/null; then ram_st="MODERATE"; ram_sc=$CY
  else                                     ram_st="PRESSURE"; ram_sc=$CR
  fi
  if   [ "${cpu:-0}" -lt 40 ] 2>/dev/null; then cpu_st="IDLE";      cpu_sc=$CG
  elif [ "${cpu:-0}" -lt 70 ] 2>/dev/null; then cpu_st="ACTIVE";    cpu_sc=$CY
  else                                          cpu_st="HIGH LOAD"; cpu_sc=$CR
  fi

  top_line
  section_row "$CA" "SYSTEM SNAPSHOT                    $(date '+%a %d %b  %H:%M:%S')"
  sep_line
  empty_row
  stat_row "RAM"  "$rp"        100 20 "${ug}/${tg}GB"  "$ram_st" "$ram_sc"
  stat_row "CPU"  "${cpu:-0}"  100 20 "${cpu:-0}%"      "$cpu_st" "$cpu_sc"
  stat_row "DISK" "$d_num"     100 20 "${du}/${dt}"     "${dp}"   "$CS"
  empty_row
  sep_line
  two_col "BATTERY" "$CG" "$bat_s"   "UPTIME"  "$CA" "$up"
  two_col "SWAP"    "$CV" "${swap}MB" "PROCS"   "$CS" "$(ps ax 2>/dev/null | wc -l | tr -d ' ')"
  empty_row
  bot_line
  echo ""
}

# ── MENU ────────────────────────────────────────────────────────
cmd_menu() {
  while true; do
    clear

    local ug tg rp cpu du dt dp bat
    IFS='|' read -r ug tg rp <<< "$(get_ram_stats)"
    cpu=$(get_cpu_usage)
    IFS='|' read -r du dt dp <<< "$(get_disk_stats)"
    bat=$(get_battery)
    local d_num; d_num=$(echo "$dp" | tr -d '%'); [ -z "$d_num" ] && d_num=0
    local bat_s; [ -n "$bat" ] && bat_s="${bat}%" || bat_s="N/A"

    print_banner

    # Stats panel
    top_line_h
    stat_row "RAM"  "$rp"       100 20 "${ug}/${tg}GB"  "" "$CS"
    stat_row "CPU"  "${cpu:-0}" 100 20 "${cpu:-0}%"      "" "$CS"
    stat_row "DISK" "$d_num"    100 20 "${du}/${dt}"     "" "$CS"
    two_col "BATTERY" "$CG" "$bat_s"  "TIME" "$CS" "$(date '+%H:%M:%S')"
    mid_line_h

    # Performance section
    section_row "$CA" "PERFORMANCE"
    sep_line_h
    two_col "1" "$CA" "System overview"   "2" "$CA" "RAM boost  (sudo)"
    sep_line_h
    two_col "3" "$CA" "Cache cleanup"     "4" "$CA" "Deep system sweep"
    sep_line_h
    two_col "5" "$CA" "Process manager"   "6" "$CA" "Live monitor"
    sep_line_h
    two_col "7" "$CA" "Full turbo sequence" " " "$CS" ""
    mid_line_h

    # Diagnostics section
    section_row "$CV" "SYSTEM & DIAGNOSTICS"
    sep_line_h
    two_col "8" "$CV" "DNS flush"         "9" "$CV" "Network info"
    sep_line_h
    two_col "a" "$CV" "Startup scan"      "b" "$CV" "Disk breakdown"
    sep_line_h
    two_col "c" "$CV" "Swap & VM info"    "d" "$CV" "Pressure watch"
    mid_line_h

    # Tools section
    section_row "$CO" "TOOLS"
    sep_line_h
    two_col "e" "$CO" "Schedule cleanup"  "f" "$CO" "Whitelist"
    sep_line_h
    two_col "g" "$CO" "Activity log"      "q" "$CR" "Quit"
    empty_row
    bot_line

    printf "\n  ${CS}▶${R}  Enter option: "
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
      q|Q) printf "\n  ${CS}Goodbye.${R}\n\n"; exit 0 ;;
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
  printf "  ${CA}${B}RAM BOOST${R}\n  ${CS}Reclaiming inactive memory via purge...${R}\n\n"
  local ub; IFS='|' read -r ub _ _ <<< "$(get_ram_stats)"
  if sudo purge 2>/dev/null; then
    sleep 2
    local ua; IFS='|' read -r ua _ _ <<< "$(get_ram_stats)"
    local freed; freed=$(awk "BEGIN{printf \"%.1f\", $ub - $ua}")
    printf "  Before  ${CW}${B}%sGB${R}  →  After  ${CW}${B}%sGB${R}\n" "$ub" "$ua"
    printf "  Reclaimed  ${CG}${B}~%sGB${R}\n\n  ${CG}${B}▶  COMPLETE${R}\n\n" "$freed"
    log "RAM Boost: reclaimed ~${freed}GB"
  else
    printf "  ${CY}Requires sudo.${R}  Run: ${B}sudo perfguard boost${R}\n\n"
  fi
}

# ── CACHE CLEAN ─────────────────────────────────────────────────
cmd_clean() {
  print_header
  printf "  ${CA}${B}CACHE CLEANUP${R}\n\n"
  local total_freed=0

  _crow() { printf "  ${CG}▸${R}  %-28s ${CS}%s${R}  ${CW}${B}%s${R}\n" "$1" "$2" "$3"; }

  local d="$HOME/Library/Caches"
  if [ -d "$d" ]; then
    local sb sa fk; sb=$(du -sk "$d" 2>/dev/null | awk '{print $1+0}')
    find "$d" -mindepth 1 -maxdepth 2 -type f -mtime +1 -delete 2>/dev/null
    sa=$(du -sk "$d" 2>/dev/null | awk '{print $1+0}')
    fk=$(( ${sb:-0} - ${sa:-0} ))
    _crow "User app caches" "~/Library/Caches" "$(awk "BEGIN{printf \"%.1fMB\",$fk/1024}")"
    total_freed=$(awk "BEGIN{printf \"%.1f\",$total_freed+$fk/1024}")
  fi

  local ld="$HOME/Library/Logs"
  if [ -d "$ld" ]; then
    local sb sa fk; sb=$(du -sk "$ld" 2>/dev/null | awk '{print $1+0}')
    find "$ld" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +7 -delete 2>/dev/null
    sa=$(du -sk "$ld" 2>/dev/null | awk '{print $1+0}')
    fk=$(( ${sb:-0} - ${sa:-0} ))
    _crow "Old log files" "~/Library/Logs >7d" "$(awk "BEGIN{printf \"%.1fMB\",$fk/1024}")"
    total_freed=$(awk "BEGIN{printf \"%.1f\",$total_freed+$fk/1024}")
  fi

  local tc; tc=$(find "$TMPDIR" -maxdepth 1 -type f -mtime +0 2>/dev/null | wc -l | tr -d ' ')
  find "$TMPDIR" -maxdepth 1 -type f -mtime +0 -delete 2>/dev/null
  _crow "Temp files" "\$TMPDIR" "${tc} files"

  local cd2="$HOME/Library/Logs/DiagnosticReports"
  if [ -d "$cd2" ]; then
    local cnt; cnt=$(find "$cd2" -type f -mtime +14 2>/dev/null | wc -l | tr -d ' ')
    find "$cd2" -type f -mtime +14 -delete 2>/dev/null
    _crow "Crash reports" "DiagnosticReports >14d" "${cnt} files"
  fi

  local xd="$HOME/Library/Developer/Xcode/DerivedData"
  if [ -d "$xd" ]; then
    local xsz; xsz=$(du -sm "$xd" 2>/dev/null | awk '{print $1+0}')
    if [ "${xsz:-0}" -gt 200 ] 2>/dev/null; then
      rm -rf "${xd:?}"/* 2>/dev/null
      _crow "Xcode DerivedData" "Build artifacts" "${xsz}MB"
      total_freed=$(awk "BEGIN{printf \"%.1f\",$total_freed+${xsz:-0}}")
    fi
  fi

  command -v npm  >/dev/null 2>&1 && npm cache clean --force >/dev/null 2>&1 \
    && _crow "npm cache" "" "cleared"
  command -v pip3 >/dev/null 2>&1 && pip3 cache purge >/dev/null 2>&1 \
    && _crow "pip cache" "" "cleared"
  if command -v brew >/dev/null 2>&1; then
    local bout; bout=$(brew cleanup --prune=7 2>/dev/null | grep -E "freed|Removed" | /usr/bin/tail -1 || echo "done")
    _crow "Homebrew cache" "old versions" "$bout"
  fi

  printf "\n  ${CS}──────────────────────────────────────────────────${R}\n"
  printf "  Total freed  ${CG}${B}~%.0f MB${R}\n\n" "$total_freed"
}

# ── DEEP CLEAN ──────────────────────────────────────────────────
cmd_deep_clean() {
  print_header
  printf "  ${CA}${B}DEEP CLEAN${R}  ${CS}— Extended sweep${R}\n\n"
  local total_freed=0
  _drow() { printf "  ${CG}▸${R}  %-28s ${CS}%s${R}  ${CW}${B}%s${R}\n" "$1" "$2" "$3"; }

  for entry in \
    "$HOME/Library/Caches/com.apple.Safari:Safari cache" \
    "$HOME/Library/Caches/Google/Chrome:Chrome cache" \
    "$HOME/Library/Caches/Firefox:Firefox cache"
  do
    local dir lbl sz
    dir=$(echo "$entry" | cut -d: -f1); lbl=$(echo "$entry" | cut -d: -f2)
    if [ -d "$dir" ]; then
      sz=$(du -sm "$dir" 2>/dev/null | awk '{print $1+0}')
      find "$dir" \( -name "Cache" -o -name "cache2" \) -type d 2>/dev/null | \
        while read -r dd; do rm -rf "${dd:?}"/* 2>/dev/null; done
      rm -rf "${dir:?}"/* 2>/dev/null
      _drow "$lbl" "Website data" "~${sz}MB"
      total_freed=$(awk "BEGIN{printf \"%.1f\",$total_freed+${sz:-0}}")
    fi
  done

  local dc; dc=$(find "$HOME" -name ".DS_Store" -maxdepth 6 2>/dev/null | wc -l | tr -d ' ')
  find "$HOME" -name ".DS_Store" -maxdepth 6 -delete 2>/dev/null
  _drow ".DS_Store files" "Desktop metadata" "${dc} files"

  local bd="$HOME/Library/Application Support/MobileSync/Backup"
  [ -d "$bd" ] && printf "  ${CY}!${R}  %-28s ${CS}Review in Finder${R}  ${CW}${B}%s${R}\n" \
    "iOS backups" "$(du -sh "$bd" 2>/dev/null | awk '{print $1}')"

  printf "\n  ${CS}──────────────────────────────────────────────────${R}\n"
  printf "  Extended freed  ${CG}${B}~%.0f MB${R}\n\n" "$total_freed"
  log "Deep clean completed"
}

# ── DNS FLUSH ───────────────────────────────────────────────────
cmd_dns_flush() {
  print_header
  printf "  ${CA}${B}DNS CACHE FLUSH${R}\n\n  ${CS}Flushing resolver cache...${R}\n"
  if sudo dscacheutil -flushcache 2>/dev/null && sudo killall -HUP mDNSResponder 2>/dev/null; then
    printf "  ${CG}${B}▶  COMPLETE${R}  DNS cache cleared.\n\n"; log "DNS cache flushed"
  else
    printf "  ${CY}Requires sudo.${R}  Run: ${B}sudo perfguard dns-flush${R}\n\n"
  fi
}

# ── NETWORK ─────────────────────────────────────────────────────
cmd_network() {
  print_header
  printf "  ${CA}${B}NETWORK DIAGNOSTICS${R}\n\n  ${CS}Active interfaces:${R}\n"
  networksetup -listallnetworkservices 2>/dev/null | /usr/bin/tail -n +2 | while IFS= read -r svc; do
    local ip; ip=$(networksetup -getinfo "$svc" 2>/dev/null | awk '/^IP address:/{print $3}')
    [ -n "$ip" ] && [ "$ip" != "none" ] && printf "  ${CA}  %-24s${R}  ${CW}%s${R}\n" "$svc" "$ip"
  done
  echo ""
  printf "  ${CS}Connectivity:${R}\n"
  for t in "8.8.8.8:Google DNS" "1.1.1.1:Cloudflare" "apple.com:Apple"; do
    local h l; h=$(echo "$t" | cut -d: -f1); l=$(echo "$t" | cut -d: -f2)
    if ping -c 1 -W 1000 "$h" >/dev/null 2>&1; then
      local ms; ms=$(ping -c 1 "$h" 2>/dev/null | awk -F'/' '/round-trip/{printf "%.1f",$5}')
      printf "  ${CG}  ◈ %-20s${R}  ${CS}%s ms${R}\n" "$l" "${ms:-?}"
    else
      printf "  ${CR}  ✗ %-20s${R}  ${CS}unreachable${R}\n" "$l"
    fi
  done
  local ws; ws=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/agrCtlRSSI/{print $2}')
  [ -n "$ws" ] && printf "\n  ${CS}Wi-Fi signal:${R}  ${CW}${B}%s dBm${R}\n" "$ws"
  echo ""
}

# ── STARTUP SCAN ────────────────────────────────────────────────
cmd_startup_scan() {
  print_header
  printf "  ${CA}${B}STARTUP ITEMS SCAN${R}\n\n  ${CS}Login Items:${R}\n"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | tr ',' '\n' | sed 's/^ //' | while IFS= read -r item; do
      [ -z "$item" ] && continue; printf "  ${CA}  ◈ %s${R}\n" "$item"
    done
  echo ""
  printf "  ${CS}User Launch Agents:${R}\n"
  local ad="$HOME/Library/LaunchAgents" found=0
  if [ -d "$ad" ]; then
    for p in "$ad"/*.plist; do
      [ -f "$p" ] || continue
      local nm dis; nm=$(basename "$p" .plist)
      dis=$(defaults read "$p" Disabled 2>/dev/null || echo "0")
      if [ "$dis" = "1" ]; then printf "  ${CS}  ◌ %-54s  disabled${R}\n" "$nm"
      else printf "  ${CW}  ◈ %-54s  ${CG}active${R}\n" "$nm"; fi
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
  local entries=("$HOME/Downloads:Downloads" "$HOME/Documents:Documents"
    "$HOME/Desktop:Desktop" "$HOME/Movies:Movies" "$HOME/Music:Music"
    "$HOME/Library/Caches:App Caches" "$HOME/Library/Application Support:App Data"
    "$HOME/.Trash:Trash")
  declare -a lbls szs; local max_mb=1
  for e in "${entries[@]}"; do
    local dir lbl sz
    dir=$(echo "$e" | cut -d: -f1); lbl=$(echo "$e" | cut -d: -f2)
    [ -d "$dir" ] && sz=$(du -sm "$dir" 2>/dev/null | awk '{print $1+0}') || sz=0
    lbls+=("$lbl"); szs+=("$sz")
    [ "$sz" -gt "$max_mb" ] 2>/dev/null && max_mb=$sz
  done
  local idx=0
  for lbl in "${lbls[@]}"; do
    local sz="${szs[$idx]}"; idx=$(( idx+1 ))
    printf "  ${CS}%-20s${R}  " "$lbl"
    local bw=26 filled; filled=$(awk "BEGIN{r=int($sz*$bw/$max_mb);if(r>$bw)r=$bw;print r}")
    local col; [ "$sz" -gt 10000 ] 2>/dev/null && col=$CR || { [ "$sz" -gt 2000 ] 2>/dev/null && col=$CY || col=$CG; }
    printf "${col}"; local i=0; while [ $i -lt "$filled" ]; do printf "█"; i=$(( i+1 )); done
    printf "${CS}"; i=$filled; while [ $i -lt $bw ]; do printf "░"; i=$(( i+1 )); done
    printf "${R}  ${CW}${B}"
    [ "$sz" -gt 1024 ] 2>/dev/null && awk "BEGIN{printf \"%.1f GB\",$sz/1024}" || printf "%s MB" "$sz"
    printf "${R}\n"
  done
  echo ""
  printf "  ${CS}Total:${R}  "; df -h / 2>/dev/null | awk 'NR==2 {printf "%s used of %s (%s)\n",$3,$2,$5}'
  echo ""
}

# ── SWAP INFO ───────────────────────────────────────────────────
cmd_swap_info() {
  print_header
  printf "  ${CA}${B}SWAP & VIRTUAL MEMORY${R}\n\n"
  printf "  ${CS}Swap:${R}  ${CW}%s${R}\n\n" "$(sysctl -n vm.swapusage 2>/dev/null || echo 'N/A')"
  printf "  ${CS}VM Statistics:${R}\n"
  vm_stat 2>/dev/null \
    | grep -E "(free|active|inactive|wired|compressed|pageins|pageouts|swapins|swapouts)" \
    | while IFS= read -r line; do printf "  ${CS}  %s${R}\n" "$line"; done
  echo ""
}

# ── PRESSURE WATCH ──────────────────────────────────────────────
cmd_pressure_watch() {
  print_header
  printf "  ${CA}${B}MEMORY PRESSURE WATCH${R}  ${CS}Ctrl+C to stop${R}\n\n"
  local thr=80
  while true; do
    local ug tg pct; IFS='|' read -r ug tg pct <<< "$(get_ram_stats)"
    printf "\r  ${CS}%s${R}  " "$(date '+%H:%M:%S')"
    draw_bar "$pct" 100 32
    printf "  ${CW}${B}%s${R}${CS}/%sGB${R}  " "$ug" "$tg"
    if [ "${pct:-0}" -ge "$thr" ] 2>/dev/null; then
      printf "${CR}${B}%s%%  — PRESSURE ALERT${R}   " "$pct"
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
    local pid mk name mb
    pid=$(echo "$line" | awk '{print $1}')
    mk=$(echo "$line" | awk '{print $2}')
    name=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
    mb=$(awk "BEGIN{printf \"%.0f\",${mk:-0}/1024}")
    [ "${mb:-0}" -le 150 ] 2>/dev/null && continue
    [ "$(is_approved "$name")" = "true" ] && continue
    found=1
    printf "  ${CR}▶${R}  ${B}%-40s${R}  ${CS}%sMB  PID %s${R}\n" "$name" "$mb" "$pid"
    printf "     Kill? [y/N] "
    local c; read -r c
    if [ "$c" = "y" ] || [ "$c" = "Y" ]; then
      kill -9 "$pid" 2>/dev/null \
        && printf "  ${CG}  Terminated.${R}\n" \
        && log "Killed: $name (PID $pid, ${mb}MB)" "WARN" \
        && killed=$(( killed+1 ))
    fi
  done < <(ps -axo pid,rss,comm 2>/dev/null | /usr/bin/tail -n +2 | sort -k2 -rn | /usr/bin/head -50)
  echo ""
  if [ "$found" = "0" ]; then printf "  ${CG}${B}▶  No unauthorized heavy processes found.${R}\n"
  else [ "$killed" -gt 0 ] && printf "  ${CR}${B}Terminated: %d process(es)${R}\n" "$killed"; fi
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
    rp=$(awk "BEGIN{printf \"%.0f\",$pct+0}")
    cp=$(awk "BEGIN{printf \"%.0f\",${cpu:-0}+0}")
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
      mb=$(awk "BEGIN{printf \"%.0f\",${mk:-0}/1024}")
      if [ "$(is_approved "$nm")" = "true" ]; then sc=$CG; sl="approved"
      else sc=$CR; sl="unknown"; fi
      printf "  ${CS}%-7s${R}  %-36s  ${CW}${B}%6sMB${R}  ${CS}%5s%%${R}  ${sc}%-10s${R}\n" "$pid" "$nm" "$mb" "$cp2" "$sl"
      count=$(( count+1 ))
    done < <(ps -axo pid,pcpu,rss,comm 2>/dev/null | /usr/bin/tail -n +2 | sort -k3 -rn)
    sleep 3
  done
}

# ── TURBO ───────────────────────────────────────────────────────
cmd_turbo() {
  print_header
  printf "  ${CV}${B}TURBO MODE${R}  ${CS}Full optimization sequence${R}\n\n"
  printf "  ${CS}kill-unused → deep-clean → dns-flush → boost${R}\n\n"
  local i=0; while [ $i -lt 62 ]; do printf "${CS}═${R}"; i=$(( i+1 )); done; echo ""
  echo ""; cmd_kill_unused; echo ""
  local i=0; while [ $i -lt 62 ]; do printf "${CS}─${R}"; i=$(( i+1 )); done; echo ""
  echo ""; cmd_deep_clean; echo ""
  local i=0; while [ $i -lt 62 ]; do printf "${CS}─${R}"; i=$(( i+1 )); done; echo ""
  echo ""; cmd_dns_flush; echo ""
  local i=0; while [ $i -lt 62 ]; do printf "${CS}─${R}"; i=$(( i+1 )); done; echo ""
  echo ""; cmd_boost
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
    printf "  ${CS}%-24s${R}" "$app"; col=$(( col+1 ))
    [ $(( col % 3 )) -eq 0 ] && echo ""
  done
  echo ""
  if [ -s "$WHITELIST_FILE" ]; then
    echo ""; printf "  ${CS}User additions:${R}\n"
    while IFS= read -r line; do [ -n "$line" ] && printf "  ${CG}▸  %s${R}\n" "$line"; done < "$WHITELIST_FILE"
  fi
  echo ""; printf "  ${CS}Add:${R}  echo 'AppName' >> ~/.perfguard/whitelist\n\n"
}

# ── SCHEDULE ────────────────────────────────────────────────────
cmd_schedule() {
  print_header
  printf "  ${CA}${B}AUTO-CLEANUP SCHEDULER${R}\n\n"
  local sp; sp=$(command -v perfguard 2>/dev/null || echo "$0")
  printf "  ${CS}Choose schedule:${R}\n\n"
  printf "  ${CA}1${R}  Every 30 minutes\n  ${CA}2${R}  Every hour\n  ${CA}3${R}  Daily at 3:00 AM\n\n"
  printf "  Select [1-3]: "; local c; read -r c
  local expr
  case "$c" in 1) expr="*/30 * * * *";; 2) expr="0 * * * *";; 3) expr="0 3 * * *";;
    *) printf "  ${CY}Invalid.${R}\n\n"; return;;
  esac
  ( crontab -l 2>/dev/null | grep -v "perfguard"; echo "${expr} ${sp} clean >> ${LOG_FILE} 2>&1" ) | crontab -
  printf "  ${CG}${B}▶  SCHEDULED${R}  Cron entry added.\n\n"; log "Scheduled: $expr"
}

# ── LOG ─────────────────────────────────────────────────────────
cmd_log() {
  print_header
  printf "  ${CA}${B}ACTIVITY LOG${R}  ${CS}last 40 entries${R}\n\n"
  if [ -s "$LOG_FILE" ]; then
    /usr/bin/tail -40 "$LOG_FILE" | while IFS= read -r line; do
      local lc=$CS
      echo "$line" | grep -q "WARN"  && lc=$CY
      echo "$line" | grep -q "ERROR" && lc=$CR
      printf "  ${lc}%s${R}\n" "$line"
    done
  else printf "  ${CS}No entries yet.${R}\n"; fi
  echo ""
}

# ── HELP ────────────────────────────────────────────────────────
cmd_help() {
  print_header
  printf "  ${CS}Usage:${R}  perfguard ${CA}[command]${R}\n\n"
  local cmds=("menu:Interactive menu (default)"
    "status:System snapshot" "boost:Flush inactive RAM  (sudo)"
    "clean:Clear caches and temp files" "deep-clean:Browser caches and .DS_Store"
    "kill-unused:Unauthorized process manager" "monitor:Live process monitor"
    "turbo:Full optimization sequence" "dns-flush:Flush DNS resolver cache"
    "network:Interface and ping diagnostics" "startup-scan:Login items audit"
    "disk-usage:Per-folder disk breakdown" "swap-info:Swap and VM statistics"
    "pressure-watch:Live memory pressure alert" "schedule:Cron auto-cleanup"
    "whitelist:Manage approved processes" "log:Activity log" "version:Print version")
  for cmd in "${cmds[@]}"; do
    printf "  ${CA}%-18s${R}  ${CS}%s${R}\n" "$(echo "$cmd"|cut -d: -f1)" "$(echo "$cmd"|cut -d: -f2)"
  done
  echo ""; printf "  ${CS}Log:  %s${R}\n\n" "$LOG_FILE"
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