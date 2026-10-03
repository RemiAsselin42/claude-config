#!/bin/bash
# Vendored from cc-safe-setup 30.0.7 (MIT, github.com/yurukusa/cc-safe-setup)
# on 2026-10-03: claude-config installs these three guards itself instead of
# running an unpinned "npx cc-safe-setup" that shipped 8 hooks, 5 of them unwanted.
# Local change: git commands also match after an "rtk " prefix (RTK rewrites
# "git x" into "rtk git x", and /create-pr writes it that way) and after a
# command separator ("cd repo && git push").
# ================================================================
# destructive-guard.sh — Destructive Command Blocker
# ================================================================
# PURPOSE:
#   Blocks dangerous shell commands that can cause irreversible damage.
#   Catches rm -rf on sensitive paths, git reset --hard, git clean -fd,
#   and other destructive operations before they execute.
#
#   Built after a real incident where rm -rf on a pnpm project
#   followed NTFS junctions and deleted an entire C:\Users directory.
#   (GitHub Issue #36339)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHAT IT BLOCKS (exit 2):
#   - rm -rf / rm -r on root, home, or parent paths (/, ~, .., /home, /etc)
#   - git reset --hard
#   - git clean -fd / git clean -fdx
#   - chmod -R 777 on sensitive paths
#   - find ... -delete on broad patterns
#
# WHAT IT ALLOWS (exit 0):
#   - rm -rf on specific project subdirectories (node_modules, dist, build)
#   - git reset --soft, git reset HEAD
#   - All non-destructive commands
#
# CONFIGURATION:
#   CC_ALLOW_DESTRUCTIVE=1 — disable this guard (not recommended)
#   CC_SAFE_DELETE_DIRS — colon-separated list of safe-to-delete dirs
#     default: "node_modules:dist:build:.cache:__pycache__:coverage"
#
# NOTE: On Windows/WSL2, rm -rf can follow NTFS junctions (symlinks)
# and delete far more than intended. This guard is especially critical
# on WSL2 environments.
# ================================================================

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Allow override (not recommended)
if [[ "${CC_ALLOW_DESTRUCTIVE:-0}" == "1" ]]; then
    exit 0
fi

# Log function — records blocked commands for audit
log_block() {
    local reason="$1"
    local logfile="${CC_BLOCK_LOG:-$HOME/.claude/blocked-commands.log}"
    mkdir -p "$(dirname "$logfile")" 2>/dev/null
    echo "[$(date -Iseconds)] BLOCKED: $reason | cmd: $COMMAND" >> "$logfile" 2>/dev/null
}

# Safe directories that can be deleted
SAFE_DIRS="${CC_SAFE_DELETE_DIRS:-node_modules:dist:build:.cache:__pycache__:coverage:.next:.nuxt:tmp}"

# --- Check 0: --no-preserve-root ---
if printf '%s' "$COMMAND" | grep -qE "rm\\s.*\\-\\-no-preserve-root"; then
    echo "BLOCKED: --no-preserve-root detected." >&2
    exit 2
fi

# --- Check 1: rm -rf on dangerous paths ---
if printf '%s' "$COMMAND" | grep -qE 'rm\s+(-[rf]+\s+)*(\/$|\/\s|\/[^a-z]|\/home|\/etc|\/usr|\/var|\/mnt|~\/|~\s*$|\.\.\/|\.\.\s*$|\.\s*$|\.\/\s*$)'; then
    # Exception: safe directories
    SAFE=0
    IFS=':' read -ra DIRS <<< "$SAFE_DIRS"
    for dir in "${DIRS[@]}"; do
        if printf '%s' "$COMMAND" | grep -qE "rm\s+.*${dir}\s*$|rm\s+.*${dir}/"; then
            SAFE=1
            break
        fi
    done

    # Check for mounted filesystems inside the target (NFS, Docker, bind mounts)
    # Why: GitHub #36640 — rm -rf on a dir with NFS mount deleted production data
    if (( SAFE == 0 )); then
        # Extract the target path from the rm command
        TARGET_PATH=$(printf '%s' "$COMMAND" | grep -oP 'rm\s+(-[rf]+\s+)*\K\S+')
        if [ -n "$TARGET_PATH" ] && command -v findmnt &>/dev/null; then
            if findmnt -n -o TARGET --submounts "$TARGET_PATH" 2>/dev/null | grep -q .; then
                log_block "rm on path with mounted filesystem"
                echo "BLOCKED: Target contains a mounted filesystem (NFS, Docker, bind)." >&2
                echo "" >&2
                echo "Command: $COMMAND" >&2
                echo "" >&2
                echo "Unmount the filesystem first, then retry." >&2
                exit 2
            fi
        fi
    fi

    if (( SAFE == 0 )); then
        log_block "rm on sensitive path"
        echo "BLOCKED: rm on sensitive path detected." >&2
        echo "" >&2
        echo "Command: $COMMAND" >&2
        echo "" >&2
        echo "This command targets a sensitive directory that could cause" >&2
        echo "irreversible data loss. On WSL2, rm -rf can follow NTFS" >&2
        echo "junctions and delete far beyond the target directory." >&2
        echo "" >&2
        echo "If you need to delete a specific subdirectory, target it directly:" >&2
        echo "  rm -rf ./specific-folder" >&2
        exit 2
    fi
fi

# --- Check 2: git reset --hard ---
# Only match when git is the actual command, not inside strings/arguments
if printf '%s' "$COMMAND" | grep -qE '(^|[;&|]\s*)(rtk\s+)?git\s+reset\s+--hard'; then
    log_block "git reset --hard"
    echo "BLOCKED: git reset --hard discards all uncommitted changes." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "Consider: git stash, or git reset --soft to keep changes staged." >&2
    exit 2
fi

# --- Check 3: git clean -fd ---
if printf '%s' "$COMMAND" | grep -qE '(^|[;&|]\s*)(rtk\s+)?git\s+clean\s+-[a-z]*[fd]'; then
    log_block "git clean"
    echo "BLOCKED: git clean removes untracked files permanently." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "Consider: git clean -n (dry run) first to see what would be deleted." >&2
    exit 2
fi

# --- Check 4: chmod 777 on broad paths ---
if printf '%s' "$COMMAND" | grep -qE 'chmod\s+(-R\s+)?777\s+(\/|~|\.)'; then
    echo "BLOCKED: chmod 777 on broad path is a security risk." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# --- Check 5: find -delete on broad patterns ---
if printf '%s' "$COMMAND" | grep -qE 'find\s+(\/|~|\.\.)\s.*-delete'; then
    echo "BLOCKED: find -delete on broad path risks mass deletion." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "Consider: find ... -print first to verify what matches." >&2
    exit 2
fi

# --- Check 6: sudo with dangerous commands ---
if printf '%s' "$COMMAND" | grep -qE '^\s*sudo\s+(rm\s+-[rf]|chmod\s+(-R\s+)?777|dd\s+if=|mkfs)'; then
    log_block "sudo with dangerous command"
    echo "BLOCKED: sudo with dangerous command detected." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "Running destructive commands with sudo amplifies the damage." >&2
    echo "Review the command carefully before proceeding." >&2
    exit 2
fi


# --- Check 7: PowerShell Remove-Item (Windows/WSL2) ---
# Real incident: GitHub #37331 — destroyed entire repo
# Skip if command is git commit (message text triggers false positive)
if printf '%s' "$COMMAND" | grep -qE '^\s*(git\s+commit|echo\s|printf\s|cat\s)'; then
    :  # string output commands mentioning PS commands are not destructive
elif printf '%s' "$COMMAND" | grep -qiE 'Remove-Item.*-Recurse.*-Force|Remove-Item.*-Force.*-Recurse|del\s+/s\s+/q|rd\s+/s\s+/q|rmdir\s+/s\s+/q'; then
    log_block "PowerShell destructive command"
    echo "BLOCKED: Destructive PowerShell command detected." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "Remove-Item with recursive force-delete can destroy entire directories" >&2
    echo "irreversibly. Target specific files instead." >&2
    exit 2
fi
if printf '%s' "$COMMAND" | grep -qE '(^|[;&|]\s*)(rtk\s+)?git\s+(checkout|switch)\s+.*(--force\b|-f\b|--discard-changes\b)'; then
    log_block "git checkout/switch --force"
    echo "BLOCKED: git checkout/switch with --force discards uncommitted changes." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "Consider: git stash before switching, or use git switch without --force." >&2
    exit 2
fi

if printf '%s' "$COMMAND" | grep -qE '(sh|bash|zsh)\s+-c\s+'; then
    INNER=$(printf '%s' "$COMMAND" | sed -E "s/.*(sh|bash|zsh)\s+-c\s+['\"]//" | sed "s/['\"]*$//" )
    if echo "$INNER" | grep -qE 'rm\s+-[rf]*\s+[/~]|git\s+reset\s+--hard|git\s+clean\s+-[fd]+|mkfs\.|dd\s+if='; then
        echo "BLOCKED: Destructive command hidden in shell wrapper" >&2
        echo "" >&2
        echo "Detected: $INNER" >&2
        exit 2
    fi
fi
if printf '%s' "$COMMAND" | grep -qE '\|\s*(sh|bash)\s*$'; then
    if printf '%s' "$COMMAND" | grep -qE 'rm\s+-[rf]*\s+[/~]|git\s+reset\s+--hard|git\s+clean\s+-[fd]+'; then
        echo "BLOCKED: Destructive command piped to shell" >&2
        exit 2
    fi
fi
exit 0
