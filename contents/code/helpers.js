.pragma library

// Shared helpers for the main widget and the settings pages.

var US = "\x1f";
var counter = 0;

// Makes every command string unique, so the "executable" data engine runs it again.
function uniq() {
    counter++;
    return " # " + Date.now() + "-" + counter;
}

// Quote a value for /bin/sh.
function q(s) {
    var v = (s === undefined || s === null) ? "" : String(s);
    return "'" + v.replace(/'/g, "'\\''") + "'";
}

// Escape text for the notification body (basic markup is allowed there).
function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function urlToPath(u) {
    var s = String(u).replace(/^file:\/\//, "");
    try {
        return decodeURIComponent(s);
    } catch (e) {
        return s;
    }
}

function repoName(repo) {
    var s = String(repo || "").replace(/\/+$/, "").replace(/\.git$/, "");
    var parts = s.split(/[\/:]/);
    return parts[parts.length - 1] || s;
}

// Turn a git remote (ssh, scp-like or https) into a browsable https URL.
function webUrl(remote) {
    var r = String(remote || "").trim();
    var m;
    if (!r) {
        return "";
    }
    if ((m = r.match(/^[\w.-]+@([^:\/]+):(.+)$/))) {
        r = "https://" + m[1] + "/" + m[2];
    } else if ((m = r.match(/^ssh:\/\/(?:[^@\/]+@)?([^:\/]+)(?::\d+)?\/(.+)$/))) {
        r = "https://" + m[1] + "/" + m[2];
    } else if (/^https?:\/\//.test(r)) {
        r = r.replace(/^(https?:\/\/)[^@\/]+@/, "$1");
    } else if ((m = r.match(/^git:\/\/([^\/]+)\/(.+)$/))) {
        r = "https://" + m[1] + "/" + m[2];
    } else {
        return "";
    }
    return r.replace(/\/+$/, "").replace(/\.git$/, "");
}

function commitUrl(base, hash) {
    return base ? base + "/commit/" + hash : "";
}

function newId() {
    return "r" + Date.now().toString(36) + Math.floor(Math.random() * 1679616).toString(36);
}

// Parse the "repos" setting (JSON array). keepEmpty = also keep entries without a path
// (the settings page needs them while a new repository is being filled in).
function parseRepos(json, keepEmpty) {
    var a;
    try {
        a = JSON.parse(json || "[]");
    } catch (e) {
        a = [];
    }
    if (!Array.isArray(a)) {
        return [];
    }
    var out = [];
    for (var i = 0; i < a.length; ++i) {
        var r = a[i];
        if (!r || typeof r !== "object" || (!r.path && !keepEmpty)) {
            continue;
        }
        out.push({
            id: r.id || newId(),
            name: r.name ? String(r.name) : "",
            path: r.path ? String(r.path) : "",
            branch: r.branch ? String(r.branch) : "",
            sshKey: r.sshKey ? String(r.sshKey) : "",
            tokenFile: r.tokenFile ? String(r.tokenFile) : "",
            enabled: r.enabled !== false
        });
    }
    return out;
}

// "main, dev release/1.x" -> ["main", "dev", "release/1.x"] (separated by commas, semicolons or spaces).
function splitBranches(s) {
    var parts = String(s || "").split(/[\s,;]+/);
    var out = [];
    for (var i = 0; i < parts.length; ++i) {
        if (parts[i] !== "" && out.indexOf(parts[i]) < 0) {
            out.push(parts[i]);
        }
    }
    return out;
}

// "ALL" (any case) or a pattern with * or ? (release/*) stands for every branch that matches.
var MAX_AUTO_BRANCHES = 30;

function isWildcardToken(t) {
    return /^all$/i.test(t) || /[*?]/.test(t);
}

function hasWildcard(s) {
    return splitBranches(s).some(isWildcardToken);
}

function tokenRegExp(t) {
    if (/^all$/i.test(t)) {
        return /^.*$/;
    }
    var re = String(t).replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".");
    return new RegExp("^" + re + "$");
}

// The branches to watch: the listed ones, then (alphabetically, main and master first) the ones among
// `available` that match an ALL / pattern entry. `available` = branch names found in the repository, or
// null if they are not known yet.
function resolveBranches(str, available) {
    var toks = splitBranches(str);
    var out = [];
    var pats = [];
    for (var i = 0; i < toks.length; ++i) {
        if (isWildcardToken(toks[i])) {
            pats.push(tokenRegExp(toks[i]));
        } else {
            out.push(toks[i]);
        }
    }
    if (pats.length > 0 && available) {
        var extra = available.filter(function(b) {
            return out.indexOf(b) < 0 && pats.some(function(re) { return re.test(b); });
        });
        var rank = function(b) { return b === "main" ? 0 : b === "master" ? 1 : 2; };
        extra.sort(function(a, b) {
            return rank(a) - rank(b) || (a < b ? -1 : a > b ? 1 : 0);
        });
        out = out.concat(extra.slice(0, MAX_AUTO_BRANCHES));
    }
    return out;
}

// The things the widget actually checks: one entry per repository and branch. A repository with
// several branches in its "branch" setting (or with ALL / a pattern, see resolveBranches; `discovered`
// maps repository id -> branch names found in it) becomes several entries. The first listed branch keeps
// the id of the repository (so the saved state of an existing single-branch repository still applies),
// all others get "<id>:<branch>". Every entry has parentId (the id of the repository setting), baseName
// (the name without the branch) and multi (true if the repository has more than one branch).
function expandRepos(repos, discovered) {
    var out = [];
    for (var i = 0; i < repos.length; ++i) {
        var r = repos[i];
        var branches = resolveBranches(r.branch, discovered ? discovered[r.id] : null);
        var listed = splitBranches(r.branch).filter(function(t) { return !isWildcardToken(t); }).length;
        var base = repoDisplayName(r);
        if (branches.length <= 1 && !hasWildcard(r.branch)) {
            out.push({
                id: r.id, parentId: r.id, name: r.name, baseName: base, multi: false,
                path: r.path, branch: branches.length === 1 ? branches[0] : "",
                sshKey: r.sshKey, tokenFile: r.tokenFile, enabled: r.enabled
            });
            continue;
        }
        for (var k = 0; k < branches.length; ++k) {
            var multi = branches.length > 1;
            out.push({
                id: (k === 0 && listed > 0) ? r.id : r.id + ":" + branches[k], parentId: r.id,
                name: multi ? base + " (" + branches[k] + ")" : r.name, baseName: base, multi: multi,
                path: r.path, branch: branches[k],
                sshKey: r.sshKey, tokenFile: r.tokenFile, enabled: r.enabled
            });
        }
    }
    return out;
}

function branchesCommand(script, o) {
    return "GCW_MODE=branches"
        + " GCW_REPO=" + q(o.repo)
        + " GCW_KEY=" + q(o.key)
        + " GCW_TOKEN_FILE=" + q(o.tokenFile)
        + " bash " + q(script) + uniq();
}

function parseBranches(stdout, stderr, exitCode) {
    var res = { ok: false, msg: "", code: "", branches: [] };
    var info = {};
    var lines = String(stdout || "").split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i];
        if (line.charAt(0) === "B" && line.charAt(1) === US) {
            res.branches.push(line.substring(2));
        } else {
            var k = line.indexOf("=");
            if (k > 0) {
                info[line.substring(0, k)] = line.substring(k + 1);
            }
        }
    }
    res.code = info.CODE || "";
    res.ok = info.STATUS === "ok";
    if (!res.ok) {
        res.msg = info.MSG || String(stderr || "").trim() || ("Listing the branches failed (exit code " + exitCode + ")");
    }
    return res;
}

function repoDisplayName(r) {
    return (r && (r.name || repoName(r.path))) || "";
}

function diffCommand(script, o) {
    return "GCW_REPO=" + q(o.repo)
        + " GCW_BRANCH=" + q(o.branch)
        + " GCW_HASH=" + q(o.hash)
        + " bash " + q(script) + uniq();
}

// Saves one file of a commit to the widget cache (openfile.sh); o = { repo, branch, hash, path }.
function openFileCommand(script, o) {
    return "GCW_REPO=" + q(o.repo)
        + " GCW_BRANCH=" + q(o.branch)
        + " GCW_HASH=" + q(o.hash)
        + " GCW_PATH=" + q(o.path)
        + " bash " + q(script) + uniq();
}

function parseOpenFile(stdout, stderr, exitCode) {
    var info = {};
    var lines = String(stdout || "").split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var k = lines[i].indexOf("=");
        if (k > 0) {
            info[lines[i].substring(0, k)] = lines[i].substring(k + 1);
        }
    }
    return {
        ok: info.STATUS === "ok" && !!info.FILE,
        file: info.FILE || "",
        msg: info.MSG || String(stderr || "").trim() || ("Failed (exit code " + exitCode + ")")
    };
}

// Path of the changed file named by a "diff --git a/X b/X" (or "diff --cc X") header; "" if unknown.
function diffHeaderPath(l) {
    var rest;
    if (l.indexOf("diff --git a/") === 0) {
        rest = l.substring(13);
        var n = (rest.length - 3) / 2;
        if (n === Math.floor(n) && n > 0 && rest.substr(n, 3) === " b/" && rest.substring(0, n) === rest.substring(n + 3)) {
            return rest.substring(0, n);
        }
        return "";
    }
    var m = l.match(/^diff --(?:cc|combined) (.+)$/);
    rest = m ? m[1] : "";
    return rest.charAt(0) === '"' ? "" : rest;
}

// Parse the output of diff.sh into display lines {t: type, s: text}.
// Types: head (commit header/message/stat), file, meta, hunk, add, del, ctx, and band: a section
// title added by this parser (k = hdr | msg | stat | diff), shown as a colored bar.
function parseDiff(stdout, stderr, exitCode) {
    var res = { ok: false, msg: "", lines: [], truncated: false };
    var text = String(stdout || "");
    var nl = text.indexOf("\n");
    var first = nl < 0 ? text : text.substring(0, nl);
    if (first !== "STATUS=ok") {
        var m = text.match(/^MSG=(.*)$/m);
        res.msg = m ? m[1] : (String(stderr || "").trim() || ("Failed (exit code " + exitCode + ")"));
        return res;
    }
    var raw = text.substring(nl + 1).split("\n");
    if (raw.length > 0 && raw[raw.length - 1] === "") {
        raw.pop();
    }
    if (raw.length > 4000) {
        raw = raw.slice(0, 4000);
        res.truncated = true;
    }
    var mode = "head";      // head -> meta (file header) -> body (hunks)
    var cur = null;         // the "file" line being described by the meta lines that follow it
    var hdrPart = true;     // still inside the commit / Author / Date lines
    var statBand = null;
    var nFiles = 0;
    res.lines.push({ t: "band", k: "hdr", s: "COMMIT" });
    for (var i = 0; i < raw.length; ++i) {
        // Control characters (e.g. the CR of CRLF files) would change the text layout.
        var l = raw[i].replace(/[\u0000-\u0008\u000b-\u001f\u2028\u2029]/g, "");
        var t;
        var mm;
        if (l.indexOf("diff --git ") === 0 || l.indexOf("diff --cc ") === 0 || l.indexOf("diff --combined ") === 0) {
            if (mode === "head") {
                res.lines.push({ t: "band", k: "diff", s: "DIFF" });
            }
            mode = "meta";
            t = "file";
            nFiles++;
            cur = { t: t, s: l, path: diffHeaderPath(l), status: "modified" };
            res.lines.push(cur);
            continue;
        } else if (mode === "head") {
            if (hdrPart && l === "") {
                // End of the header: the commit message follows.
                hdrPart = false;
                res.lines.push({ t: "band", k: "msg", s: "MESSAGE" });
                continue;
            }
            if (!hdrPart && l === "---") {
                // The separator between the message and the "git diff --stat" part.
                statBand = { t: "band", k: "stat", s: "CHANGED FILES" };
                res.lines.push(statBand);
                continue;
            }
            t = "head";
        } else if (l.indexOf("@@") === 0) {
            mode = "body";
            t = "hunk";
        } else if (mode === "meta") {
            t = "meta";
            if (cur) {
                if (l.indexOf("new file mode") === 0) {
                    cur.status = "added";
                } else if (l.indexOf("deleted file mode") === 0) {
                    cur.status = "deleted";
                } else if ((mm = l.match(/^rename to (.*)$/))) {
                    cur.status = "renamed";
                    cur.path = mm[1].charAt(0) === '"' ? "" : mm[1];
                } else if ((mm = l.match(/^\+\+\+ (.*?)\t?$/)) && mm[1] !== "/dev/null") {
                    cur.path = mm[1].charAt(0) === '"' ? "" : mm[1].replace(/^b\//, "");
                }
            }
        } else if (l.charAt(0) === "+") {
            t = "add";
        } else if (l.charAt(0) === "-") {
            t = "del";
        } else {
            t = "ctx";
        }
        res.lines.push({ t: t, s: l });
    }
    if (statBand && nFiles > 0) {
        statBand.s = "CHANGED FILES (" + nFiles + ")";
    }
    res.ok = true;
    return res;
}

function htmlEscape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function colored(color, text, extra) {
    return '<span style="color:' + color + (extra || "") + '">' + htmlEscape(text) + "</span>";
}

// Colored +++/--- bar of one "git diff --stat" line, e.g. " ++++---".
function statBar(rest, pal) {
    var parts = String(rest).split(/(\++|-+)/);
    var out = "";
    for (var i = 0; i < parts.length; ++i) {
        var p = parts[i];
        if (p === "") {
            continue;
        }
        out += p.charAt(0) === "+" ? colored(pal.pos, p)
             : p.charAt(0) === "-" ? colored(pal.neg, p)
             : htmlEscape(p);
    }
    return out;
}

// Position of each changed file's header line in the plain text of the rendered diff (see
// diffToHtml), so that a button can be placed next to it. Deleted files have no file to open.
// Every line is one paragraph: the plain text is the line plus a newline, and an empty line
// is rendered as a single space.
function diffFileMarks(lines) {
    var marks = [];
    var off = 0;
    for (var i = 0; i < lines.length; ++i) {
        var ln = lines[i];
        if (ln.t === "file" && ln.path && ln.status !== "deleted") {
            marks.push({ off: off, path: ln.path, status: ln.status });
        }
        off += (ln.s === "" ? 1 : ln.s.length) + 1;
    }
    return marks;
}

// Turns the parsed diff lines (see parseDiff) into rich text for a read-only TextArea, so that
// it can be selected and copied. pal: { text, muted, pos, neg, link, warn, bgAdd, bgDel, bgHunk, bgFile, bgBand, bgMsg }
// (CSS colors). One paragraph per line; the text of every line is kept exactly as git printed it.
function diffToHtml(lines, pal) {
    var out = [];
    var phase = "hdr";           // hdr (commit/Author/Date) -> msg -> stat
    var subjectDone = false;
    for (var i = 0; i < lines.length; ++i) {
        var t = lines[i].t;
        var s = lines[i].s;
        var color = pal.text;
        var bg = "";
        var body = "";
        var rightMargin = "";
        var topMargin = "";
        var m;

        if (t === "band") {
            // Section title: a colored bar across the whole width.
            if (lines[i].k === "msg") {
                phase = "msg";
            } else if (lines[i].k === "stat") {
                phase = "stat";
            }
            bg = pal.bgBand || pal.bgFile;
            body = colored(pal.text, s, ";font-weight:bold");
            if (lines[i].k !== "hdr") {
                topMargin = "margin-top:12px;";
            }
        } else if (s === "" && t !== "add" && t !== "del") {
            if (t === "head" && phase === "hdr") {
                phase = "msg";
            }
            if (t === "head" && phase === "msg") {
                bg = pal.bgMsg || "";
            }
            body = " ";
        } else if (t === "head") {
            if (phase === "hdr") {
                bg = pal.bgFile;
                if ((m = s.match(/^(commit )([0-9a-fA-F]+)(.*)$/))) {
                    body = colored(pal.muted, m[1]) + colored(pal.warn, m[2], ";font-weight:bold;font-size:larger")
                         + (m[3] ? colored(pal.muted, m[3]) : "");
                } else if ((m = s.match(/^(Author:\s*)(.*?)(\s*<[^>]*>)?\s*$/))) {
                    body = colored(pal.muted, m[1]) + colored(pal.link, m[2], ";font-weight:bold")
                         + (m[3] ? colored(pal.muted, m[3]) : "");
                } else if ((m = s.match(/^(Date:\s*)(.*)$/))) {
                    body = colored(pal.muted, m[1]) + colored(pal.text, m[2]);
                } else {
                    color = pal.muted;
                    body = htmlEscape(s);
                }
            } else if (phase === "msg") {
                bg = pal.bgMsg || "";
                if (!subjectDone && s.trim() !== "") {
                    subjectDone = true;
                    body = colored(pal.text, s, ";font-weight:bold;font-size:larger");
                } else {
                    body = htmlEscape(s);
                }
            } else if ((m = s.match(/^(\s*)(.*?)(\s+\|\s+)(\d+|Bin)(.*)$/))) {
                body = htmlEscape(m[1]) + colored(pal.link, m[2]) + colored(pal.muted, m[3])
                     + colored(pal.text, m[4], ";font-weight:bold") + statBar(m[5], pal);
            } else if ((m = s.match(/^(\s*\d+ files? changed)(?:,\s*(\d+ insertions?\(\+\)))?(?:,\s*(\d+ deletions?\(-\)))?\s*$/))) {
                body = colored(pal.muted, m[1])
                     + (m[2] ? colored(pal.muted, ", ") + colored(pal.pos, m[2]) : "")
                     + (m[3] ? colored(pal.muted, ", ") + colored(pal.neg, m[3]) : "");
            } else {
                color = pal.muted;
                body = htmlEscape(s);
            }
        } else if (t === "file") {
            bg = pal.bgFile;
            body = colored(pal.text, s, ";font-weight:bold");
            if (lines[i].path && lines[i].status !== "deleted" && pal.buttonSpace) {
                rightMargin = "margin-right:" + pal.buttonSpace + "px;";      // room for the "Open File" button
            }
        } else if (t === "meta") {
            color = pal.muted;
            body = htmlEscape(s);
        } else if (t === "hunk") {
            bg = pal.bgHunk;
            m = s.match(/^(@@.*?@@)(.*)$/);
            body = m ? colored(pal.link, m[1], ";font-weight:bold") + colored(pal.muted, m[2]) : htmlEscape(s);
        } else if (t === "add") {
            bg = pal.bgAdd;
            color = pal.pos;
            body = htmlEscape(s === "" ? " " : s);
        } else if (t === "del") {
            bg = pal.bgDel;
            color = pal.neg;
            body = htmlEscape(s === "" ? " " : s);
        } else {
            body = htmlEscape(s);
        }

        out.push('<p style="margin:0;' + topMargin + rightMargin + 'white-space:pre-wrap;color:' + color
                 + (bg ? ";background-color:" + bg : "") + '">' + body + "</p>");
    }
    return out.join("");
}

// Commit subject for a StyledText label: issue references (#123, ABC-123) in the link color.
function subjectHtml(subject, linkColor) {
    return htmlEscape(subject).replace(/(#\d+|\b[A-Z][A-Z0-9]+-\d+\b)/g, '<font color="' + linkColor + '">$1</font>');
}

// "repo · hash · author · time" line of a commit row (StyledText); col = { hash, author, muted }.
function metaHtml(c, repoPrefix, col) {
    return (repoPrefix ? '<font color="' + col.muted + '">' + htmlEscape(repoPrefix) + " · </font>" : "")
        + '<font color="' + col.hash + '">' + htmlEscape(c.short) + "</font>"
        + '<font color="' + col.muted + '"> · </font>'
        + '<font color="' + col.author + '"><b>' + htmlEscape(c.author) + "</b></font>"
        + '<font color="' + col.muted + '"> · <i>' + htmlEscape(c.when) + "</i></font>";
}

function checkCommand(script, o) {
    return "GCW_REPO=" + q(o.repo)
        + " GCW_BRANCH=" + q(o.branch)
        + " GCW_KEY=" + q(o.key)
        + " GCW_TOKEN_FILE=" + q(o.tokenFile)
        + " GCW_LIMIT=" + (o.limit || 50)
        + " bash " + q(script) + uniq();
}

// action: "status" | "unlock" | "lock"; o = { key, lifetime (seconds) }
function agentCommand(script, action, o) {
    return "GCW_KEY=" + q(o.key)
        + " GCW_LIFETIME=" + ((o.lifetime | 0) || 0)
        + " bash " + q(script) + " " + action + uniq();
}

// Parse the output of agent.sh.
function parseAgent(stdout, stderr, exitCode) {
    var info = {};
    var lines = String(stdout || "").split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var k = lines[i].indexOf("=");
        if (k > 0) {
            info[lines[i].substring(0, k)] = lines[i].substring(k + 1);
        }
    }
    return {
        ok: info.STATUS === "ok",
        key: info.KEY || "",
        agent: info.AGENT || "",
        own: info.OWN === "1",
        msg: info.MSG || String(stderr || "").trim() || ("Failed (exit code " + exitCode + ")")
    };
}

function notifyCommand(o, title, body) {
    var urgencies = ["low", "normal", "critical"];
    var u = urgencies[Math.min(2, Math.max(0, o.urgency | 0))];
    var cmd = "notify-send -a " + q("Git Commit Watcher") + " -u " + u;
    if (o.icon) {
        cmd += " -i " + q(o.icon);
    }
    if (!o.useDefaultTimeout) {
        cmd += " -t " + (Math.max(0, o.timeoutSec | 0) * 1000);
    }
    var tail = " -- " + q(title) + " " + q(body);
    if (o.clickable) {
        // Clicking the notification (or its "Show changes" button) makes notify-send print the
        // name of the action and exit. That needs notify-send 0.8 or newer (libnotify); with an
        // older one the notification is sent without actions.
        var actions = " -A " + q("default=" + (o.actionLabel || "Show changes"))
                    + " -A " + q("open=" + (o.actionLabel || "Show changes"));
        return "if notify-send --help 2>&1 | grep -q -e '--action'; then " + cmd + actions + tail
            + "; else " + cmd + tail + "; fi" + uniq();
    }
    return cmd + tail + uniq();
}

// Plays a notification sound. name: a sound-theme name (e.g. "message-new-instant") or the
// path of a sound file (absolute, or starting with "~/").
function soundCommand(name) {
    var n = String(name || "").trim() || "message-new-instant";
    if (n.charAt(0) === "/" || n.indexOf("~/") === 0) {
        var p = n.charAt(0) === "~" ? '"$HOME"' + q(n.substring(1)) : q(n);
        return "(canberra-gtk-play -f " + p + " 2>/dev/null"
            + " || pw-play " + p + " 2>/dev/null"
            + "; true)" + uniq();
    }
    return "(canberra-gtk-play -i " + q(n) + " 2>/dev/null"
        + " || { f=$(find /usr/share/sounds -name " + q(n + ".*") + " 2>/dev/null | head -n 1);"
        + " [ -n \"$f\" ] && pw-play \"$f\" 2>/dev/null; }"
        + "; true)" + uniq();
}

// Shell command that prints the names of the sounds installed in the sound themes, one per line.
function listSoundsCommand() {
    return "find /usr/share/sounds \"$HOME/.local/share/sounds\" -type f"
        + " \\( -name '*.oga' -o -name '*.ogg' -o -name '*.wav' \\) 2>/dev/null"
        + " | sed 's#.*/##; s#\\.[^.]*$##' | sort -u" + uniq();
}

// Parse the output of check.sh.
function parseOutput(stdout, stderr, exitCode) {
    var res = { ok: false, msg: "", code: "", tip: "", url: "", commits: [] };
    var info = {};
    var lines = String(stdout || "").split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i];
        if (line.charAt(0) === "C" && line.charAt(1) === US) {
            var p = line.split(US);
            res.commits.push({
                hash: p[1],
                short: p[2],
                author: p[3],
                subject: p[4],
                when: p[5],
                ts: parseInt(p[6], 10) || 0
            });
        } else {
            var k = line.indexOf("=");
            if (k > 0) {
                info[line.substring(0, k)] = line.substring(k + 1);
            }
        }
    }
    res.tip = info.TIP || "";
    res.url = info.URL || "";
    res.code = info.CODE || "";
    res.ok =info.STATUS === "ok" && res.tip !== "";
    if (!res.ok) {
        res.msg = info.MSG || String(stderr || "").trim() || ("Check failed (exit code " + exitCode + ")");
    }
    return res;
}

// Commits newer than `hash` (list is newest first). overflow = hash not in the list.
function commitsSince(list, hash) {
    if (!hash) {
        return { list: [], overflow: false };
    }
    for (var i = 0; i < list.length; ++i) {
        if (list[i].hash === hash) {
            return { list: list.slice(0, i), overflow: false };
        }
    }
    return { list: list, overflow: list.length > 0 };
}
