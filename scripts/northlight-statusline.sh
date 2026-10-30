#!/bin/sh
# Claude Code statusLine wrapper. Saves the account's 5-hour and 7-day usage where the
# Northlight Mac app can read it, then hands the same input to your own status line.
#
#   "statusLine": {"type": "command",
#                  "command": "sh ~/.claude/northlight-statusline.sh claude-powerline --style=powerline"}
#
# Only rate_limits is read; the path, session name and transcript stay here.

input=$(cat; printf x)
input=${input%x}

dir=${NORTHLIGHT_USAGE_DIR:-"$HOME/Library/Containers/com.arkwerx.northlight/Data/Library/Application Support/Northlight"}

# Prints one number at a key path, or fails.
number() {
    value=$(printf '%s' "$limits" | /usr/bin/plutil -extract "$1" raw -o - -- - 2>/dev/null) || return 1
    case $value in '' | *[!0-9.]* | *.*.*) return 1 ;; esac
    printf '%s' "$value"
}

# Prints "name":{...}, for a window with both numbers.
window() {
    used=$(number "$1.used_percentage") && resets=$(number "$1.resets_at") &&
        printf '"%s":{"used_percentage":%s,"resets_at":%s},' "$1" "$used" "$resets"
}

case $input in
*'"rate_limits"'*)
    if limits=$(printf '%s' "$input" | /usr/bin/plutil -extract rate_limits json -o - -- - 2>/dev/null); then
        windows=$(window five_hour)$(window seven_day)
        if [ -n "$windows" ] && mkdir -p "$dir" && tmp=$(mktemp "$dir/.usage.XXXXXX"); then
            if printf '{%s"observed_at":%s}\n' "$windows" "$(date +%s)" >"$tmp"; then
                mv -f "$tmp" "$dir/usage.json"
            else
                rm -f "$tmp"
            fi
        fi
    fi
    ;;
esac

[ $# -gt 0 ] || exit 0
printf '%s' "$input" | exec "$@"
