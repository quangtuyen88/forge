// Landing: reveal-on-scroll, video pause off-screen, reduced-motion play buttons,
// and the hero demo button scrolls to #demo and starts playback.
(function () {
  document.documentElement.classList.add("js");

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)");

  // Reveal sections/cards once as they enter the viewport.
  var revealEls = document.querySelectorAll("[data-reveal]");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -10% 0px" });
    revealEls.forEach(function (el) { io.observe(el); });
    // Safety net: nothing stays hidden if the observer never fires (in-app browsers, prerender).
    setTimeout(function () { revealEls.forEach(function (el) { el.classList.add("is-in"); }); }, 1500);
  } else {
    revealEls.forEach(function (el) { el.classList.add("is-in"); });
  }

  // Autoplay videos: play only while on screen. Under reduced motion they never autoplay —
  // the poster stays and a play button (CSS: .reduce-play .video-play) starts them.
  document.querySelectorAll("video[autoplay]").forEach(function (video) {
    if (reduced.matches) {
      video.removeAttribute("autoplay");
      document.documentElement.classList.add("reduce-play");
      var btn = video.parentElement.querySelector(".video-play");
      if (btn) {
        btn.addEventListener("click", function () {
          if (video.paused) {
            video.play().then(function () { btn.style.display = "none"; }).catch(function () {});
          } else {
            video.pause();
            btn.style.display = "";
          }
        });
        video.addEventListener("play", function () { btn.style.display = "none"; });
        video.addEventListener("pause", function () { btn.style.display = ""; });
      }
      return;
    }
    if (!("IntersectionObserver" in window)) return;
    var vio = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { video.play().catch(function () {}); }
        else { video.pause(); }
      });
    }, { threshold: 0.25 });
    vio.observe(video);
  });

  // Hero demo button: scroll to #demo and start playback.
  var demoBtn = document.getElementById("demo-button");
  var demoVideo = document.getElementById("demo-video");
  if (demoBtn && demoVideo) {
    demoBtn.addEventListener("click", function (e) {
      e.preventDefault();
      var demo = document.getElementById("demo");
      if (demo) { demo.scrollIntoView({ behavior: "smooth", block: "start" }); }
      demoVideo.play().catch(function () {});
    });
  }
})();

// Find-my-plan: quiz → reviewed starter preview → waitlist (real beta funnel).
// Options mirror ForgeCore/Sources/ForgeCore/Program.swift + App/Forge/OnboardingView.swift.
(function () {
var WAITLIST_URL = "https://forge-coach.quangtuyen88.workers.dev/waitlist";
var STORE_KEY = "regulift.plan.v1";
var REF_KEY = "regulift.ref";
var VERSION = 1;

// Reviewed, versioned starter templates. Day names are exactly Program.split(daysPerWeek:)
// (auto style) — repeated labels get A/B/C suffixes for display only. No load calculation here.
var SPLITS = {
  3: ["Full A", "Full B", "Full C"],
  4: ["Upper", "Lower", "Upper", "Lower"],
  5: ["Upper", "Lower", "Push", "Pull", "Legs"],
  6: ["Push", "Pull", "Legs", "Push", "Pull", "Legs"]
};
var SPLIT_LABEL = {
  3: "Full body",
  4: "Upper / Lower",
  5: "Upper · Lower · Push · Pull · Legs",
  6: "Push / Pull / Legs"
};
var GOALS = [
  { id: "hypertrophy", name: "Hypertrophy", detail: "Build muscle" },
  { id: "strength", name: "Strength", detail: "Move more weight" },
  { id: "both", name: "Both", detail: "Size and strength" }
];
var DAYS = [3, 4, 5, 6];
var SESSIONS = [
  { id: 45, name: "45 min" },
  { id: 60, name: "60 min" },
  { id: 90, name: "90 min" }
];
var MAX_EXERCISES = { 45: 4, 60: 6, 90: 8 };
var PRESETS = [
  { id: "commercial", name: "Commercial gym", detail: "Barbells, dumbbells, machines, cables, pull-up bar." },
  { id: "home", name: "Home", detail: "Barbell, dumbbells, bands and bodyweight." },
  { id: "dumbbellsOnly", name: "Dumbbells only", detail: "Dumbbells and bodyweight." },
  { id: "hotel", name: "Hotel", detail: "Dumbbells, machines and bodyweight." },
  { id: "noMachines", name: "No machines", detail: "Everything except machines." },
  { id: "bodyweight", name: "Bodyweight", detail: "Bodyweight and bands." }
];
var EXPERIENCE = [
  { id: "postBeginner", name: "Post-beginner", detail: "1–2 years" },
  { id: "intermediate", name: "Intermediate", detail: "2–4 years" },
  { id: "advanced", name: "Advanced", detail: "4+ years" }
];
// Program.repRange(_:goal:) — compound / isolation by goal.
var REP_RANGES = {
  hypertrophy: { compound: "8–12", isolation: "12–15" },
  strength: { compound: "4–6", isolation: "8–12" },
  both: { compound: "6–10", isolation: "10–15" }
};

var form = document.getElementById("finder-form");
if (!form) { return; }

var nextBtn = document.getElementById("finder-next");
var backBtn = document.getElementById("finder-back");
var progressEl = document.getElementById("finder-progress");
var trackFill = document.getElementById("finder-track-fill");
var previewEl = document.getElementById("finder-preview");
var restoreBtn = document.getElementById("restore-btn");
var restoreInput = document.getElementById("restore-code");
var waitlistForm = document.getElementById("waitlist-form");

var steps = Array.prototype.slice.call(form.querySelectorAll(".finder-step"));
var stepCount = steps.length;
var current = 1;

var answers = {
  goal: "hypertrophy",
  days: 3,
  session: 60,
  equipment: "commercial",
  experience: "intermediate"
};

var ref = readRef();

function readRef() {
  try {
    var m = window.location.search.match(/[?&]ref=([^&]+)/);
    var code = m ? decodeURIComponent(m[1]) : "";
    if (code) {
      try { localStorage.setItem(REF_KEY, code); } catch (e) {}
      return code;
    }
    try { return localStorage.getItem(REF_KEY) || ""; } catch (e) { return ""; }
  } catch (e) { return ""; }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}

function indexOf(list, id) {
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].id) === String(id)) { return i; }
  }
  return -1;
}

function pack(a) {
  var gi = indexOf(GOALS, a.goal);
  var di = DAYS.indexOf(Number(a.days));
  var si = indexOf(SESSIONS, a.session);
  var pi = indexOf(PRESETS, a.equipment);
  var ei = indexOf(EXPERIENCE, a.experience);
  if ([gi, di, si, pi, ei].some(function (i) { return i < 0; })) {
    return "RP" + VERSION + "-invalid";
  }
  var n = gi + GOALS.length * (di + DAYS.length * (si + SESSIONS.length * (pi + PRESETS.length * ei)));
  return "RP" + VERSION + "-" + n.toString(36).toUpperCase();
}

function unpack(code) {
  var m = String(code || "").trim().toUpperCase().match(/^RP(\d+)-([0-9A-Z]+)$/);
  if (!m) { return null; }
  if (parseInt(m[1], 10) !== VERSION) { return null; }
  var n = parseInt(m[2], 36);
  if (isNaN(n)) { return null; }
  var base = GOALS.length * DAYS.length * SESSIONS.length * PRESETS.length;
  var ei = Math.floor(n / base); n = n % base;
  var pbase = GOALS.length * DAYS.length * SESSIONS.length;
  var pi = Math.floor(n / pbase); n = n % pbase;
  var sbase = GOALS.length * DAYS.length;
  var si = Math.floor(n / sbase); n = n % sbase;
  var dbase = GOALS.length;
  var di = Math.floor(n / dbase);
  var gi = n % dbase;
  if (ei >= EXPERIENCE.length || pi >= PRESETS.length || si >= SESSIONS.length || di >= DAYS.length || gi >= GOALS.length) { return null; }
  return {
    goal: GOALS[gi].id,
    days: DAYS[di],
    session: SESSIONS[si].id,
    equipment: PRESETS[pi].id,
    experience: EXPERIENCE[ei].id
  };
}

function persist() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({
      v: VERSION,
      goal: answers.goal,
      days: answers.days,
      session: answers.session,
      equipment: answers.equipment,
      experience: answers.experience
    }));
  } catch (e) {}
}

function restore() {
  try {
    var raw = localStorage.getItem(STORE_KEY);
    if (!raw) { return false; }
    var saved = JSON.parse(raw);
    if (!saved || saved.v !== VERSION) { return false; }
    var ok = indexOf(GOALS, saved.goal) >= 0 &&
      DAYS.indexOf(Number(saved.days)) >= 0 &&
      indexOf(SESSIONS, saved.session) >= 0 &&
      indexOf(PRESETS, saved.equipment) >= 0 &&
      indexOf(EXPERIENCE, saved.experience) >= 0;
    if (!ok) { return false; }
    answers = {
      goal: saved.goal,
      days: Number(saved.days),
      session: Number(saved.session),
      equipment: saved.equipment,
      experience: saved.experience
    };
    return true;
  } catch (e) { return false; }
}

function setRadio(name, value) {
  var inputs = form.elements[name];
  if (!inputs) { return; }
  for (var i = 0; i < inputs.length; i++) {
    if (inputs[i].value === String(value)) { inputs[i].checked = true; }
  }
}

function applyAnswers() {
  setRadio("goal", answers.goal);
  setRadio("days", answers.days);
  setRadio("session", answers.session);
  setRadio("equipment", answers.equipment);
  setRadio("experience", answers.experience);
}

function checkedValue(name) {
  var inputs = form.elements[name];
  if (!inputs) { return null; }
  for (var i = 0; i < inputs.length; i++) {
    if (inputs[i].checked) { return inputs[i].value; }
  }
  return null;
}

function readAnswers() {
  var g = checkedValue("goal");
  var d = checkedValue("days");
  var s = checkedValue("session");
  var eq = checkedValue("equipment");
  var ex = checkedValue("experience");
  if (g) { answers.goal = g; }
  if (d) { answers.days = Number(d); }
  if (s) { answers.session = Number(s); }
  if (eq) { answers.equipment = eq; }
  if (ex) { answers.experience = ex; }
}

function labelDays(days) {
  var counts = {};
  var seen = {};
  days.forEach(function (d) { counts[d] = (counts[d] || 0) + 1; });
  return days.map(function (d, i) {
    seen[d] = (seen[d] || 0) + 1;
    var label = d + (counts[d] > 1 ? " " + "ABCDEFGH".charAt(seen[d] - 1) : "");
    return { n: i + 1, name: label };
  });
}

function row(label, value, editStep) {
  var edit = editStep
    ? '<button type="button" class="edit" data-edit="' + editStep + '" aria-label="Edit ' + escapeHtml(label) + '">Edit</button>'
    : "";
  return '<div class="preview-row">' +
    '<span class="row-label">' + escapeHtml(label) + '</span>' +
    '<span class="row-value">' + escapeHtml(value) + '</span>' +
    '<span class="row-edit">' + edit + '</span>' +
    '</div>';
}

function buildPreview() {
  var days = labelDays(SPLITS[answers.days] || []);
  var goalName = (GOALS[indexOf(GOALS, answers.goal)] || GOALS[0]).name;
  var preset = PRESETS[indexOf(PRESETS, answers.equipment)] || PRESETS[0];
  var exp = EXPERIENCE[indexOf(EXPERIENCE, answers.experience)] || EXPERIENCE[1];
  var rr = REP_RANGES[answers.goal] || REP_RANGES.hypertrophy;
  var maxEx = MAX_EXERCISES[answers.session] || 6;
  var splitLabel = answers.days + "-day " + (SPLIT_LABEL[answers.days] || "split");
  var code = pack(answers);

  var dayItems = days.map(function (d) {
    return '<li class="preview-day"><span class="day-name">Day ' + d.n + '</span><span class="day-split">' + escapeHtml(d.name) + '</span></li>';
  }).join("");

  var html =
    '<span class="starter-badge">Starter structure. The app calibrates it from your first sessions.</span>' +
    '<h3>Your starting structure</h3>' +
    '<p class="preview-sub">' + escapeHtml(splitLabel) + '. Designed around your equipment and time budget.</p>' +
    '<ol class="preview-days">' + dayItems + '</ol>' +
    '<div class="preview-meta">' +
      row("Goal", goalName, "1") +
      row("Days per week", String(answers.days), "2") +
      row("Session length", "≈ " + answers.session + " min · up to " + maxEx + " exercises", "3") +
      row("Equipment", preset.name, "4") +
      row("Experience", exp.name + " · " + exp.detail, "5") +
      row("Rep ranges", rr.compound + " on main lifts · " + rr.isolation + " on accessories", null) +
    '</div>' +
    '<div class="plan-code">' +
      '<label for="plan-code-out">Your plan code</label>' +
      '<div class="plan-code-row">' +
        '<output id="plan-code-out">' + escapeHtml(code) + '</output>' +
        '<button type="button" class="btn btn-secondary btn-sm" data-copy="' + escapeHtml(code) + '" data-copy-label="plan code">Copy code</button>' +
      '</div>' +
    '</div>' +
    '<p class="preview-note">Starting loads are calibrated in the app or from imported Strong/Hevy history. This is a starter plan, not a promise of future strength or appearance.</p>';

  previewEl.innerHTML = html;
  bindCopy(previewEl);
}

function goTo(step) {
  current = Math.max(1, Math.min(stepCount, step));
  steps.forEach(function (el, i) {
    el.hidden = (i + 1) !== current;
  });
  backBtn.hidden = current === 1;
  nextBtn.textContent = current === stepCount ? "Edit answers" : "Continue";
  progressEl.textContent = "Step " + current + " of " + stepCount;
  trackFill.style.width = ((current / stepCount) * 100) + "%";
  if (current === stepCount) { buildPreview(); }
}

function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text).then(function () { return true; }).catch(function () { return legacyCopy(text); });
  }
  return Promise.resolve(legacyCopy(text));
}

function legacyCopy(text) {
  try {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    document.body.removeChild(ta);
    return true;
  } catch (e) { return false; }
}

function bindCopy(root) {
  if (!root || !root.querySelectorAll) { return; }
  Array.prototype.slice.call(root.querySelectorAll("[data-copy]")).forEach(function (btn) {
    btn.addEventListener("click", function () {
      var text = btn.getAttribute("data-copy");
      copyText(text).then(function (ok) {
        var old = btn.textContent;
        btn.textContent = ok ? "Copied" : "Copy failed";
        btn.disabled = true;
        setTimeout(function () { btn.textContent = old; btn.disabled = false; }, 1600);
      });
    });
  });
}

function friendlyError(msg) {
  if (msg === "valid email required") { return "Enter a valid email address."; }
  if (msg === "Too many signups. Try again in a minute.") { return "Too many signups. Try again in a minute."; }
  return msg;
}

nextBtn.addEventListener("click", function () {
  if (current === stepCount) { goTo(1); return; }
  readAnswers();
  persist();
  goTo(current + 1);
});

backBtn.addEventListener("click", function () { goTo(current - 1); });

form.addEventListener("change", function () {
  readAnswers();
  persist();
  if (current === stepCount) { buildPreview(); }
});

previewEl.addEventListener("click", function (e) {
  var target = e.target;
  while (target && target !== previewEl) {
    if (target.getAttribute && target.getAttribute("data-edit")) {
      goTo(Number(target.getAttribute("data-edit")));
      return;
    }
    target = target.parentNode;
  }
});

function applyRestore() {
  var a = unpack(restoreInput.value);
  if (!a) {
    restoreInput.setAttribute("aria-invalid", "true");
    return;
  }
  restoreInput.removeAttribute("aria-invalid");
  answers = a;
  applyAnswers();
  persist();
  goTo(stepCount);
}

restoreBtn.addEventListener("click", applyRestore);
restoreInput.addEventListener("keydown", function (e) {
  if (e.key === "Enter") {
    e.preventDefault();
    applyRestore();
  }
});

if (waitlistForm) {
  waitlistForm.addEventListener("submit", function (e) {
    e.preventDefault();
    var emailInput = document.getElementById("waitlist-email");
    var statusEl = document.getElementById("waitlist-status");
    var submitBtn = document.getElementById("waitlist-submit");
    var email = emailInput.value.trim();
    if (!email) {
      statusEl.textContent = "Enter your email to join.";
      return;
    }
    submitBtn.disabled = true;
    statusEl.textContent = "Joining…";
    fetch(WAITLIST_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: email, ref: ref })
    }).then(function (res) {
      return res.json().then(function (data) { return { ok: res.ok, data: data }; });
    }).then(function (r) {
      submitBtn.disabled = false;
      if (r.ok && r.data && r.data.code) {
        statusEl.innerHTML = "You're on the list. Your referral code: <button type='button' class='code-chip' data-copy='" + escapeHtml(r.data.code) + "' data-copy-label='referral code'>" + escapeHtml(r.data.code) + " · copy</button>";
        bindCopy(statusEl);
      } else if (r.data && r.data.error) {
        statusEl.textContent = friendlyError(r.data.error);
      } else {
        statusEl.textContent = "Something went wrong. Try again.";
      }
    }).catch(function () {
      submitBtn.disabled = false;
      statusEl.textContent = "Couldn't reach the waitlist. Check your connection and try again.";
    });
  });
}

applyAnswers();
goTo(restore() ? stepCount : 1);
})();
