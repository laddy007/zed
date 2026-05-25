#!/usr/bin/env bash
# statusline.sh - Claude Code status line with optional ZED_TASK badge.
# Reads JSON from stdin (Claude Code passes session info) and prints
# a single-line status. If $ZED_TASK is set, appends a yellow-on-black
# colored badge with the task name.

input=$(cat)

cwd=$(echo "$input"      | jq -r '.workspace.current_dir // "."')
model=$(echo "$input"    | jq -r '.model.display_name // "Unknown"')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total_out=$(echo "$input"| jq -r '.context_window.total_output_tokens // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

ESC=$'\033'
badge=""
if [ -n "$ZED_TASK" ]; then
    # Normalize Windows TEMP path (backslashes -> forward slashes) for bash.
    temp_norm="${TEMP//\\//}"
    flag="$temp_norm/zed-done/$ZED_TASK.flag"

    # Build preview from ZED_PROMPT_FILE: first line, first 20 chars + "...".
    preview=""
    if [ -n "$ZED_PROMPT_FILE" ]; then
        pf="${ZED_PROMPT_FILE//\\//}"
        if [ -f "$pf" ]; then
            first_line=$(head -n 1 "$pf" 2>/dev/null)
            short="${first_line:0:200}"
            if [ ${#first_line} -gt 200 ]; then short="${short}..."; fi
            if [ -n "$short" ]; then preview=": $short"; fi
        fi
    fi

    label="${ZED_TASK}${preview}"

    if [ -f "$flag" ]; then
        # Green: claude finished, awaiting acknowledgement via zed-reset.
        badge="${ESC}[48;2;0;180;0m${ESC}[97;1m ${label} DONE ${ESC}[0m"
    else
        # Gray: claude actively working.
        badge="${ESC}[48;2;120;120;120m${ESC}[97;1m ${label} ${ESC}[0m"
    fi
fi

# Build main line (line 1).
if [ -n "$total_in" ] && [ -n "$total_out" ] && [ -n "$ctx_size" ]; then
    total_used=$((total_in + total_out))
    used_k=$((total_used / 1000))
    ctx_k=$((ctx_size / 1000))
    pct=$((total_used * 100 / ctx_size))
    main=$(printf "%s | %s | %dk/%dk (%d%%)" "$cwd" "$model" "$used_k" "$ctx_k" "$pct")
else
    main=$(printf "%s | %s" "$cwd" "$model")
fi

# Output: main on line 1, badge on line 2 (only if present).
if [ -n "$badge" ]; then
    printf "%s\n%s" "$main" "$badge"
else
    printf "%s" "$main"
fi
