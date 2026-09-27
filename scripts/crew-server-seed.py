#!/usr/bin/env python3
"""Seed and check the local forge server for the crew server E2E.

Run by scripts/test-crew-server-e2e.sh against `node server/dist/index.js` started with
APP_SECRET=e2e-local in dev ENV (so /auth/email/start returns `devCode`). Python 3 stdlib
only (urllib + json).

  seed  --base http://127.0.0.1:8799 --secret e2e-local --out ART/seed.json
      Signs the three lifters in over email dev codes, PUTs their profiles, makes the app
      lifter follow Linh and Kenji, and posts crew data in the CURRENT local week (this
      week's Monday per the local time zone): Linh Monday and Tuesday (weekTarget 4), Kenji
      Tuesday (weekTarget 3), each with localDate/weekTarget/lifts (an object map of
      exercise id -> e1rm), plus one session per user per week for the previous 8 weeks with
      rising e1rm so crew lift lines have points, and one pr post for Kenji this week.

  check --base http://127.0.0.1:8799 --secret e2e-local --seed ART/seed.json --out ART
      Signs the app lifter in again (a fresh dev-code session), GETs /social/crew?week=<local
      ISO week> and /social/feed into crew.json/feed.json, and asserts the app's run reached
      the server. Writes summary.txt; exits 1 with a clear message when any check fails.
"""

import json
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta, timezone

# role, email, handle, display name
USERS = [
    ("an", "an@e2e.test", "an_e2e", "An"),
    ("linh", "linh@e2e.test", "linh", "Linh"),
    ("kenji", "kenji@e2e.test", "kenji", "Kenji"),
]

# This week's session `lifts` (exercise id -> e1rm kg); the previous 8 weeks scale down from
# these so every lift line rises into this week.
WEEK_LIFTS = {
    "linh": {"back_squat": 100.0, "deadlift": 140.0},
    "kenji": {"back_squat": 114.0, "deadlift": 150.0},
}
WEEK_TARGET = {"linh": 4, "kenji": 3}
KENJI_PR = {
    "exercise": "Back Squat",
    "exerciseId": "back_squat",
    "e1rm": 117,
    "weightKg": 97.5,
    "reps": 6,
    "previous": 115,
}


class Fail(Exception):
    """An expected failure with a message that is safe to print."""


# ---------- HTTP ----------

def request(method, path, base, secret, token=None, body=None):
    """One JSON request; every call carries x-forge-secret (the app gate)."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base.rstrip("/") + path, data=data, method=method)
    req.add_header("x-forge-secret", secret)
    if data is not None:
        req.add_header("content-type", "application/json")
    if token is not None:
        req.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            raw = res.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:200]
        raise Fail("%s %s -> HTTP %d %s" % (method, path, error.code, detail))
    except urllib.error.URLError as error:
        raise Fail("%s %s unreachable: %s" % (method, path, error.reason))
    return json.loads(raw) if raw else None


def sign_in(base, secret, email):
    """Email dev-code sign-in: returns (token, userId)."""
    start = request("POST", "/auth/email/start", base, secret, body={"email": email})
    code = start.get("devCode") if isinstance(start, dict) else None
    if not code:
        raise Fail("/auth/email/start returned no devCode for %s (server not in dev mode?)" % email)
    verified = request("POST", "/auth/email/verify", base, secret,
                       body={"email": email, "code": code})
    return verified["token"], verified["user"]["id"]


def post_session(base, secret, token, day, week_target, lifts):
    payload = {
        "dayName": "Full A",
        "sets": 16,
        "tonnageKg": round(18.0 * sum(lifts.values()) / max(len(lifts), 1), 1),
        "durationMin": 55,
        "exercises": len(lifts),
        "muscles": {"Quads": 6, "Back": 5, "Hamstrings": 5},
        "localDate": day.isoformat(),
        "weekTarget": week_target,
        "lifts": lifts,
    }
    request("POST", "/social/posts", base, secret, token=token,
            body={"type": "session", "payload": payload})


def dump(path, data):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")


# ---------- seed ----------

def cmd_seed(base, secret, out):
    started = datetime.now(timezone.utc)
    monday = date.today() - timedelta(days=date.today().weekday())

    users = {}
    for role, email, handle, display in USERS:
        token, user_id = sign_in(base, secret, email)
        request("PUT", "/social/profile", base, secret, token=token,
                body={"handle": handle, "displayName": display, "bio": ""})
        users[role] = {"email": email, "handle": handle, "displayName": display, "userId": user_id,
                       "token": token}

    # The app lifter follows Linh and Kenji, so the crew is exactly the three of them.
    for role in ("linh", "kenji"):
        request("POST", "/social/follow/" + users[role]["userId"], base, secret,
                token=users["an"]["token"])

    sessions = 0
    # Previous 8 weeks first (older created_at), one session per user per week, e1rm rising
    # towards this week's values so the crew lift lines have points and end on a high.
    for weeks_back in range(8, 0, -1):
        day = monday - timedelta(weeks=weeks_back)
        for role in ("linh", "kenji"):
            lifts = {exercise_id: round(value * (1 - 0.01 * weeks_back), 1)
                     for exercise_id, value in WEEK_LIFTS[role].items()}
            post_session(base, secret, users[role]["token"], day, WEEK_TARGET[role], lifts)
            sessions += 1
    # This week: Linh Monday and Tuesday, Kenji Tuesday.
    post_session(base, secret, users["linh"]["token"], monday, WEEK_TARGET["linh"], WEEK_LIFTS["linh"])
    post_session(base, secret, users["linh"]["token"], monday + timedelta(days=1), WEEK_TARGET["linh"],
                 {"back_squat": 101.0, "deadlift": 141.5})
    sessions += 2
    post_session(base, secret, users["kenji"]["token"], monday + timedelta(days=1), WEEK_TARGET["kenji"],
                 WEEK_LIFTS["kenji"])
    sessions += 1

    # Kenji's Back Squat record, dated this week but never after today (Monday <= today).
    request("POST", "/social/posts", base, secret, token=users["kenji"]["token"],
            body={"type": "pr", "payload": dict(KENJI_PR, localDate=monday.isoformat())})

    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"runStartedAt": started.isoformat(), "weekMonday": monday.isoformat(),
                   "users": users}, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print("Seeded %d users, %d session posts, 1 pr post -> %s" % (len(users), sessions, out))


# ---------- check ----------

def cmd_check(base, secret, seed_path, out_dir):
    with open(seed_path, encoding="utf-8") as fh:
        seed = json.load(fh)
    run_started = datetime.fromisoformat(seed["runStartedAt"])
    users = seed["users"]
    today = date.today().isoformat()
    iso = date.today().isocalendar()
    week = "%04d-W%02d" % (iso[0], iso[1])

    token, _ = sign_in(base, secret, users["an"]["email"])
    crew = request("GET", "/social/crew?week=" + week, base, secret, token=token)
    feed = request("GET", "/social/feed", base, secret, token=token)
    dump(out_dir + "/crew.json", crew)
    dump(out_dir + "/feed.json", feed)

    results = []

    def check(name, ok, detail=""):
        results.append((name, bool(ok), str(detail)))

    # (a) the seeded crew came back, with Kenji's record
    members = crew.get("members") or []
    by_handle = {m.get("handle"): m for m in members if m.get("handle")}
    an = by_handle.get(users["an"]["handle"])
    linh = by_handle.get(users["linh"]["handle"])
    kenji = by_handle.get(users["kenji"]["handle"])
    check("members contain An (isSelf)", an is not None and an.get("isSelf") is True,
          "member=%r" % (an,))
    check("members contain Linh", linh is not None and linh.get("displayName") == "Linh",
          "member=%r" % (linh,))
    check("members contain Kenji", kenji is not None and kenji.get("displayName") == "Kenji",
          "member=%r" % (kenji,))
    check("Linh sessions == 2", linh is not None and linh.get("sessions") == 2,
          "sessions=%r" % ((linh or {}).get("sessions"),))
    check("Kenji sessions == 1", kenji is not None and kenji.get("sessions") == 1,
          "sessions=%r" % ((kenji or {}).get("sessions"),))
    kenji_records = [r for r in (crew.get("records") or [])
                     if r.get("userId") == users["kenji"]["userId"]
                     and r.get("exerciseId") == "back_squat"]
    check("records contain Kenji's back_squat", bool(kenji_records),
          "matches=%d" % len(kenji_records))

    # (b) the app lifter's own newest session post, as the app posted it during this run
    mine = [p for p in (feed.get("posts") or [])
            if p.get("type") == "session"
            and (p.get("user") or {}).get("handle") == users["an"]["handle"]]
    newest = mine[0] if mine else None
    check("app lifter session post in feed", newest is not None,
          "session posts by %s: %d" % (users["an"]["handle"], len(mine)))
    payload = (newest or {}).get("payload") or {}
    created = None
    if newest:
        created = datetime.fromisoformat(newest["createdAt"].replace("Z", "+00:00"))
    check("session post created in this run", created is not None and created >= run_started,
          "createdAt=%s runStartedAt=%s" % (created, run_started.isoformat()))
    check("session payload localDate is today", payload.get("localDate") == today,
          "localDate=%r today=%s" % (payload.get("localDate"), today))
    week_target = payload.get("weekTarget")
    check("session payload weekTarget is an int",
          isinstance(week_target, int) and not isinstance(week_target, bool),
          "weekTarget=%r" % (week_target,))
    lifts = payload.get("lifts")
    check("session payload lifts is an object map with >= 1 entry",
          isinstance(lifts, dict) and len(lifts) >= 1
          and all(isinstance(k, str) and isinstance(v, (int, float))
                  and not isinstance(v, bool) for k, v in lifts.items()),
          "lifts=%r" % (lifts,))

    # (c) the post reached the crew week view
    check("app lifter crew sessions >= 1",
          an is not None and (an.get("sessions") or 0) >= 1,
          "sessions=%r" % ((an or {}).get("sessions"),))

    failed = [name for name, ok, _ in results if not ok]
    lines = ["crew-server-e2e check %s (week %s)"
             % (datetime.now(timezone.utc).isoformat(), week), ""]
    for name, ok, detail in results:
        lines.append("%s  %s%s" % ("ok" if ok else "FAIL", name, " — " + detail if detail else ""))
    lines.append("")
    lines.append("%s: %d/%d checks passed"
                 % ("PASS" if not failed else "FAIL", len(results) - len(failed), len(results)))
    with open(out_dir + "/summary.txt", "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    if failed:
        raise Fail("check failed: " + "; ".join(failed))
    print("PASS crew-server-e2e week %s — artifacts in %s" % (week, out_dir))


# ---------- CLI ----------

def parse_opts(rest):
    opts = {}
    i = 0
    while i < len(rest):
        if rest[i].startswith("--") and i + 1 < len(rest):
            opts[rest[i][2:]] = rest[i + 1]
            i += 2
        else:
            i += 1
    return opts


def main(argv):
    if len(argv) >= 2 and argv[1] == "seed":
        opts = parse_opts(argv[2:])
        missing = [name for name in ("base", "secret", "out") if not opts.get(name)]
        if missing:
            print("seed is missing: %s" % ", ".join("--" + m for m in missing), file=sys.stderr)
            return 2
        cmd_seed(opts["base"], opts["secret"], opts["out"])
    elif len(argv) >= 2 and argv[1] == "check":
        opts = parse_opts(argv[2:])
        missing = [name for name in ("base", "secret", "seed", "out") if not opts.get(name)]
        if missing:
            print("check is missing: %s" % ", ".join("--" + m for m in missing), file=sys.stderr)
            return 2
        cmd_check(opts["base"], opts["secret"], opts["seed"], opts["out"])
    else:
        print("usage: crew-server-seed.py seed --base URL --secret S --out FILE\n"
              "       crew-server-seed.py check --base URL --secret S --seed FILE --out DIR",
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Fail as failure:
        print("FAIL: %s" % failure, file=sys.stderr)
        sys.exit(1)
