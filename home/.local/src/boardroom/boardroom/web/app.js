"use strict";
/* Boardroom web UI. Plain JavaScript, no build step, nothing loaded from the internet.
   Everything on the Office page is derived from the run's event stream (see events.py),
   so a past run in History is drawn by replaying its events.jsonl the same way. */

const $ = (sel, el = document) => el.querySelector(sel);
const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];

// --- the access token (from the link `boardroom ui` printed) -----------------------------
const START_TAB = (location.hash.match(/tab=(\w+)/) || [])[1];
const TOKEN = (() => {
  const m = location.hash.match(/t=([\w-]+)/);
  try {
    if (m) { sessionStorage.setItem("boardroom-token", m[1]); history.replaceState(null, "", location.pathname); }
    return m ? m[1] : (sessionStorage.getItem("boardroom-token") || "");
  } catch { return m ? m[1] : ""; }
})();

async function api(path, body) {
  const opts = { headers: { "X-Boardroom-Token": TOKEN } };
  if (body !== undefined) {
    opts.method = "POST";
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(body);
  }
  const r = await fetch(path, opts);
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || `${r.status} ${r.statusText}`);
  return j;
}

const store = {
  get(k, d) { try { return localStorage.getItem(k) ?? d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
};

// --- small helpers ------------------------------------------------------------------------
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
// One line of plain text: whitespace squeezed, markdown marks (#, **, `, list bullets) dropped.
const firstLine = (s, n = 140) => {
  const t = String(s ?? "").replace(/^\s*(#{1,6}|[-*+]|\d+[.)])\s+/gm, "").replace(/\*\*|`{1,3}|__/g, "").replace(/\s+/g, " ").trim();
  return t.length > n ? t.slice(0, n - 1) + "…" : t;
};
const clock = (ts) => new Date(ts * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
const duration = (sec) => { sec = Math.max(0, Math.round(sec)); const m = Math.floor(sec / 60), s = sec % 60; return m ? `${m}m ${String(s).padStart(2, "0")}s` : `${s}s`; };
const money = (d) => "$" + (d < 10 ? d.toFixed(2) : d.toFixed(0));
const kTokens = (n) => n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1000 ? Math.round(n / 1000) + "k" : String(n);

function toast(msg, bad = false) {
  const t = $("#toast");
  t.textContent = msg;
  t.className = "toast show" + (bad ? " bad" : "");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { t.className = "toast" + (bad ? " bad" : ""); }, bad ? 6000 : 2800);
}

async function act(fn, okMsg) {
  try { const r = await fn(); if (okMsg) toast(okMsg); return r; }
  catch (e) { toast(e.message, true); throw e; }
}

// --- names, colours, words ------------------------------------------------------------------
const FIXED_COLORS = { ceo: "#d39b00", debugger: "#e0507a" };
const PALETTE = ["#1aa3c8", "#38a865", "#a659d6", "#4a86e8", "#e07b39", "#7aa83a", "#d14f8e", "#3f9fc4", "#c49a1e", "#8a63d2"];
const colorCache = new Map();
function colorOf(id) {
  const m = String(id || "").split(".")[0];
  if (!colorCache.has(m)) colorCache.set(m, FIXED_COLORS[m] || PALETTE[[...colorCache.keys()].filter((k) => !FIXED_COLORS[k]).length % PALETTE.length]);
  return colorCache.get(m);
}
function nameOf(id) {
  if (!id) return "";
  if (id.includes(".")) {
    const parts = id.split(".");
    return `${nameOf(parts[0])} › helper ${parts[parts.length - 1].replace(/^sub/, "")}`;
  }
  if (id === "ceo") return "CEO";
  return id.replace(/-(\d+)$/, " $1").replace(/^\w/, (c) => c.toUpperCase());
}
const ROLE_ICON = { ceo: "🧑‍💼", debugger: "🔍", worker: "🛠️", subagent: "🐣" };
const iconOf = (role) => ROLE_ICON[role] || "✨";
const who = (id) => `<span class="who" style="--c:${colorOf(id)}">${esc(nameOf(id))}</span>`;

function verb(name, summary) {
  const n = String(name || "").toLowerCase();
  const s = summary && summary !== "." ? " " + summary : (/^(list_files|ls|glob|list_directory)$/.test(n) ? " the project" : "");
  if (/^(write_file|write)$/.test(n)) return "✏️ Writing" + s;
  if (/^(edit_file|edit|multiedit|notebookedit|replace)$/.test(n)) return "✏️ Editing" + s;
  if (/^(read_file|read|read_many_files)$/.test(n)) return "📖 Reading" + s;
  if (/^(list_files|ls|glob|list_directory)$/.test(n)) return "👀 Looking around" + s;
  if (/^(search|grep|grep_search)$/.test(n)) return "🔎 Searching for" + s;
  if (/^(run_shell|bash|shell|run_shell_command)$/.test(n)) return "▶️ Running" + s;
  if (/web|fetch/.test(n)) return "🌐 Looking online" + s;
  if (/todo/.test(n)) return "📝 Updating its to-do list";
  return `🔧 Using ${name}${s}`;
}
const STATUS_TEXT = { idle: "Free", queued: "Up next", working: "Working", waiting: "Waiting on team", done: "Done", failed: "Didn't finish" };

// --- the run, rebuilt from events -------------------------------------------------------------
class RunModel {
  constructor(roster) {
    this.members = new Map();
    this.events = [];
    this.goal = "";
    this.startTs = null;
    this.endTs = null;
    this.ended = false;
    this.ok = null;
    this.reports = [];       // the CEO's final reports, one per turn
    this.pendingAsk = null;
    this.waitingOn = {};     // agent id -> tasks it handed out that aren't back yet
    if (roster) this.setRoster(roster);
  }
  setRoster(list) { for (const m of list) this.member(m.id, m); }
  member(id, info) {
    let m = this.members.get(id);
    if (!m) {
      m = { id, role: "worker", model: "", status: "idle", task: "", action: "", tokens: 0, cost: 0, subs: new Map(), wire: false };
      this.members.set(id, m);
    }
    if (info) { if (info.role) m.role = info.role; if (info.model) m.model = info.model; }
    return m;
  }
  sub(id) {
    const parent = this.member(id.split(".")[0]);
    let s = parent.subs.get(id);
    if (!s) { s = { id, status: "working", task: "", action: "" }; parent.subs.set(id, s); }
    return s;
  }
  thing(id) { return id && id.includes(".") ? this.sub(id) : this.member(id); }
  waiting(id, delta) {
    if (!id) return;
    const n = (this.waitingOn[id] = (this.waitingOn[id] || 0) + delta);
    const t = this.thing(id);
    if (n > 0) { t.status = "waiting"; t.action = id === "ceo" ? "⏳ Waiting for the team" : "⏳ Waiting for helpers"; }
    else if (t.status === "waiting") { t.status = "working"; t.action = "📋 Reading the reports"; }
  }
  apply(ev) {
    this.events.push(ev);
    const a = ev.agent;
    switch (ev.type) {
      case "run_start":
        this.goal = ev.goal; this.startTs = ev.ts; this.setRoster(ev.members || []);
        break;
      case "agent_start": {
        const t = this.thing(a);
        t.status = "working"; t.task = ev.task || t.task; t.action = "🚀 Getting started";
        break;
      }
      case "delegate": {
        const t = this.member(ev.to);
        t.status = "queued"; t.task = ev.task; t.action = "Waiting to start"; t.wire = true;
        this.waiting(a, +1);
        break;
      }
      case "spawn": {
        const s = this.sub(ev.to);
        s.task = ev.task; s.status = "working";
        this.waiting(a, +1);
        break;
      }
      case "tool": { const t = this.thing(a); t.action = verb(ev.name, ev.summary); if (t.status === "queued") t.status = "working"; break; }
      case "text": this.thing(a).action = "💭 " + firstLine(ev.text, 90); break;
      case "report": {
        const t = this.thing(a);
        t.status = ev.ok === false ? "failed" : "done";
        t.action = (ev.ok === false ? "⚠️ " : "✅ ") + firstLine(ev.text, 90);
        if (!a.includes(".")) t.wire = false;
        if (ev.to) this.waiting(ev.to, -1);
        if (a === "ceo" && !ev.to) this.reports.push(ev);
        break;
      }
      case "usage": {
        const m = this.member(String(a).split(".")[0]);
        m.tokens += (ev.input || 0) + (ev.output || 0);
        m.cost += ev.cost || 0;
        break;
      }
      case "ask": this.pendingAsk = ev; break;
      case "answer": this.pendingAsk = null; break;
      case "user": { const c = this.member("ceo"); c.status = "working"; c.action = "💭 Reading your reply"; break; }
      case "run_end":
        this.ended = true; this.ok = ev.ok; this.endTs = ev.ts; this.pendingAsk = null;
        for (const m of this.members.values()) {
          if (["working", "queued", "waiting"].includes(m.status)) { m.status = ev.ok ? "done" : "failed"; m.wire = false; }
          for (const s of m.subs.values()) if (s.status === "working") s.status = "failed";
        }
        break;
    }
  }
}

function describe(ev) {
  const a = ev.agent;
  switch (ev.type) {
    case "run_start": return { html: `📋 New task: <b>${esc(firstLine(ev.goal, 200))}</b>`, detail: ev.goal.length > 200 ? ev.goal : null };
    case "agent_start": return ev.parent ? null : { html: `${who(a)} started working on it` };
    case "delegate": return { html: `${who(a)} gave ${who(ev.to)} a task`, detail: ev.task, to: ev.to };
    case "spawn": return { html: `${who(a)} brought in a helper (${who(ev.to)})`, detail: ev.task, to: ev.to };
    case "tool": return { html: `${who(a)} ${esc(verb(ev.name, ev.summary).replace(/^\S+ /, "").replace(/^\w/, (c) => c.toLowerCase()))}` };
    case "text": return { html: `${who(a)}: “${esc(firstLine(ev.text, 160))}”`, detail: ev.text.length > 160 ? ev.text : null };
    case "report": {
      if (a === "ceo" && !ev.to) return { html: `${who(a)} ${ev.ok === false ? "stopped and wrote" : "finished and wrote"} a report`, cls: "ev-user" };
      const to = ev.to && !a.startsWith(ev.to + ".") ? ` and reported to ${who(ev.to)}` : "";
      return ev.ok === false
        ? { html: `${who(a)} couldn't finish${to}`, detail: ev.text, cls: "ev-error" }
        : { html: `${who(a)} finished${to}`, detail: ev.text, to: ev.to };
    }
    case "ask": return { html: `${who(a)} asks to run a command`, detail: ev.command, cls: "ev-notice" };
    case "answer": return { html: ev.allowed ? `You allowed it${ev.always ? " (and everything else this run)" : ""}` : "You didn't allow it" };
    case "notice": return { html: `ℹ️ ${a ? who(a) + ": " : ""}${esc(ev.text)}`, cls: "ev-notice" };
    case "error": return { html: `⚠️ ${a ? who(a) + " ran into a problem" : "Problem"}`, detail: ev.text, cls: "ev-error" };
    case "user": return { html: `💬 You: ${esc(firstLine(ev.text, 200))}`, detail: ev.text.length > 200 ? ev.text : null, cls: "ev-user" };
    case "run_end": return { html: ev.ok ? `🎉 All done in ${duration(ev.seconds)}` : `⏹️ Stopped after ${duration(ev.seconds)}`, cls: "ev-user" };
    default: return null;
  }
}

function feedItem(ev) {
  const d = describe(ev);
  if (!d) return null;
  const li = document.createElement("li");
  li.dataset.agent = ev.agent || "";
  li.dataset.to = d.to || "";
  li.innerHTML = `<time>${clock(ev.ts)}</time><div class="${d.cls || ""}">${d.html}${d.detail ? `<div class="detail" title="Click to see all">${esc(d.detail)}</div>` : ""}</div>`;
  return li;
}

function matchesFilter(li, f) {
  if (!f) return true;
  const a = li.dataset.agent, to = li.dataset.to;
  return a === f || a.startsWith(f + ".") || to === f || to.startsWith(f + ".");
}

// --- app state --------------------------------------------------------------------------------
const S = {
  state: null,           // /api/state
  models: [],            // /api/models
  run: new RunModel(),   // the current run, from the event stream
  dir: store.get("boardroom-dir", ""),
  filter: null,
  evCount: 0,
  gen: 0,
};

async function refresh() {
  try {
    S.state = await api("/api/state");
  } catch (e) {
    document.body.innerHTML = `<div class="card welcome" style="margin:3rem auto;max-width:560px"><h2>Can't reach Boardroom</h2><p>${esc(e.message)}</p><p class="muted">Start it with <code>boardroom ui</code> and open the link it prints.</p></div>`;
    throw e;
  }
  if (!S.dir) S.dir = S.state.run.dir || S.state.default_dir;
  render();
}

async function refreshModels() {
  try { S.models = await api("/api/models"); } catch { S.models = []; }
  renderTeam(); renderModels();
}

// --- event stream -----------------------------------------------------------------------------
let es = null;
function connectEvents() {
  if (es) es.close();
  es = new EventSource(`/api/events?from=${S.evCount}&gen=${S.gen}&t=${encodeURIComponent(TOKEN)}`);
  es.addEventListener("reset", (e) => {
    S.gen = JSON.parse(e.data).generation;
    S.evCount = 0;
    S.run = new RunModel();
    S.filter = null;
    $("#feed").innerHTML = "";
    scheduleRender();
  });
  es.addEventListener("event", (e) => {
    S.evCount++;
    const ev = JSON.parse(e.data);
    S.run.apply(ev);
    addToFeed(ev);
    if (ev.type === "report" && ev.agent === "ceo" && !ev.to && S.state) S.state.run.state = "waiting";
    if (ev.type === "run_end" || (ev.type === "report" && ev.agent === "ceo" && !ev.to)) setTimeout(refresh, 400);
    if (ev.type === "run_start") setTimeout(refresh, 200);
    scheduleRender();
  });
  es.onerror = () => { es.close(); setTimeout(connectEvents, 1500); };
}

function addToFeed(ev) {
  const li = feedItem(ev);
  if (!li) return;
  const feed = $("#feed");
  const stick = feed.scrollHeight - feed.scrollTop - feed.clientHeight < 40;
  if (!matchesFilter(li, S.filter)) li.classList.add("hidden");
  feed.appendChild(li);
  while (feed.children.length > 1500) feed.firstChild.remove();
  if (stick) feed.scrollTop = feed.scrollHeight;
}

// --- rendering ----------------------------------------------------------------------------------
let renderQueued = false;
function scheduleRender() {
  if (renderQueued) return;
  renderQueued = true;
  requestAnimationFrame(() => { renderQueued = false; renderOffice(); });
}

function render() {
  const st = S.state;
  if (!st) return;
  $("#companyName").textContent = st.company.name;
  renderOffice();
  renderTeam();
  renderAccounts();
  renderModels();
  for (const chip of [$("#folderChip"), $("#historyFolder")]) chip.innerHTML = `<span>${esc(S.dir)}</span>`;
}

function runState() { return S.state ? S.state.run.state : "idle"; }

function renderOffice() {
  const st = S.state;
  if (!st) return;
  const noAccounts = !st.accounts.length;
  const rs = runState();
  const hasRun = S.run.events.length > 0;
  const busy = rs === "working" || rs === "waiting";

  // welcome / composer / runbar
  const welcome = $("#welcome");
  welcome.classList.toggle("hidden", !noAccounts);
  if (noAccounts) {
    welcome.innerHTML = `<h2>Welcome to Boardroom 👋</h2>
      <p>Boardroom turns the AI accounts you already have into a small company that works on your projects together.</p>
      <div class="steps">
        <div class="step"><b>1. Connect an account</b>Claude, ChatGPT, DeepSeek, a free local model…</div>
        <div class="step"><b>2. Meet your team</b>Boardroom picks a CEO, a debugger and workers for you.</div>
        <div class="step"><b>3. Give it a task</b>Watch everyone work, then read the CEO's report.</div>
      </div>
      <button class="primary" data-goto="accounts">Connect your first account</button>`;
  }
  $("#composer").classList.toggle("hidden", noAccounts || busy);
  $("#runbar").classList.toggle("hidden", !busy);
  const chip = $("#runChip");
  chip.className = "run-chip " + rs;
  chip.textContent = rs === "working" ? "● Working…" : rs === "waiting" ? "● Waiting for you" : "";
  if (busy) {
    $("#runGoal").textContent = S.run.goal || st.run.goal;
    $("#runbar").className = "card runbar" + (rs === "waiting" ? " waiting" : "");
    $("#stopBtn").classList.toggle("hidden", rs !== "working");
    updateTimer();
  }

  // team chart + feed
  $("#stage").classList.toggle("hidden", noAccounts || !st.members.length);
  const roster = hasRun ? S.run : new RunModel(st.members);
  if (!hasRun) roster.setRoster(st.members);
  renderChart(roster);
  const feed = $("#feed");
  if (!hasRun && !feed.children.length) {
    feed.innerHTML = `<li class="feed-empty">Nothing yet. Give your company a task and you'll see everything here as it happens.</li>`;
  } else if (hasRun) {
    const empty = $(".feed-empty", feed);
    if (empty) empty.remove();
  }
  $("#clearFilter").classList.toggle("hidden", !S.filter);

  // the CEO's report
  const rep = S.run.reports[S.run.reports.length - 1];
  const showReport = rep && (rs === "waiting" || rs === "finished" || S.run.ended);
  $("#report").classList.toggle("hidden", !showReport);
  if (showReport) {
    const n = S.run.reports.length;
    $("#reportTitle").textContent = n > 1 ? `The CEO's report (round ${n})` : "The CEO's report";
    const body = $("#reportBody");
    if (body.dataset.ts !== String(rep.ts)) { body.innerHTML = md(rep.text); body.dataset.ts = String(rep.ts); }
    $("#replyBox").classList.toggle("hidden", rs !== "waiting");
    const after = rs !== "waiting";
    $("#afterBox").classList.toggle("hidden", !after);
    if (after) $("#afterText").textContent = S.run.ok === false ? "The run was stopped." : "This task is finished. Everything is saved in History.";
  }

  // approval question
  const dlg = $("#askDialog");
  if (S.run.pendingAsk && !dlg.open) {
    $("#askWho").textContent = nameOf(S.run.pendingAsk.agent);
    $("#askCmd").textContent = S.run.pendingAsk.command;
    dlg.showModal();
  } else if (!S.run.pendingAsk && dlg.open) dlg.close();
}

function memberCard(m, opts = {}) {
  const status = m.status || "idle";
  const subs = [...m.subs.values()].slice(-6);
  const [model, account] = String(m.model || "").split(":").reverse();
  const classes = ["member"];
  if (S.filter === m.id) classes.push("selected");
  else if (S.filter && !opts.static) classes.push("dim");
  return `<div class="${classes.join(" ")}" data-member="${esc(m.id)}" style="--c:${colorOf(m.id)}">
    <div class="member-head">
      <div class="avatar">${iconOf(m.role)}</div>
      <div class="member-id"><div class="member-name">${esc(nameOf(m.id))}</div>
        <div class="member-model">${esc(model || "")}${account ? " · " + esc(account) : ""}</div></div>
      <span class="status ${status}">${STATUS_TEXT[status] || status}</span>
    </div>
    <div class="member-task ${m.task ? "" : "empty"}">${m.task ? esc(firstLine(m.task, 220)) : roleLine(m.role)}</div>
    <div class="member-action">${esc(m.action || "")}</div>
    ${subs.length ? `<div class="subs">${subs.map((s) => `<div class="sub ${s.status}" title="${esc(s.task)}"><span class="dot"></span><span class="sub-text"><b>helper ${esc(s.id.split(".").pop().replace(/^sub/, ""))}</b> ${esc(firstLine(s.action || s.task, 80))}</span></div>`).join("")}</div>` : ""}
    <div class="member-foot">${memberFoot(m)}</div>
  </div>`;
}
function memberFoot(m) {
  const custom = !["ceo", "debugger", "worker"].includes(m.role) ? `<span>${esc(capitalize(m.role))}</span>` : "<span></span>";
  const usage = m.tokens ? kTokens(m.tokens) + " tokens" + (m.cost >= 0.005 ? ` · ~${money(m.cost)}` : "") : "";
  return usage || custom !== "<span></span>" ? `${custom}<span>${usage}</span>` : "";
}
const capitalize = (s) => String(s || "").replace(/^\w/, (c) => c.toUpperCase());
function roleLine(role) {
  const r = S.state && S.state.roles[role];
  return esc(r ? r.description : "");
}

function renderChart(model) {
  const members = [...model.members.values()];
  const ceo = members.find((m) => m.role === "ceo");
  const rest = members.filter((m) => m !== ceo);
  $("#chartTop").innerHTML = ceo ? memberCard(ceo) : "";
  $("#chartRow").innerHTML = rest.map((m) => memberCard(m)).join("");
  requestAnimationFrame(() => drawWires(model));
}

function drawWires(model) {
  const chart = $("#chart"), svg = $("#wires");
  const top = $("#chartTop .member");
  const kids = $$("#chartRow .member");
  if (!top || !kids.length || chart.offsetParent === null) { svg.innerHTML = ""; return; }
  const box = chart.getBoundingClientRect();
  const t = top.getBoundingClientRect();
  const x1 = t.left + t.width / 2 - box.left, y1 = t.bottom - box.top;
  const firstTop = kids[0].getBoundingClientRect().top - box.top;
  const busY = y1 + (firstTop - y1) / 2;
  let paths = "";
  for (const el of kids) {
    const r = el.getBoundingClientRect();
    const x2 = r.left + r.width / 2 - box.left, y2 = r.top - box.top;
    let d;
    if (Math.abs(y2 - firstTop) < 4) {
      d = `M${x1},${y1} V${busY} H${x2} V${y2}`;
    } else {
      // a later row: run down the gap to the left of the card, then in above it
      const gx = r.left - box.left - 7, rowY = y2 - 11;
      d = `M${x1},${y1} V${busY} H${gx} V${rowY} H${x2} V${y2}`;
    }
    const m = model.members.get(el.dataset.member);
    const active = m && m.wire && ["queued", "working", "waiting"].includes(m.status);
    paths += `<path class="${active ? "active" : ""}" style="--wire:${colorOf(el.dataset.member)}" d="${d}"/>`;
  }
  svg.innerHTML = paths;
}
new ResizeObserver(() => drawWires(S.run.events.length ? S.run : new RunModel(S.state ? S.state.members : []))).observe(document.documentElement);

function updateTimer() {
  const start = S.run.startTs;
  const last = S.run.reports[S.run.reports.length - 1];
  const end = S.run.endTs || (runState() === "waiting" && last ? last.ts : Date.now() / 1000);
  const cost = [...S.run.members.values()].reduce((t, m) => t + m.cost, 0);
  $("#runTimer").textContent = (start ? duration(end - start) : "") + (cost >= 0.005 ? ` · about ${money(cost)}` : "");
  $("#runTimer").title = cost ? "Estimated from list prices; subscriptions aren't counted. Your provider's bill is what counts." : "";
}
setInterval(() => { if (runState() === "working") updateTimer(); }, 1000);

// --- team page ----------------------------------------------------------------------------------
function modelOptions(selected, { allowSame = false } = {}) {
  const groups = new Map();
  for (const m of S.models) {
    if (!groups.has(m.account)) groups.set(m.account, []);
    groups.get(m.account).push(m);
  }
  let html = allowSame ? `<option value="">Same model as above</option>` : "";
  let found = !selected;
  for (const [account, list] of groups) {
    html += `<optgroup label="${esc(account)}">`;
    for (const m of list) {
      const sel = m.ref === selected ? " selected" : "";
      if (sel) found = true;
      html += `<option value="${esc(m.ref)}"${sel}>${esc(m.model)} — ${m.tier}</option>`;
    }
    html += "</optgroup>";
  }
  if (!found) html = `<option value="${esc(selected)}" selected>${esc(selected)}</option>` + html;
  return html;
}

function renderTeam() {
  const st = S.state;
  if (!st) return;
  $("#problems").innerHTML = st.problems.map((p) => `<div class="problem">⚠️ ${esc(p)}</div>`).join("");
  $("#members").innerHTML = st.members.map((m) => `
    <div class="member edit-member" style="--c:${colorOf(m.id)}">
      <div class="member-head"><div class="avatar">${iconOf(m.role)}</div>
        <div class="member-id"><div class="member-name">${esc(nameOf(m.id))}</div><div class="member-model">${esc(m.model.split(":").reverse().join(" · "))}</div></div></div>
      <label>Model<select data-set="${esc(m.id)}">${modelOptions(m.model)}</select></label>
      <label>Model for its helpers<select data-set-sub="${esc(m.id)}">${modelOptions(m.subagent_model || "", { allowSame: true })}</select></label>
      <div class="row"><span class="muted small">${esc(st.roles[m.role] ? st.roles[m.role].description : "")}</span>
        ${m.role === "ceo" ? "" : `<button class="danger ghost small" data-fire="${esc(m.id)}">Let go</button>`}</div>
    </div>`).join("") || `<p class="muted">Nobody on the team yet. Connect an account, then build the team automatically.</p>`;
  const roles = Object.keys(st.roles).filter((r) => r !== "ceo" || !st.members.some((m) => m.role === "ceo"))
    .sort((a, b) => (b === "worker") - (a === "worker"));
  const hireRole = $("#hireRole");
  const prevRole = hireRole.value;
  hireRole.innerHTML = roles.map((r) => `<option value="${esc(r)}">${esc(capitalize(r))}</option>`).join("");
  if (roles.includes(prevRole)) hireRole.value = prevRole;
  $("#hireModel").innerHTML = modelOptions("");
  $("#autoTemplate").innerHTML = Object.entries(st.templates).map(([k, v]) => `<option value="${esc(k)}">${esc(capitalize(k))}: ${esc(v)}</option>`).join("");
  // settings
  const c = st.company;
  if (document.activeElement?.id !== "setName") $("#setName").value = c.name;
  $("#setAutonomy").innerHTML = `<legend>How much may members do without asking you?</legend>` + st.autonomy.map((a) =>
    `<label><input type="radio" name="autonomy" value="${a.id}" ${a.id === c.autonomy ? "checked" : ""}><span><b>${esc(a.label)}</b><br><span class="muted small">${esc(a.about)}</span></span></label>`).join("");
  $("#setMaxSteps").value = c.max_steps;
  $("#setMaxDepth").value = c.max_depth;
  $("#setMaxSubagents").value = c.max_subagents;
  $("#setBudget").value = c.token_budget;
  $("#setSandbox").value = c.sandbox;
  $("#runAutonomy").innerHTML = st.autonomy.map((a) => `<option value="${a.id}" ${a.id === c.autonomy ? "selected" : ""}>${esc(a.label)}</option>`).join("");
}

// --- accounts page --------------------------------------------------------------------------------
const KIND_LABEL = { "claude-code": "Claude subscription (through Claude Code)", codex: "ChatGPT subscription (through Codex)", "gemini-cli": "Google account (through the Gemini CLI)", anthropic: "Anthropic API", "openai-compat": "API" };
const KIND_ICON = { "claude-code": "🟠", codex: "🟢", "gemini-cli": "🔷", anthropic: "🔶", "openai-compat": "🔌" };

function renderAccounts() {
  const st = S.state;
  if (!st) return;
  $("#accountList").innerHTML = st.accounts.map((a) => {
    const preset = st.providers.find((p) => p.id === a.preset);
    const kind = a.kind === "openai-compat" ? (preset && a.preset !== "custom" ? `${preset.label}${preset.needs_key ? " API" : ""}` : "API")
      : KIND_LABEL[a.kind] || a.kind;
    const best = a.models.slice(0, 4).join(", ") + (a.models.length > 4 ? `, +${a.models.length - 4} more` : "");
    return `<div class="account"><div class="avatar">${KIND_ICON[a.kind] || "🔌"}</div>
      <div class="account-info"><b>${esc(a.name)}</b> <span class="muted small">· ${esc(kind)}</span><br>
        <span class="muted small">${a.models.length} models: ${esc(best)}</span></div>
      <span class="account-test" data-test-result="${esc(a.name)}"></span>
      <button class="small" data-test="${esc(a.name)}">Test</button>
      <button class="small danger ghost" data-remove="${esc(a.name)}">Remove</button></div>`;
  }).join("") || `<p class="muted">No accounts yet. Pick one below to get started.</p>`;
  const connectedPresets = new Set(st.accounts.map((a) => a.kind === "openai-compat" ? a.preset : a.kind));
  $("#providers").innerHTML = st.providers.map((p) =>
    `<button class="provider ${connectedPresets.has(p.id) ? "connected" : ""}" data-provider="${esc(p.id)}"><b>${esc(p.label)}</b><span>${esc(p.about)}</span></button>`).join("");
}

function renderModels() {
  $("#modelRows").innerHTML = S.models.map((m) =>
    `<tr><td>${esc(m.model)}</td><td>${esc(m.account)}</td><td><span class="tier ${m.tier}">${m.tier}</span></td><td>${m.score}</td><td>${esc(m.family)}</td></tr>`).join("");
}

function openConnect(pid) {
  const p = S.state.providers.find((x) => x.id === pid);
  const dlg = $("#connectDialog");
  dlg.dataset.provider = pid;
  $("#connectTitle").textContent = `Connect ${p.label}`;
  const notes = {
    "claude-code": "Uses the Claude Code app and the account you're logged into there. Don't have it? Install it from claude.com/claude-code and run `claude auth login` once.",
    codex: "Uses the Codex app and the ChatGPT account you're logged into there. Don't have it? Run `npm install -g @openai/codex`, then `codex login` once.",
    "gemini-cli": "Uses the Gemini CLI and the Google account you signed in with there (the free tier works too). Don't have it? Run `npm install -g @google/gemini-cli`, then `gemini` once to sign in.",
    ollama: "Uses models running on this computer with Ollama (ollama.com). Free, and nothing leaves your computer.",
    lmstudio: "Uses models running on this computer with LM Studio. Free, and nothing leaves your computer.",
    custom: "Any service that works like OpenAI's API. Its address usually ends in /v1.",
  };
  $("#connectAbout").textContent = notes[pid] || `${p.about}. Your key is stored only on this computer.`;
  $("#keyRow").classList.toggle("hidden", !p.needs_key);
  $("#envRow").classList.toggle("hidden", !p.needs_key);
  $("#urlRow").classList.toggle("hidden", !["custom", "ollama", "lmstudio"].includes(pid));
  $("#connectUrl").placeholder = pid === "ollama" ? "http://localhost:11434/v1 (default)" : pid === "lmstudio" ? "http://localhost:1234/v1 (default)" : "https://example.com/v1";
  for (const id of ["connectKey", "connectEnv", "connectUrl", "connectName", "connectModels"]) $("#" + id).value = "";
  $("#connectEnv").placeholder = p.key_env ? `e.g. ${p.key_env}` : "e.g. MY_API_KEY";
  $("#connectError").textContent = "";
  $("#connectGo").disabled = false;
  $("#connectGo").textContent = "Connect";
  dlg.showModal();
}

// --- history page ------------------------------------------------------------------------------
async function renderHistory() {
  const list = $("#runList");
  let runs = [];
  try { runs = await api(`/api/runs?dir=${encodeURIComponent(S.dir)}`); }
  catch (e) { list.innerHTML = `<li class="muted">${esc(e.message)}</li>`; return; }
  list.innerHTML = runs.map((r) => {
    const badge = r.ok === true ? `<span class="badge ok">done</span>` : r.ok === false ? `<span class="badge bad">stopped</span>` : `<span class="badge open">in progress</span>`;
    const when = r.name.replace(/^(\d{4})-(\d\d)-(\d\d)_(\d\d)(\d\d)(\d\d).*/, "$1-$2-$3 $4:$5");
    return `<li data-run="${esc(r.name)}">${badge}<span class="run-goal">${esc(r.goal || "(no goal)")}</span><span class="run-when">${esc(when)}${r.seconds ? " · " + duration(r.seconds) : ""}</span></li>`;
  }).join("") || `<li class="muted" style="cursor:default">No past work in this folder yet.</li>`;
}

async function openRun(name) {
  const d = await act(() => api(`/api/run?dir=${encodeURIComponent(S.dir)}&name=${encodeURIComponent(name)}`));
  const box = $("#runDetail");
  box.classList.remove("hidden");
  const start = d.events.find((e) => e.type === "run_start");
  $("#runDetailTitle").textContent = start ? firstLine(start.goal, 90) : name;
  $("#runDetailReport").innerHTML = d.report ? md(d.report) : `<p class="muted">No report.</p>`;
  const feed = $("#runDetailFeed");
  feed.innerHTML = "";
  for (const ev of d.events) { const li = feedItem(ev); if (li) feed.appendChild(li); }
  box.scrollIntoView({ behavior: "smooth", block: "start" });
}

// --- folder picker ----------------------------------------------------------------------------------
let folderNow = "";
async function browse(path) {
  try {
    const d = await api(`/api/dirs?path=${encodeURIComponent(path)}`);
    folderNow = d.path;
    $("#folderPath").textContent = d.path;
    $("#folderUp").disabled = !d.parent;
    $("#folderUp").dataset.path = d.parent || "";
    $("#folderHome").dataset.path = d.home;
    $("#folderList").innerHTML = d.dirs.map((n) => `<li data-dir="${esc(n)}">${esc(n)}</li>`).join("") || `<li class="empty">No folders inside.</li>`;
  } catch (e) { toast(e.message, true); }
}
function chooseFolder(after) {
  $("#folderDialog").dataset.after = after || "";
  $("#newFolderName").value = "";
  browse(S.dir || S.state.default_dir);
  $("#folderDialog").showModal();
}
const joinPath = (a, b) => a.replace(/[\\/]+$/, "") + (a.includes("\\") && !a.includes("/") ? "\\" : "/") + b;

// --- markdown (small and safe: text is escaped first) ------------------------------------------
function md(src) {
  const lines = String(src || "").replace(/\r\n/g, "\n").split("\n");
  const out = [];
  const isList = (l) => /^\s*([-*+]|\d+[.)])\s+/.test(l);
  const isBlockStart = (l) => /^```/.test(l) || /^#{1,4}\s/.test(l) || isList(l) || /^\|.*\|\s*$/.test(l);
  let i = 0;
  while (i < lines.length) {
    const l = lines[i];
    if (/^```/.test(l)) {
      const buf = []; i++;
      while (i < lines.length && !/^```/.test(lines[i])) buf.push(lines[i++]);
      i++;
      out.push(`<pre><code>${esc(buf.join("\n"))}</code></pre>`);
    } else if (/^#{1,4}\s/.test(l)) {
      const n = l.match(/^#+/)[0].length;
      out.push(`<h${n}>${inline(l.replace(/^#+\s+/, ""))}</h${n}>`); i++;
    } else if (isList(l)) {
      const ordered = /^\s*\d/.test(l), items = [];
      while (i < lines.length && isList(lines[i])) items.push(lines[i++].replace(/^\s*([-*+]|\d+[.)])\s+/, ""));
      out.push(`<${ordered ? "ol" : "ul"}>${items.map((x) => `<li>${inline(x)}</li>`).join("")}</${ordered ? "ol" : "ul"}>`);
    } else if (/^\|.*\|\s*$/.test(l) && i + 1 < lines.length && /^\|[\s:|-]+\|\s*$/.test(lines[i + 1])) {
      const cells = (row) => row.trim().replace(/^\||\|$/g, "").split("|").map((c) => inline(c.trim()));
      const head = cells(l); i += 2;
      const rows = [];
      while (i < lines.length && /^\|.*\|\s*$/.test(lines[i])) rows.push(cells(lines[i++]));
      out.push(`<table><thead><tr>${head.map((c) => `<th>${c}</th>`).join("")}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody></table>`);
    } else if (!l.trim()) {
      i++;
    } else {
      const para = [lines[i++]];
      while (i < lines.length && lines[i].trim() && !isBlockStart(lines[i])) para.push(lines[i++]);
      out.push(`<p>${inline(para.join(" "))}</p>`);
    }
  }
  return out.join("");
}
function inline(s) {
  const codes = [];
  let t = esc(s).replace(/`([^`]+)`/g, (_, c) => { codes.push(c); return `\u0000${codes.length - 1}\u0000`; });
  t = t.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    .replace(/(^|[\s(])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>")
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
  return t.replace(/\u0000(\d+)\u0000/g, (_, n) => `<code>${codes[+n]}</code>`);
}

// --- wiring up ------------------------------------------------------------------------------------
function showTab(name) {
  for (const b of $$(".tabs button")) b.classList.toggle("active", b.dataset.tab === name);
  for (const p of $$(".tab-page")) p.classList.toggle("active", p.id === name);
  store.set("boardroom-tab", name);
  if (name === "history") renderHistory();
  if (name === "team" || name === "accounts") refreshModels();
  if (name === "office") requestAnimationFrame(() => drawWires(S.run.events.length ? S.run : new RunModel(S.state ? S.state.members : [])));
}

document.addEventListener("click", async (e) => {
  const t = e.target.closest("button, [data-member], [data-run], [data-dir], .detail");
  if (!t) return;
  if (t.matches(".tabs button")) return showTab(t.dataset.tab);
  if (t.dataset.goto) return showTab(t.dataset.goto);
  if (t.classList.contains("detail")) return t.classList.toggle("open");
  if (t.dataset.member && !t.classList.contains("edit-member")) {
    S.filter = S.filter === t.dataset.member ? null : t.dataset.member;
    for (const li of $("#feed").children) li.classList.toggle("hidden", !matchesFilter(li, S.filter));
    return renderOffice();
  }
  if (t.dataset.run) return openRun(t.dataset.run);
  if (t.dataset.dir) return browse(joinPath(folderNow, t.dataset.dir));
  if (t.dataset.provider) return openConnect(t.dataset.provider);
  if (t.dataset.fire) {
    if (!confirm(`Let ${nameOf(t.dataset.fire)} go?`)) return;
    await act(() => api("/api/fire", { id: t.dataset.fire }), `${nameOf(t.dataset.fire)} has left the team`);
    return refresh();
  }
  if (t.dataset.test) {
    const out = $(`[data-test-result="${CSS.escape(t.dataset.test)}"]`);
    out.className = "account-test"; out.textContent = "testing…";
    try {
      const r = await api("/api/test", { name: t.dataset.test });
      out.className = "account-test " + (r.ok ? "ok" : "bad");
      out.textContent = (r.ok ? "✓ " : "✗ ") + r.message;
    } catch (err) { out.className = "account-test bad"; out.textContent = "✗ " + err.message; }
    return;
  }
  if (t.dataset.remove) {
    if (!confirm(`Remove the account "${t.dataset.remove}"? Team members using it will need a new model.`)) return;
    await act(() => api("/api/disconnect", { name: t.dataset.remove }), "Account removed");
    await refresh(); return refreshModels();
  }
  if (t.dataset.answer) {
    const a = t.dataset.answer;
    await act(() => api("/api/answer", { allow: a !== "no", always: a === "always" }));
    $("#askDialog").close();
    return;
  }
  if (t.dataset.path !== undefined && (t.id === "folderUp" || t.id === "folderHome")) return browse(t.dataset.path);
});

$("#clearFilter").onclick = () => {
  S.filter = null;
  for (const li of $("#feed").children) li.classList.remove("hidden");
  renderOffice();
};

$("#startBtn").onclick = async () => {
  const goal = $("#goal").value.trim();
  if (!goal) { $("#goal").focus(); return toast("Write what the company should do first.", true); }
  $("#startBtn").disabled = true;
  try {
    await act(() => api("/api/run", { goal, dir: S.dir, autonomy: $("#runAutonomy").value }));
    $("#goal").value = "";
    S.filter = null;
    await refresh();
  } finally { $("#startBtn").disabled = false; }
};
$("#goal").addEventListener("keydown", (e) => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) $("#startBtn").click(); });

$("#stopBtn").onclick = async () => {
  if (!confirm("Stop every member now? Work in progress will be cut short.")) return;
  await act(() => api("/api/stop", {}), "Stopping everyone…");
};
$("#replyBtn").onclick = async () => {
  const text = $("#replyText").value.trim();
  if (!text) return $("#replyText").focus();
  await act(() => api("/api/reply", { text }));
  $("#replyText").value = "";
  await refresh();
};
$("#replyText").addEventListener("keydown", (e) => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) $("#replyBtn").click(); });
$("#finishBtn").onclick = async () => { await act(() => api("/api/finish", {}), "Saved. Find it later in History."); await refresh(); };
$("#newRunBtn").onclick = () => {
  S.run = new RunModel(); S.filter = null; $("#feed").innerHTML = "";
  if (S.state) S.state.run.state = "idle";
  renderOffice();
  $("#goal").focus();
};

$("#folderChip").onclick = () => chooseFolder("office");
$("#historyFolder").onclick = () => chooseFolder("history");
$("#folderCancel").onclick = () => $("#folderDialog").close();
$("#folderChoose").onclick = () => {
  S.dir = folderNow; store.set("boardroom-dir", S.dir);
  $("#folderDialog").close();
  render();
  if ($("#folderDialog").dataset.after === "history") { $("#runDetail").classList.add("hidden"); renderHistory(); }
};
$("#newFolderBtn").onclick = async () => {
  const name = $("#newFolderName").value.trim();
  if (!name || /[\\/]/.test(name)) return toast("Type a folder name (without slashes).", true);
  const r = await act(() => api("/api/mkdir", { path: joinPath(folderNow, name) }));
  $("#newFolderName").value = "";
  browse(r.path);
};
$("#closeDetail").onclick = () => $("#runDetail").classList.add("hidden");

$("#hireBtn").onclick = async () => {
  const model = $("#hireModel").value;
  if (!model) return toast("Pick a model first.", true);
  await act(() => api("/api/hire", { role: $("#hireRole").value, model, count: +$("#hireCount").value || 1 }), "Hired!");
  refresh();
};
$("#autoBtn").onclick = async () => {
  if (S.state.members.length && !confirm("Replace the whole team with an automatic one?")) return;
  await act(() => api("/api/org/auto", { workers: +$("#autoWorkers").value, template: $("#autoTemplate").value, spread: $("#autoSpread").checked }), "New team ready");
  refresh();
};
$("#members").addEventListener("change", async (e) => {
  const sel = e.target;
  if (sel.dataset.set) await act(() => api("/api/org/set", { who: sel.dataset.set, model: sel.value }), "Updated");
  else if (sel.dataset.setSub) {
    const m = S.state.members.find((x) => x.id === sel.dataset.setSub);
    await act(() => api("/api/org/set", { who: sel.dataset.setSub, model: sel.value || m.model, subagents: true }), "Updated");
  }
  refresh();
});
$("#saveSettings").onclick = async () => {
  const autonomy = ($('input[name="autonomy"]:checked') || {}).value;
  await act(() => api("/api/settings", {
    name: $("#setName").value.trim(), autonomy,
    max_steps: +$("#setMaxSteps").value, max_depth: +$("#setMaxDepth").value,
    max_subagents: +$("#setMaxSubagents").value, token_budget: +$("#setBudget").value,
    sandbox: $("#setSandbox").value,
  }), "Settings saved");
  refresh();
};

$("#connectCancel").onclick = () => $("#connectDialog").close();
$("#connectForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const pid = $("#connectDialog").dataset.provider;
  const body = { provider: pid, key: $("#connectKey").value.trim(), key_env: $("#connectEnv").value.trim(),
    base_url: $("#connectUrl").value.trim(), name: $("#connectName").value.trim(), models: $("#connectModels").value.trim() };
  const p = S.state.providers.find((x) => x.id === pid);
  if (p.needs_key && !body.key && !body.key_env) { $("#connectError").textContent = "Paste your API key (or the name of the variable that holds it)."; return; }
  $("#connectGo").disabled = true; $("#connectGo").textContent = "Connecting…"; $("#connectError").textContent = "";
  try {
    const r = await api("/api/connect", body);
    $("#connectDialog").close();
    toast(`Connected ${r.name}!`);
    await refresh(); refreshModels();
  } catch (err) {
    $("#connectError").textContent = err.message;
  } finally { $("#connectGo").disabled = false; $("#connectGo").textContent = "Connect"; }
});

// --- start ----------------------------------------------------------------------------------------
(async () => {
  if (!TOKEN) {
    document.body.innerHTML = `<div class="card welcome" style="margin:3rem auto;max-width:560px"><h2>Open Boardroom from its link</h2><p>Run <code>boardroom ui</code> in a terminal; it opens this page for you with the right link.</p></div>`;
    return;
  }
  await refresh();
  showTab(START_TAB || store.get("boardroom-tab", "office"));
  connectEvents();
  refreshModels();
})();
