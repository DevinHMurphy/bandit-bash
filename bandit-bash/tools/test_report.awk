# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     test_report.awk
# Author:
# Created:  November 16, 2026
# Modified: November 16, 2026
# ==============================================================================
# Writes the test report, one HTML page, to standard output. tools/run_tests.sh runs it about every
# 2 seconds while suites run and once at the end, and swaps the page in whole, so a browser never
# reads half of one. POSIX awk only (Git Bash's gawk, macOS's awk).
#
# Input: the run's suites.tsv, one line per row in the order found: name, file stem, description.
# Beside it in the log folder, per stem: <stem>.log (the suite's output), .start and .end (epoch
# seconds) and .status (the runner's verdict word; the runner judges, this script only shows).
#
# Variables (-v): logs, the log folder; now, started (epoch seconds) and started_text; phase,
# running, done or interrupted; history, the history file (may be missing); run_id; full, 1 for a
# full run; broken, the runner's regex for lines that break a run; rows_out, where the done phase
# writes this run's history rows; iso, this run's date for those rows.
#
# Reads from the suites: the summary line "--- N passed, M failed[, K skipped] ---", PASS, FAIL
# and SKIP lines while a suite runs, and the group timer's "TIME  <ms> ms  <group>" lines
# (tests/group_clock.gd). A suite's time is compared with its last PASS in the history; the total
# with the last full run that passed.
# ==============================================================================

BEGIN {
	FS = "\t"
	rows = 0
	groups = 0
	max_secs = 0
	if (history != "") {
		read_history()
	}
}

{
	rows++
	name[rows] = $1
	stem[rows] = $2
	about[rows] = $3
	read_suite(rows)
}

END {
	summarize()
	page_head()
	page_header()
	page_failures()
	page_suites()
	page_groups()
	page_foot()
	if (phase == "done" && rows_out != "") {
		write_history_rows()
	}
}

# The last PASS time of each suite, and the last full run that passed, from earlier runs.
function read_history(    line, f, n) {
	while ((getline line < history) > 0) {
		n = split(line, f, "\t")
		if (n < 9 || f[1] == run_id) {
			continue
		}
		if (f[4] == "TOTAL") {
			if (f[3] == "full" && f[5] == "PASS") {
				base_total = f[6]
			}
		} else if (f[5] == "PASS") {
			base_secs[f[4]] = f[6]
		}
	}
	close(history)
}

# Reads one row's files: its status, times, counts, failing lines and group times.
function read_suite(i,    path, line, f, n, k, ring, seen, pattern) {
	path = logs "/" stem[i] ".log"
	status[i] = read_word(path ".status")
	start_at[i] = read_word(path ".start")
	end_at[i] = read_word(path ".end")
	passed[i] = 0
	failed[i] = 0
	skipped[i] = 0
	has_summary[i] = 0
	lines[i] = ""
	line_count[i] = 0
	pattern = "^FAIL|" broken
	if (stem[i] == "launch") {
		pattern = broken "|^ERROR:|^WARNING:"
	}
	seen = 0
	while ((getline line < path) > 0) {
		seen++
		ring[seen % 15] = line
		if (line ~ /^PASS/) {
			passed[i]++
		} else if (line ~ /^FAIL/) {
			failed[i]++
		} else if (line ~ /^SKIP/) {
			skipped[i]++
		}
		if (line ~ /^--- [0-9]+ passed/) {
			has_summary[i] = 1
			read_summary(i, line)
		}
		if (line ~ /^TIME  [0-9]+ ms  /) {
			add_group(i, line)
		}
		if (line ~ pattern && line_count[i] < 40) {
			lines[i] = lines[i] line "\n"
			line_count[i]++
		}
	}
	close(path)
	# A run that broke with no failing line shows how its log ended instead.
	if (line_count[i] == 0 && (status[i] == "FAIL" || status[i] == "HUNG")) {
		k = seen - 14
		if (k < 1) {
			k = 1
		}
		for (; k <= seen; k++) {
			lines[i] = lines[i] ring[k % 15] "\n"
		}
		tail_only[i] = 1
	}
	if (start_at[i] == "") {
		secs[i] = 0
	} else if (end_at[i] != "") {
		secs[i] = end_at[i] - start_at[i]
	} else {
		secs[i] = now - start_at[i]
	}
	if (secs[i] > max_secs) {
		max_secs = secs[i]
	}
}

function read_summary(i, line,    f, n, k) {
	n = split(line, f, " ")
	for (k = 2; k <= n; k++) {
		if (f[k] ~ /^passed/) {
			passed[i] = f[k - 1] + 0
		} else if (f[k] ~ /^failed/) {
			failed[i] = f[k - 1] + 0
		} else if (f[k] ~ /^skipped/) {
			skipped[i] = f[k - 1] + 0
		}
	}
}

function add_group(i, line,    f) {
	split(line, f, " ")
	match(line, /^TIME  [0-9]+ ms  /)
	groups++
	group_row[groups] = i
	group_ms[groups] = f[2] + 0
	group_name[groups] = substr(line, RLENGTH + 1)
}

# The first word of a small file, or "" when it is missing.
function read_word(path,    word) {
	word = ""
	if ((getline word < path) > 0) {
		sub(/[ \t\r]+.*$/, "", word)
	}
	close(path)
	return word
}

# The shown state of row i: its verdict, or running, waiting, stopped or not run.
function state_of(i) {
	if (status[i] != "") {
		return status[i]
	}
	if (start_at[i] != "") {
		return phase == "running" ? "RUNNING" : "STOPPED"
	}
	return phase == "running" ? "WAITING" : "NOT RUN"
}

function summarize(    i, s) {
	done_rows = 0
	failures = 0
	total_passed = 0
	total_failed = 0
	total_skipped = 0
	for (i = 1; i <= rows; i++) {
		s = state_of(i)
		if (status[i] != "") {
			done_rows++
		}
		if (s == "FAIL" || s == "HUNG") {
			failures++
		}
		total_passed += passed[i]
		total_failed += failed[i]
		total_skipped += skipped[i]
	}
	wall = now - started
	if (phase == "running") {
		verdict = "RUNNING"
	} else if (phase == "interrupted") {
		verdict = "INTERRUPTED"
	} else {
		verdict = failures > 0 ? "FAILURES" : "ALL PASS"
	}
}

function esc(text) {
	gsub(/&/, "\\&amp;", text)
	gsub(/</, "\\&lt;", text)
	gsub(/>/, "\\&gt;", text)
	gsub(/"/, "\\&quot;", text)
	return text
}

# A time in seconds as "42 s" or "3:05".
function clock(s) {
	s = int(s + 0.5)
	if (s < 60) {
		return s " s"
	}
	return sprintf("%d:%02d", int(s / 60), s % 60)
}

# The change against a baseline as a span: slower or faster only past 2 s and 10%.
function delta(s, base,    d, margin, kind, text) {
	if (base == "") {
		return "<span class=\"delta\">no earlier pass</span>"
	}
	d = s - base
	margin = base * 0.1
	if (margin < 2) {
		margin = 2
	}
	kind = "same"
	if (d > margin) {
		kind = "slower"
	} else if (-d > margin) {
		kind = "faster"
	}
	if (d >= 0) {
		text = "+" clock(d)
	} else {
		text = "&minus;" clock(-d)
	}
	return "<span class=\"delta " kind "\" title=\"last pass: " clock(base) "\">" text \
		" vs " clock(base) "</span>"
}

function pill(s,    kind) {
	kind = tolower(s)
	gsub(/[^a-z]/, "-", kind)
	return "<span class=\"pill " kind "\">" s "</span>"
}

function log_link(i) {
	return "<a href=\"" esc(stem[i]) ".log\">log</a>"
}

function page_head() {
	print "<!doctype html>"
	print "<html lang=\"en\"><head><meta charset=\"utf-8\">"
	print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
	if (phase == "running") {
		print "<meta http-equiv=\"refresh\" content=\"2\">"
	}
	print "<title>Bandit Bash tests</title>"
	print "<style>"
	print ":root{--bg:#f7f7f5;--panel:#ffffff;--text:#1d1d1b;--muted:#6b6b66;--line:#e2e1dc;"
	print "--pass:#1f7a3f;--pass-bg:#e3f3e8;--fail:#b3261e;--fail-bg:#fbe5e3;--run:#2457a6;"
	print "--run-bg:#e2ebf8;--wait:#7a7a74;--wait-bg:#ededea;--warn:#8a5a00;--warn-bg:#fbefd5;"
	print "--bar:#9fb6d9;--bar-fail:#e08a84;--bar-pass:#8cc6a0;--code:#f1f0ec;color-scheme:light}"
	print "@media (prefers-color-scheme:dark){:root{--bg:#161615;--panel:#1f1f1d;--text:#ecebe6;"
	print "--muted:#9c9b94;--line:#33332f;--pass:#6fd18f;--pass-bg:#16301f;--fail:#ff8a80;"
	print "--fail-bg:#3a1a17;--run:#8fb4ff;--run-bg:#1a2740;--wait:#a3a39c;--wait-bg:#2a2a27;"
	print "--warn:#f0c060;--warn-bg:#3a2e12;--bar:#3e5a86;--bar-fail:#8e3a33;--bar-pass:#2f6b45;"
	print "--code:#262624;color-scheme:dark}}"
	print "*{box-sizing:border-box}"
	print "body{margin:0;background:var(--bg);color:var(--text);"
	print "font:15px/1.45 system-ui,-apple-system,\"Segoe UI\",sans-serif}"
	print "main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}"
	print "h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 10px}"
	print ".meta{color:var(--muted);font-size:13px;word-break:break-all}"
	print ".head{display:flex;flex-wrap:wrap;gap:12px 28px;align-items:center;margin:14px 0}"
	print ".big{font-size:28px;font-weight:650}.stat{display:flex;flex-direction:column}"
	print ".stat b{font-size:20px;font-variant-numeric:tabular-nums}"
	print ".stat span{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em}"
	print ".pill{display:inline-block;padding:2px 9px;border-radius:99px;font-size:12px;"
	print "font-weight:650;letter-spacing:.03em;white-space:nowrap}"
	print ".pass,.all-pass{color:var(--pass);background:var(--pass-bg)}"
	print ".fail,.hung,.failures{color:var(--fail);background:var(--fail-bg)}"
	print ".exit-crash,.stopped,.interrupted{color:var(--warn);background:var(--warn-bg)}"
	print ".running{color:var(--run);background:var(--run-bg)}"
	print ".waiting,.not-run{color:var(--wait);background:var(--wait-bg)}"
	print ".big.pill{font-size:20px;padding:4px 16px}"
	print "table{width:100%;border-collapse:collapse;background:var(--panel);"
	print "border:1px solid var(--line);border-radius:8px;overflow:hidden}"
	print "th,td{padding:8px 10px;text-align:left;border-top:1px solid var(--line);vertical-align:top}"
	print "th{border-top:0;font-size:12px;color:var(--muted);font-weight:600;text-transform:uppercase;"
	print "letter-spacing:.04em}"
	print "td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}"
	print ".name{font-weight:600;white-space:nowrap}.about{color:var(--muted);font-size:13px}"
	print ".zero{color:var(--muted)}.bad{color:var(--fail);font-weight:650}"
	print ".time{min-width:220px}.bar{height:8px;border-radius:4px;background:var(--line);margin:4px 0}"
	print ".bar i{display:block;height:100%;border-radius:4px;background:var(--bar)}"
	print ".bar i.pass{background:var(--bar-pass)}.bar i.fail,.bar i.hung{background:var(--bar-fail)}"
	print ".inline{display:flex;align-items:center;gap:10px}.inline .bar{flex:1;margin:0}"
	print ".inline span{min-width:56px;text-align:right;font-variant-numeric:tabular-nums}"
	print ".delta{font-size:12px;color:var(--muted)}.delta.slower{color:var(--fail)}"
	print ".delta.faster{color:var(--pass)}"
	print ".card{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--fail);"
	print "border-radius:8px;padding:10px 14px;margin:0 0 12px}"
	print ".card h3{margin:0 0 6px;font-size:15px;display:flex;gap:10px;align-items:center}"
	print "pre{margin:0;background:var(--code);padding:10px;border-radius:6px;overflow-x:auto;"
	print "font:12px/1.5 ui-monospace,Consolas,monospace;white-space:pre-wrap;word-break:break-word}"
	print "a{color:var(--run)}"
	print "@media (max-width:700px){.about{display:none}.time{min-width:120px}}"
	print "</style></head><body><main>"
}

function page_header(    text) {
	print "<h1>Bandit Bash tests</h1>"
	print "<div class=\"meta\">Started " esc(started_text) " &middot; logs " esc(logs) "</div>"
	print "<div class=\"head\">"
	text = verdict
	if (phase == "running") {
		text = "RUNNING " done_rows " / " rows
	}
	print "<span class=\"big pill " (verdict == "ALL PASS" ? "all-pass" : tolower(verdict)) "\">" \
		text "</span>"
	print "<div class=\"stat\"><b>" clock(wall) "</b><span>" \
		(phase == "running" ? "elapsed" : "total") "</span></div>"
	if (full == 1 && phase != "running") {
		print "<div class=\"stat\"><b>" delta(wall, base_total) "</b><span>vs last full pass</span></div>"
	}
	print "<div class=\"stat\"><b>" total_passed "</b><span>passed</span></div>"
	print "<div class=\"stat\"><b class=\"" (total_failed > 0 ? "bad" : "zero") "\">" total_failed \
		"</b><span>failed</span></div>"
	print "<div class=\"stat\"><b class=\"" (total_skipped > 0 ? "" : "zero") "\">" total_skipped \
		"</b><span>skipped</span></div>"
	print "</div>"
}

# The failing rows first, each open with its failing lines.
function page_failures(    i, s) {
	if (failures == 0) {
		return
	}
	print "<h2>Failures</h2>"
	for (i = 1; i <= rows; i++) {
		s = state_of(i)
		if (s != "FAIL" && s != "HUNG") {
			continue
		}
		print "<div class=\"card\"><h3>" esc(name[i]) " " pill(s) " " log_link(i) "</h3>"
		if (tail_only[i]) {
			print "<div class=\"about\">No failing line; the log ends:</div>"
		}
		print "<pre>" esc(lines[i]) "</pre></div>"
	}
}

function count_cell(n, kind) {
	if (n == 0) {
		return "<td class=\"num zero\">0</td>"
	}
	return "<td class=\"num" (kind == "bad" ? " bad" : "") "\">" n "</td>"
}

function page_suites(    i, s, width, desc, time_text) {
	print "<h2>Suites</h2>"
	print "<table><thead><tr><th>Suite</th><th>Status</th><th class=\"num\">Passed</th>"
	print "<th class=\"num\">Failed</th><th class=\"num\">Skipped</th><th>Time</th><th></th></tr>"
	print "</thead><tbody>"
	for (i = 1; i <= rows; i++) {
		s = state_of(i)
		desc = about[i]
		if (desc == "") {
			desc = "No SUITE_DESCRIPTION in its run_all.gd."
		}
		width = max_secs > 0 ? int(100 * secs[i] / max_secs + 0.5) : 0
		time_text = ""
		if (start_at[i] != "") {
			time_text = clock(secs[i])
			if (status[i] != "" && name[i] != "launch") {
				time_text = time_text " " delta(secs[i], base_secs[name[i]])
			}
		}
		printf "<tr><td><div class=\"name\">%s</div><div class=\"about\">%s</div></td>", \
			esc(name[i]), esc(desc)
		printf "<td>%s</td>", pill(s)
		if (name[i] == "launch") {
			printf "<td class=\"num zero\">&ndash;</td><td class=\"num zero\">&ndash;</td>"
			printf "<td class=\"num zero\">&ndash;</td>"
		} else {
			printf "%s%s%s", count_cell(passed[i], ""), count_cell(failed[i], "bad"), \
				count_cell(skipped[i], "")
		}
		printf "<td class=\"time\"><div class=\"bar\"><i class=\"%s\" style=\"width:%d%%\"></i></div>%s</td>", \
			tolower(s), width, time_text
		printf "<td>%s</td></tr>\n", (start_at[i] != "" ? log_link(i) : "")
	}
	print "</tbody></table>"
}

# The 10 slowest groups across every suite, slowest first.
function page_groups(    shown, k, best, j, top_ms, width) {
	print "<h2>Slowest test groups</h2>"
	if (groups == 0) {
		print "<div class=\"meta\">No group times yet.</div>"
		return
	}
	print "<table><thead><tr><th>Group</th><th>Suite</th><th>Time</th></tr></thead><tbody>"
	for (shown = 0; shown < 10 && shown < groups; shown++) {
		best = 0
		for (j = 1; j <= groups; j++) {
			if (!(j in used) && (best == 0 || group_ms[j] > group_ms[best])) {
				best = j
			}
		}
		used[best] = 1
		if (shown == 0) {
			top_ms = group_ms[best]
		}
		width = top_ms > 0 ? int(100 * group_ms[best] / top_ms + 0.5) : 0
		printf "<tr><td>%s</td><td class=\"about\">%s</td>", esc(group_name[best]), \
			esc(name[group_row[best]])
		printf "<td class=\"time\"><div class=\"inline\"><div class=\"bar\"><i style=\"width:%d%%\"></i>", \
			width
		printf "</div><span>%.1f s</span></div></td></tr>\n", group_ms[best] / 1000
	}
	print "</tbody></table>"
}

function page_foot() {
	print "</main></body></html>"
}

# This run's rows for the history file: one per row, then the run's TOTAL.
function write_history_rows(    i, kind) {
	kind = full == 1 ? "full" : "partial"
	for (i = 1; i <= rows; i++) {
		if (status[i] == "") {
			continue
		}
		printf "%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\n", run_id, iso, kind, name[i], status[i], \
			secs[i], passed[i], failed[i], skipped[i] > rows_out
	}
	printf "%s\t%s\t%s\tTOTAL\t%s\t%d\t%d\t%d\t%d\n", run_id, iso, kind, \
		(failures > 0 ? "FAIL" : "PASS"), wall, total_passed, total_failed, total_skipped > rows_out
	close(rows_out)
}
