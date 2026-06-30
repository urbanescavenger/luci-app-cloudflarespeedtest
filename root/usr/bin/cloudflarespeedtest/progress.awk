# progress.awk - filter CloudflareSpeedTest (cdnspeedtest, v2.3.4) stdout into a
# clean, throttled speed-test log with overall progress.
#
# The core tool (cheggaaa/pb v3 progress bar) refreshes each progress line in
# place with \r, shaped like:
#     <current> / <total> [----↖_____] 可用: <count>     (latency phase)
#     <current> / <total> [----↖_____]                  (download phase)
# i.e. the "current / total" counters have NO brackets, and the "[...]" is the
# graphical bar (arrows/dashes), not the numbers. The rpcd log reader strips the
# "[...]" bar but leaves the \r-mangled counters unreadable.
#
# Fed via `tr "\r" "\n"`, this filter:
#   * detects progress lines (start with "n / total" counters AND contain a "["
#     bar) and collapses the high-frequency refresh spam into throttled
#     "进度: <phase> <tested>/<total> (<pct>%)" lines (~every 1%),
#   * tracks the phase via the "开始延迟测速" / "开始下载测速" markers (and the
#     "可用:" hint),
#   * passes through every other line (markers, summaries, CSV results) verbatim.
#
# Usage:  ... | tr "\r" "\n" | awk -f /usr/bin/cloudflarespeedtest/progress.awk

BEGIN {
    total = 0
    prev_total = 0
    tested = 0
    last_printed = 0
    step = 1
    phase = "测速"
}

# blank lines (e.g. from leading \r after the tr conversion) are noise
/^$/ {
    next
}

# phase markers: pass through, but remember which phase we are in
/开始延迟测速/ {
    phase = "延迟测速"
    print
    next
}
/开始下载测速/ {
    phase = "下载测速"
    print
    next
}

# progress line: starts with "current / total" counters and contains a "[" bar
match($0, /^ *[0-9]+ *\/ *[0-9]+/) && index($0, "[") > 0 {
    token = substr($0, RSTART, RLENGTH)
    split(token, parts, "/")
    tested = parts[1] + 0
    total = parts[2] + 0

    # latency progress carries a "可用:" counter; use it as a phase hint too
    if (index($0, "可用") > 0)
        phase = "延迟测速"

    # recompute the throttle step whenever the total changes (new phase)
    if (total != prev_total) {
        step = int(total / 100)
        if (step < 1)
            step = 1
        last_printed = 0
        prev_total = total
    }

    # emit progress on the first update of a phase, at every ~1% step, and at 100%
    if (total > 0 && (last_printed == 0 || tested == total || tested - last_printed >= step)) {
        pct = int(tested * 100 / total)
        printf "进度: %s %d/%d (%d%%)\n", phase, tested, total, pct
        fflush()
        last_printed = tested
    }

    next
}

# any other line: pass through verbatim
{
    print
}