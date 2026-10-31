#!/usr/bin/python3
"""Print Claude Code usage limits and a per-model token breakdown as JSON.

Used as the data source for the Claude Usage Plasma widget.
"""
import json
import re
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

CREDS = Path.home() / ".claude" / ".credentials.json"
PROJECTS = Path.home() / ".claude" / "projects"
CACHE = Path.home() / ".cache" / "claude-usage-widget.json"
CLAUDE_JSON = Path.home() / ".claude.json"
MIN_FETCH_INTERVAL = 5 * 60   # never call the API more often than this, however often we're run
DEFAULT_BACKOFF = 15 * 60     # wait this long after a 429 if the server doesn't say
URL = "https://api.anthropic.com/api/oauth/usage"
LABELS = {
    "session": "Session (5h)",
    "weekly_all": "Weekly (all models)",
    "weekly_opus": "Weekly (Opus)",
    "weekly_sonnet": "Weekly (Sonnet)",
}


def fetch_usage():
    token = json.loads(CREDS.read_text())["claudeAiOauth"]["accessToken"]
    req = urllib.request.Request(URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-usage-plasmoid/1.0",
    })
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def load_cache():
    try:
        return json.loads(CACHE.read_text())
    except (OSError, ValueError):
        return {}


def save_cache(cache):
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache))
    except OSError:
        pass


def claude_code_cached():
    """Usage data Claude Code itself cached in ~/.claude.json, as (epoch seconds, data) or None."""
    try:
        c = json.loads(CLAUDE_JSON.read_text())["cachedUsageUtilization"]
        return c["fetchedAtMs"] / 1000, c["utilization"]
    except (OSError, ValueError, KeyError, TypeError):
        return None


def parse_limits(data):
    """Return list of (label, percent, resets_at iso|None)."""
    out = []
    for lim in data.get("limits") or []:
        label = LABELS.get(lim.get("kind"), str(lim.get("kind", "?")).replace("_", " ").title())
        out.append((label, float(lim.get("percent") or 0), lim.get("resets_at")))
    fields = (("five_hour", "Session (5h)"), ("seven_day", "Weekly (all models)"),
              ("seven_day_opus", "Weekly (Opus)"), ("seven_day_sonnet", "Weekly (Sonnet)"))
    if out:  # "limits" covered the totals; only add per-model limits it lacks
        fields = fields[2:]
    have = {label for label, _, _ in out}
    for key, label in fields:
        v = data.get(key)
        if v and label not in have:
            out.append((label, float(v.get("utilization") or 0), v.get("resets_at")))
    return out


def window_starts(data):
    """Start of the current 5h session window and 7-day window, from the API reset times."""
    now = datetime.now(timezone.utc)

    def start(key, span):
        try:
            return datetime.fromisoformat(data[key]["resets_at"]) - span
        except (KeyError, TypeError, ValueError):
            return now - span
    return start("five_hour", timedelta(hours=5)), start("seven_day", timedelta(days=7))


def model_breakdown(since):
    """Tokens per model from local Claude Code transcripts since `since` (UTC datetime).

    Counts input + cache writes + output; cache reads are excluded since they are cheap
    and would otherwise dwarf everything else.
    """
    cutoff = since.timestamp()
    seen, totals = set(), {}
    for f in PROJECTS.glob("**/*.jsonl"):
        try:
            if f.stat().st_mtime < cutoff:
                continue
            fh = f.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"assistant"' not in line or '"usage"' not in line:
                    continue
                try:
                    d = json.loads(line)
                    msg = d["message"]
                    model, usage = msg.get("model"), msg.get("usage")
                    if not model or not usage or model.startswith("<"):
                        continue
                    ts = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
                except (ValueError, KeyError, TypeError, AttributeError):
                    continue
                if ts < since:
                    continue
                key = (msg.get("id"), d.get("requestId"))
                if key in seen:
                    continue
                seen.add(key)
                n = (usage.get("input_tokens") or 0) + (usage.get("output_tokens") or 0) \
                    + (usage.get("cache_creation_input_tokens") or 0)
                totals[model] = totals.get(model, 0) + n
    return sorted(totals.items(), key=lambda kv: -kv[1])


def pretty_model(model):
    m = re.match(r"claude-([a-z]+)-(\d+)(?:-(\d{1,2})(?!\d))?(?:-\d{8})?", model)
    if not m:
        return model
    fam, major, minor = m.groups()
    return f"{fam.title()} {major}.{minor}" if minor else f"{fam.title()} {major}"


def model_family(model):
    for fam in ("opus", "sonnet", "haiku", "fable"):
        if fam in model:
            return fam
    return "other"


def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def fmt_reset(iso):
    if not iso:
        return ""
    try:
        t = datetime.fromisoformat(iso)
    except ValueError:
        return ""
    secs = int((t - datetime.now(timezone.utc)).total_seconds())
    if secs <= 0:
        return "Resets now"
    d, rem = divmod(secs, 86400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    left = f"{d}d {h}h" if d else (f"{h}h {m}m" if h else f"{m}m")
    return f"Resets in {left} ({t.astimezone().strftime('%a %H:%M')})"


def models_json(items):
    total = sum(n for _, n in items) or 1
    return [{"name": pretty_model(m), "family": model_family(m), "tokens": n,
             "tokensText": fmt_tokens(n), "share": n / total * 100} for m, n in items]


def main():
    out = {"ok": False, "error": "", "limits": [], "models": {"session": [], "week": []},
           "updated": datetime.now().strftime("%H:%M")}
    now = datetime.now().timestamp()
    cache = load_cache()
    # Claude Code's own cached copy counts as a fetch if it's newer than ours.
    cc = claude_code_cached()
    if cc and cc[0] > cache.get("fetched_at", 0):
        cache.update(fetched_at=cc[0], data=cc[1])

    data = None
    if now - cache.get("fetched_at", 0) < MIN_FETCH_INTERVAL and cache.get("data"):
        data = cache["data"]  # fresh enough; no network call
    elif now < cache.get("backoff_until", 0):
        until = datetime.fromtimestamp(cache["backoff_until"]).strftime("%H:%M")
        out["error"] = f"Rate limited by Anthropic; retrying after {until}."
    else:
        try:
            data = fetch_usage()
            cache.update(fetched_at=now, data=data, backoff_until=0)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                try:
                    wait = int(e.headers.get("Retry-After") or DEFAULT_BACKOFF)
                except ValueError:
                    wait = DEFAULT_BACKOFF
                cache["backoff_until"] = now + max(wait, 60)
                until = datetime.fromtimestamp(cache["backoff_until"]).strftime("%H:%M")
                out["error"] = f"Rate limited by Anthropic; retrying after {until}."
            elif e.code == 401:
                out["error"] = "Login token expired — run `claude` once to refresh it."
            else:
                out["error"] = f"HTTP error {e.code}"
        except Exception as e:  # network down, missing creds, etc.
            out["error"] = f"Couldn't fetch usage: {e}"
        save_cache(cache)

    if data is None and cache.get("data"):  # fall back to the last successful fetch
        data = cache["data"]
        out["error"] += " Showing last known values."
    if data is not None and cache.get("fetched_at"):
        out["updated"] = datetime.fromtimestamp(cache["fetched_at"]).strftime("%H:%M")

    if data is not None:
        limits = parse_limits(data)
        if not limits:
            out["error"] = "No limit data returned."
        else:
            out["ok"] = True
            out["limits"] = [{"label": label, "percent": pct, "reset": fmt_reset(reset)}
                             for label, pct, reset in limits]
        session_start, week_start = window_starts(data)
    else:
        now = datetime.now(timezone.utc)
        session_start, week_start = now - timedelta(hours=5), now - timedelta(days=7)

    try:
        out["models"] = {"session": models_json(model_breakdown(session_start)),
                         "week": models_json(model_breakdown(week_start))}
    except Exception:
        pass
    print(json.dumps(out))


if __name__ == "__main__":
    main()
