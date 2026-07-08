#!/usr/bin/env bash
# normalize-mp3.sh — Convert MP3s to DFPlayer Mini (TonUINO AiO) compatible format
# Usage: ./normalize-mp3.sh [--dry-run] /path/to/directory
# Only re-encodes files that fail DFPlayer compatibility checks.
# In-place: temp file → mv (safe for spaces/special chars)

set -euo pipefail

VERSION="1.2.0"

# --- Config ----------------------------------------------------
BITRATE_MAX=192000        # Max bitrate in bps (192 kbps)
ID3_SIZE_MAX=1024         # Max ID3 tag size in bytes
TARGET_SAMPLE_RATE=44100  # DFPlayer-required sample rate
LAME_BITRATE="192k"       # Re-encode target
XATTR_NAME="user.mp3_normalize"  # xattr for mtime cache (value: file mtime as seconds since epoch)
NORMALIZE_XATTR="${NORMALIZE_XATTR:-1}"  # 1 = xattr caching enabled (default), 0 = disabled
NORMALIZE_LOCKFILE="${NORMALIZE_LOCKFILE:-}"  # Set via env for systemd timer runs

# --- Helpers ---------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { log "WARN: $*"; }
err()  { log "ERROR: $*"; }

check_deps() {
    for cmd in ffprobe ffmpeg python3; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "FATAL: $cmd not found in PATH" >&2
            exit 1
        fi
    done
    # xattr tools: warn if missing (caching disabled, but script still works)
    if [ "$NORMALIZE_XATTR" = "1" ]; then
        for cmd in setfattr getfattr; do
            if ! command -v "$cmd" &>/dev/null; then
                warn "$cmd not found — xattr caching disabled"
            fi
        done
    fi
}

# --- Python check (embedded) -----------------------------------
# Reads ffprobe JSON from stdin, opens file for binary checks.
# Outputs key=value pairs: sample_rate, bit_rate, vbr, has_apic, id3_size
analyze_mp3() {
    python3 -c "
import json, struct, sys

ffprobe = json.load(sys.stdin)
path = sys.argv[1]
sr = br = vbr = 'unknown'
has_apic = False
id3_size = 0

try:
    # Stream info from ffprobe
    for s in ffprobe.get('streams', []):
        if s.get('codec_type') == 'audio':
            sr = s.get('sample_rate', 'unknown')
            br = s.get('bit_rate', 'unknown')
            break
    has_apic = any(s.get('codec_type') == 'video' for s in ffprobe.get('streams', []))

    # Binary checks on the file
    with open(path, 'rb') as f:
        # ID3v2 size
        if f.read(3) == b'ID3':
            f.seek(6)
            b = f.read(4)
            id3_size = (b[0]<<21)|(b[1]<<14)|(b[2]<<7)|b[3]
            offset = 10 + id3_size
        else:
            id3_size = 0
            f.seek(0)
            offset = 0

        # MPEG frame → side info → Xing/VBRI/Info marker
        f.seek(offset)
        frame = f.read(4)
        if len(frame) == 4 and frame[0] == 0xFF and (frame[1] & 0xE0) == 0xE0:
            mpeg_ver = (frame[1] >> 3) & 3
            layer = (frame[1] >> 1) & 3
            if layer == 1:
                has_crc = (frame[1] & 1) == 0
                channel_mode = (frame[3] >> 6) & 3
                is_mono = (channel_mode == 3)
                side_info = (17 if is_mono else 32) if mpeg_ver == 3 else (9 if is_mono else 17)
                xing_off = offset + 4 + (2 if has_crc else 0) + side_info
                f.seek(xing_off)
                marker = f.read(4)
                if marker in (b'Xing', b'Info'):
                    flags = struct.unpack('>I', f.read(4))[0]
                    vbr = 'vbr' if (flags & 0x01) else 'cbr'
                elif marker == b'VBRI':
                    vbr = 'vbr'
except Exception:
    pass  # Corrupt file → leave all values at defaults

print(f'sample_rate={sr}')
print(f'bit_rate={br}')
print(f'vbr={vbr}')
print(f'has_apic={has_apic}')
print(f'id3_size={id3_size}')
" "$1"
}

# --- Core logic ------------------------------------------------

# Get cached mtime from xattr (returns empty string if no xattr)
get_cached_mtime() {
    getfattr -n "$XATTR_NAME" --only-values "$1" 2>/dev/null || true
}

# Set cached mtime xattr on a file
set_cached_mtime() {
    setfattr -n "$XATTR_NAME" -v "$1" "$2" 2>/dev/null || true
}

# Re-encode a file to DFPlayer-compatible format
# Uses temp file → mv for in-place safety
reencode_file() {
    local input="$1"
    local dry_run="$2"
    local dir
    dir=$(dirname "$input")
    local basename
    basename=$(basename "$input")
    local stem="${basename%.*}"
    local tmp="${dir}/${stem}.tmp.mp3"

    local size_before
    size_before=$(stat -c%s "$input" 2>/dev/null || echo 0)

    if [ "$dry_run" = "true" ]; then
        log "  DRY-RUN: would re-encode $basename (${size_before} bytes)"
        STATS_CONVERTED=$((STATS_CONVERTED + 1))
        return 0
    fi

    log "  ENCODE: $basename (${size_before} bytes)"

    if ffmpeg -v error -i "$input" -map 0:a \
        -c:a libmp3lame -b:a "$LAME_BITRATE" \
        -map_metadata -1 -ar "$TARGET_SAMPLE_RATE" -ac 2 \
        -y "$tmp" 2>/dev/null; then

        local size_after
        size_after=$(stat -c%s "$tmp" 2>/dev/null || echo 0)

        # Replace original (atomic: mv within same FS is rename)
        mv "$tmp" "$input"
        log "    DONE: $((size_before / 1024))KB → $((size_after / 1024))KB"
        STATS_CONVERTED=$((STATS_CONVERTED + 1))
        # Set cache after successful re-encode
        if [ "$NORMALIZE_XATTR" = "1" ]; then
            local new_mtime
            new_mtime=$(stat -c %Y "$input" 2>/dev/null || echo 0)
            set_cached_mtime "$new_mtime" "$input"
        fi
        return 0
    else
        err "    FFMPEG FAILED for $basename"
        rm -f "$tmp"
        STATS_ERRORS=$((STATS_ERRORS + 1))
        return 1
    fi
}

# --- Main ------------------------------------------------------

main() {
    local dry_run="false"
    local target_dir=""

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run="true"; shift;;
            -*) err "Unknown option: $1"; exit 1;;
            *) target_dir="$1"; shift;;
        esac
    done

    if [ -z "$target_dir" ]; then
        echo "Usage: $(basename "$0") [--dry-run] /path/to/directory" >&2
        echo "  Recursively normalizes MP3 files for DFPlayer Mini (TonUINO AiO)" >&2
        echo "  Only re-encodes files that fail compatibility checks." >&2
        echo "" >&2
        echo "  --dry-run  Show what would be done without modifying files" >&2
        exit 1
    fi

    if [ ! -d "$target_dir" ]; then
        echo "ERROR: Directory not found: $target_dir" >&2
        exit 1
    fi

    check_deps

    # --- Lockfile mechanism (optional, only when NORMALIZE_LOCKFILE is set) ---
    if [ -n "$NORMALIZE_LOCKFILE" ]; then
        if [ -f "$NORMALIZE_LOCKFILE" ]; then
            log "Another normalize-mp3.sh is already running (lockfile: $NORMALIZE_LOCKFILE). Exiting."
            exit 0
        fi
        touch "$NORMALIZE_LOCKFILE"
        trap 'rm -f "$NORMALIZE_LOCKFILE"' EXIT
    fi

    STATS_SKIPPED=0
    STATS_CACHED=0
    STATS_CONVERTED=0
    STATS_ERRORS=0

    log "============================================="
    log "normalize-mp3.sh v${VERSION}"
    if [ "$dry_run" = "true" ]; then
        log "*** DRY-RUN MODE — no files will be modified ***"
    fi
    log "Target: $target_dir"
    log "Config: max_bitrate=${BITRATE_MAX}bps, max_id3=${ID3_SIZE_MAX}B, target_sr=${TARGET_SAMPLE_RATE}Hz"
    log "Re-encode: libmp3lame ${LAME_BITRATE} CBR, strip metadata"
    log "============================================="

    # Count total
    local total
    total=$(find "$target_dir" -type f -name "*.mp3" | wc -l)
    log "Total MP3 files found: $total"

    if [ "$total" -eq 0 ]; then
        log "No MP3 files found. Nothing to do."
        log "============================================="
        return 0
    fi

    # --- Phase 1: Check-Phase ---
    local encode_list
    encode_list=$(mktemp /tmp/normalize-encode-list-XXXXXX.txt)
    trap 'rm -f "$encode_list" "$NORMALIZE_LOCKFILE"' EXIT

    local queued=0
    local count=0
    while IFS= read -r -d '' file; do
        count=$((count + 1))
        log "[$count/$total] Checking: $file"

        # xattr cache check (skip if file unchanged since last processing)
        if [ "$NORMALIZE_XATTR" = "1" ]; then
            local cached_mtime
            cached_mtime=$(get_cached_mtime "$file")
            if [ -n "$cached_mtime" ]; then
                local current_mtime
                current_mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
                if [ "$cached_mtime" = "$current_mtime" ]; then
                    STATS_CACHED=$((STATS_CACHED + 1))
                    continue
                fi
            fi
        fi

        # Consolidated check: single ffprobe + single Python
        local analysis
        analysis=$(ffprobe -v error -print_format json -show_streams -show_format "$file" 2>/dev/null \
            | analyze_mp3 "$file" 2>/dev/null || true)

        local srate="" brate="" vbr="" has_apic="" id3_size=""
        if [ -n "$analysis" ]; then
            while IFS='=' read -r key value; do
                case "$key" in
                    sample_rate) srate="$value";;
                    bit_rate)    brate="$value";;
                    vbr)         vbr="$value";;
                    has_apic)    has_apic="$value";;
                    id3_size)    id3_size="$value";;
                esac
            done <<< "$analysis"
        fi

        # Validate all criteria
        local issues=()
        if [ -n "$srate" ] && [ "$srate" != "$TARGET_SAMPLE_RATE" ]; then
            issues+=("sample_rate=${srate}Hz")
        fi
        if [ -n "$brate" ] && [ "$brate" -gt "$BITRATE_MAX" ] 2>/dev/null; then
            issues+=("bitrate=$((brate / 1000))kbps")
        fi
        case "$vbr" in
            vbr) issues+=("vbr");;
        esac
        if [ "$has_apic" = "True" ]; then
            issues+=("has_apic")
        fi
        if [ -n "$id3_size" ] && [ "$id3_size" -gt "$ID3_SIZE_MAX" ] 2>/dev/null; then
            issues+=("id3=$((id3_size / 1024))KB")
        fi
        if [ -n "$srate" ]; then
            case "$srate" in
                32000|44100|48000) ;;
                *) issues+=("mpeg2_sample_rate=${srate}Hz");;
            esac
        fi

        if [ ${#issues[@]} -gt 0 ]; then
            log "  FAIL: $file"
            for issue in "${issues[@]}"; do
                log "    → $issue"
            done
            printf '%s\0' "$file" >> "$encode_list"
            queued=$((queued + 1))
        else
            # Compatible: set cache so future runs skip
            if [ "$NORMALIZE_XATTR" = "1" ] && [ "$dry_run" != "true" ]; then
                local current_mtime
                current_mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
                set_cached_mtime "$current_mtime" "$file"
            fi
            STATS_SKIPPED=$((STATS_SKIPPED + 1))
        fi
    done < <(find "$target_dir" -type f -name "*.mp3" -print0)

    log "Check phase done: $queued files queued for re-encoding"

    # --- Phase 2: Encode-Phase (parallel, only when not --dry-run) ---
    if [ "$dry_run" = "true" ]; then
        # Dry-run: just count and log, don't encode
        while IFS= read -r -d '' file; do
            log "  DRY-RUN: would re-encode $file"
            STATS_CONVERTED=$((STATS_CONVERTED + 1))
        done < "$encode_list"
    elif [ -s "$encode_list" ]; then
        log "============================================="
        log "Encode phase: $queued files, parallel (max 3)"
        log "============================================="

        # Export variables and function for subprocesses
        export LAME_BITRATE TARGET_SAMPLE_RATE NORMALIZE_LOCKFILE NORMALIZE_XATTR
        export -f reencode_file set_cached_mtime log err

        # Parallel encode — stats via file counting (subshells can't modify parent vars)
        local encode_log
        encode_log=$(mktemp /tmp/normalize-encode-log-XXXXXX.txt)
        xargs -0 -P 3 -n 1 -I {} bash -c 'reencode_file "$@"' _ {} < "$encode_list" | tee "$encode_log" || true
        STATS_CONVERTED=$queued
        STATS_ERRORS=$(grep -c "FFMPEG FAILED" "$encode_log" 2>/dev/null) || STATS_ERRORS=0
        STATS_CONVERTED=$((STATS_CONVERTED - STATS_ERRORS))
        rm -f "$encode_log"
    fi

    log "============================================="
    log "SUMMARY: $total total | $STATS_CACHED cached | $STATS_SKIPPED skipped (OK) | $STATS_CONVERTED converted | $STATS_ERRORS errors"
    log "============================================="

    rm -f "$encode_list"
}

main "$@"
