import { Controller } from "@hotwired/stimulus"

// The Reviews and Issues views: repo, community, scope, search and people
// filters over the PR or issue cards, the right-click menu that excludes a
// repo from the viewer's own views, plus the hover tooltip. Filters hide cards (and keep the column
// counts honest); the state lives in the URL hash like the board's, so it
// survives the live refresh and can be shared as a link.
export default class extends Controller {
  static targets = [
    "card", "count", "empty", "tooltip", "search",
    "repoRow", "repoBtn", "repoBadge", "repoClear", "communityBtn", "scopeBtn",
    "personRow", "personCount", "peopleBtn", "peopleLabel", "peopleClear",
    "roleBtn", "noReplyRow", "teamRow", "repoCtx", "repoCtxBtn"
  ]
  static values = { viewer: String }
  static ROLES = [ "any", "author", "replied", "requested" ]
  // Attributes this controller owns. A live refresh must not put the server's
  // defaults back, or an open menu snaps shut and the cards blink.
  static OWNED = [ "data-hidden", "data-on" ]

  connect() {
    this._state = this._blank()
    this._load()
    this._sync()
    this._onMorph = () => { this._load(); this._sync() }
    document.addEventListener("turbo:morph", this._onMorph)
    this._onBeforeMorphAttr = (event) => this._keepAttr(event)
    document.addEventListener("turbo:before-morph-attribute", this._onBeforeMorphAttr)
    this._onMove = () => { this._doHide(); this._closeRepoMenu() }
    window.addEventListener("scroll", this._onMove, true)
    window.addEventListener("resize", this._onMove)
    this._onKey = (e) => { if (e.key === "Escape") this._closeRepoMenu() }
    document.addEventListener("keydown", this._onKey)
    this._onPointer = (e) => {
      if (this.hasRepoCtxTarget && !this.repoCtxTarget.hidden && !this.repoCtxTarget.contains(e.target)) this._closeRepoMenu()
    }
    document.addEventListener("mousedown", this._onPointer)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this._onMorph)
    document.removeEventListener("turbo:before-morph-attribute", this._onBeforeMorphAttr)
    window.removeEventListener("scroll", this._onMove, true)
    window.removeEventListener("resize", this._onMove)
    document.removeEventListener("keydown", this._onKey)
    document.removeEventListener("mousedown", this._onPointer)
  }

  // Keeps the reader's state through a live refresh: what is shown or ticked,
  // and any open dropdown or tooltip. Everything else morphs as usual, and
  // _sync re-applies the filters to the new cards right after.
  _keepAttr(event) {
    const el = event.target
    if (!this.element.contains(el)) return
    const attr = event.detail.attributeName
    if (this.constructor.OWNED.includes(attr)) return event.preventDefault()
    if (attr === "hidden" && (el.matches("[data-filter-dropdown-target='menu']") || el === this._tooltipEl())) {
      event.preventDefault()
    }
  }

  _tooltipEl() {
    return this.hasTooltipTarget ? this.tooltipTarget : null
  }

  // ---------- filters ----------
  toggleRepo(event) {
    event.stopPropagation()
    // An excluded repo has no cards on the page; right-click brings it back.
    if (event.currentTarget.dataset.excluded === "1") return
    this._toggleIn("r", event.currentTarget.dataset.repo)
  }

  // ---------- exclude a repo from the viewer's views ----------
  openRepoMenu(event) {
    if (!this.hasRepoCtxTarget) return
    event.preventDefault()
    event.stopPropagation()
    const row = event.currentTarget
    this._ctxRepo = row.dataset.repo
    this._ctxExclude = row.dataset.excluded !== "1"
    const btn = this.repoCtxBtnTarget
    btn.disabled = false
    btn.textContent = this._ctxExclude ? "Exclude from my view" : "Include in my view again"
    const menu = this.repoCtxTarget
    menu.hidden = false
    const w = menu.offsetWidth
    const h = menu.offsetHeight
    menu.style.left = `${Math.max(8, Math.min(event.clientX, window.innerWidth - w - 8))}px`
    menu.style.top = `${Math.max(8, Math.min(event.clientY, window.innerHeight - h - 8))}px`
    btn.focus()
  }

  // Saves the choice for the signed-in viewer, then refreshes the page: the
  // server leaves the repo's cards out, moves its row and redoes the tab counts.
  toggleExclude(event) {
    event.stopPropagation()
    const repo = this._ctxRepo
    if (!repo) return
    const excluded = this._ctxExclude
    this.repoCtxBtnTarget.disabled = true
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch("/repo_exclusion", {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ repo, excluded })
    }).then((res) => {
      if (!res.ok) throw new Error(`${res.status}`)
      this._closeRepoMenu()
      // A ticked repo that is now excluded would filter to nothing.
      if (excluded && this._state.r.includes(repo)) this._set({ r: this._state.r.filter((r) => r !== repo) })
      Turbo.visit(location.href, { action: "replace" })
    }).catch((e) => {
      console.error("Failed to save repo exclusion", e)
      this.repoCtxBtnTarget.disabled = false
      this.repoCtxBtnTarget.textContent = "Could not save. Try again."
    })
  }

  _closeRepoMenu() {
    if (this.hasRepoCtxTarget) this.repoCtxTarget.hidden = true
    this._ctxRepo = null
  }

  clearRepos(event) {
    event.stopPropagation()
    this._set({ r: [] })
  }

  // How a ticked person must relate to a PR for the card to stay.
  chooseRole(event) {
    event.stopPropagation()
    this._set({ o: event.currentTarget.dataset.role || "any" })
  }

  toggleNoReply(event) {
    event.stopPropagation()
    this._set({ n: !this._state.n })
  }

  // Ticks every team member at once, or unticks them all if all are ticked.
  toggleTeam(event) {
    event.stopPropagation()
    const team = this._team()
    const set = new Set(this._state.p)
    const all = team.length > 0 && team.every((l) => set.has(l))
    team.forEach((l) => (all ? set.delete(l) : set.add(l)))
    this._set({ p: [...set] })
  }

  togglePerson(event) {
    event.stopPropagation()
    this._toggleIn("p", event.currentTarget.dataset.login)
  }

  clearPeople(event) {
    event.stopPropagation()
    this._set({ p: [], n: false })
  }

  toggleCommunity() {
    this._set({ c: !this._state.c })
  }

  chooseScope(event) {
    this._set({ s: event.currentTarget.dataset.scope || "all" })
  }

  search(event) {
    this._set({ q: event.target.value || "" })
  }

  _toggleIn(key, value) {
    const set = new Set(this._state[key])
    set.has(value) ? set.delete(value) : set.add(value)
    this._set({ [key]: [...set] })
  }

  _set(patch) {
    Object.assign(this._state, patch)
    this._save()
    this._sync()
  }

  _matches(card) {
    const ds = card.dataset
    const st = this._state
    if (st.r.length && !st.r.includes(ds.repo)) return false
    if (st.c && ds.community !== "1") return false
    if (st.s === "me" && ds.needsMe !== "1") return false
    if (st.s === "mine" && !(this.viewerValue && this._involved(card, this.viewerValue, "any"))) return false
    if (st.n && ds.noReply !== "1") return false
    if (st.p.length && !st.p.some((login) => this._involved(card, login, st.o))) return false
    const q = st.q.trim().toLowerCase()
    return !q || (ds.search || "").includes(q)
  }

  _sync() {
    const st = this._state
    this.cardTargets.forEach((card) => { card.dataset.hidden = this._matches(card) ? "0" : "1" })

    this.element.querySelectorAll(".kb-reviews-col").forEach((col) => {
      const cards = [...col.querySelectorAll(".kb-pr-card")]
      const shown = cards.filter((c) => c.dataset.hidden !== "1").length
      const count = col.querySelector("[data-reviews-target='count']")
      if (count) count.textContent = shown === cards.length ? `${cards.length}` : `${shown}/${cards.length}`
      const empty = col.querySelector("[data-reviews-target='empty']")
      if (empty) {
        empty.hidden = shown > 0
        if (cards.length > 0) empty.textContent = "No PRs match the filters."
      }
    })

    this.repoRowTargets.forEach((row) => { row.dataset.on = st.r.includes(row.dataset.repo) ? "1" : "0" })
    if (this.hasRepoBtnTarget) this.repoBtnTarget.dataset.on = st.r.length ? "1" : "0"
    if (this.hasRepoBadgeTarget) {
      this.repoBadgeTarget.hidden = st.r.length === 0
      this.repoBadgeTarget.textContent = st.r.length
    }
    if (this.hasRepoClearTarget) this.repoClearTarget.hidden = st.r.length === 0
    if (this.hasCommunityBtnTarget) this.communityBtnTarget.dataset.on = st.c ? "1" : "0"
    this.scopeBtnTargets.forEach((b) => { b.dataset.on = b.dataset.scope === st.s ? "1" : "0" })
    this._syncPeople()
    if (this.hasSearchTarget && this.searchTarget.value !== st.q) this.searchTarget.value = st.q
  }

  _syncPeople() {
    const st = this._state
    const mark = (row, on) => {
      row.dataset.on = on ? "1" : "0"
      const chk = row.querySelector(".check")
      if (chk) chk.hidden = !on
    }
    this.personRowTargets.forEach((row) => mark(row, st.p.includes(row.dataset.login)))
    this.roleBtnTargets.forEach((b) => { b.dataset.on = b.dataset.role === st.o ? "1" : "0" })
    if (this.hasNoReplyRowTarget) mark(this.noReplyRowTarget, st.n)
    const team = this._team()
    const teamOn = team.length > 0 && team.every((l) => st.p.includes(l))
    if (this.hasTeamRowTarget) mark(this.teamRowTarget, teamOn)

    // Each person's count follows the role switch, over all PRs.
    const cards = this.cardTargets
    this.personRowTargets.forEach((row) => {
      const count = row.querySelector("[data-reviews-target='personCount']")
      if (count) count.textContent = cards.filter((c) => this._involved(c, row.dataset.login, st.o)).length
    })

    // A blue ring on whoever made a card match.
    cards.forEach((card) => {
      card.querySelectorAll(".kb-avatar[data-login]").forEach((av) => {
        const login = av.dataset.login
        const picked = st.p.includes(login) && this._involved(card, login, st.o)
        const me = st.s === "mine" && login === this.viewerValue
        av.classList.toggle("kb-avatar-hit", picked || me)
      })
    })

    let who = ""
    if (teamOn && st.p.length === team.length) who = "My team"
    else if (st.p.length === 1) {
      const row = this.personRowTargets.find((r) => r.dataset.login === st.p[0])
      who = row?.querySelector(".name")?.textContent || st.p[0]
    } else if (st.p.length) who = `${st.p.length} people`
    const on = st.p.length > 0 || st.n
    if (this.hasPeopleBtnTarget) this.peopleBtnTarget.dataset.on = on ? "1" : "0"
    if (this.hasPeopleLabelTarget) this.peopleLabelTarget.textContent = [ st.n ? "No reply" : "", who ].filter(Boolean).join(" · ") || "People"
    if (this.hasPeopleClearTarget) this.peopleClearTarget.hidden = !on
  }

  _involved(card, login, role) {
    const ds = card.dataset
    const has = (attr) => (ds[attr] || "").split(" ").includes(login)
    if (role === "author") return ds.author === login
    if (role === "replied") return has("replied")
    if (role === "requested") return has("requested")
    return ds.author === login || has("replied") || has("requested")
  }

  _team() {
    const menu = this.element.querySelector(".kb-review-people")
    return (menu?.dataset.team || "").split(" ").filter(Boolean)
  }

  _blank() {
    return { r: [], p: [], q: "", c: false, s: "all", o: "any", n: false }
  }

  _save() {
    const st = this._state
    const empty = !st.r.length && !st.p.length && !st.q && !st.c && st.s === "all" && st.o === "any" && !st.n
    const hash = empty ? "" : encodeURIComponent(JSON.stringify(st))
    history.replaceState(null, "", hash ? `#${hash}` : location.pathname + location.search)
  }

  _load() {
    if (!location.hash) return
    try {
      const st = JSON.parse(decodeURIComponent(location.hash.slice(1)))
      this._state = {
        r: Array.isArray(st.r) ? st.r : [],
        p: Array.isArray(st.p) ? st.p : [],
        q: typeof st.q === "string" ? st.q : "",
        c: !!st.c,
        s: [ "all", "me", "mine" ].includes(st.s) ? st.s : "all",
        o: this.constructor.ROLES.includes(st.o) ? st.o : "any",
        n: !!st.n
      }
      // A shared link may tick a repo this viewer excluded; it has no cards here.
      const excluded = new Set(this.repoRowTargets.filter((row) => row.dataset.excluded === "1").map((row) => row.dataset.repo))
      this._state.r = this._state.r.filter((r) => !excluded.has(r))
      // A scope the viewer cannot use (no github login) falls back to All.
      const btn = this.scopeBtnTargets.find((b) => b.dataset.scope === this._state.s)
      if (btn && btn.disabled) this._state.s = "all"
    } catch (_) {}
  }

  // ---------- hover tooltip ----------
  showTooltip(event) {
    const card = event.currentTarget
    clearTimeout(this._ttTimer)
    this._ttTimer = setTimeout(() => this._renderTooltip(card), 140)
  }

  hideTooltip() {
    clearTimeout(this._ttTimer)
    this._doHide()
  }

  _doHide() {
    clearTimeout(this._ttTimer)
    if (this.hasTooltipTarget) this.tooltipTarget.hidden = true
  }

  _renderTooltip(card) {
    if (!this.hasTooltipTarget) return
    if (document.getElementById("kb-snooze")?.hidden === false) return
    let t = {}
    try { t = JSON.parse(card.dataset.tooltip || "{}") } catch (_) { return }
    const row = (label, value, style = "") => value
      ? `<span class="lbl">${label}</span><span class="val"${style ? ` style="${style}"` : ""}>${this._esc(value)}</span>`
      : ""
    const staleColor = t.stale === "critical" ? "#fca5a5" : t.stale === "stale" ? "#fdba74" : ""
    const waiting = t.stale && t.stale !== "fresh" ? `${t.waiting} · ${t.stale}` : t.waiting
    const hint = t.snoozable
      ? (t.snooze ? "Click to open on GitHub ↗ · right-click to see or lift the snooze"
                  : "Click to open on GitHub ↗ · right-click to snooze")
      : "Click to open on GitHub ↗"
    this.tooltipTarget.innerHTML = `
      <div class="kb-tt-row">
        <span class="kb-tt-id">${this._esc(t.id || "")}</span>
        <span class="kb-tt-state-pill" style="background:${this._esc(t.color || "#94a3b8")}">${this._esc(t.stage || "")}</span>
      </div>
      <div class="kb-tt-title">${this._esc(t.title || "")}</div>
      <div class="kb-tt-grid">
        ${row("Author", t.author)}
        ${row("Waiting", waiting, staleColor ? `color:${staleColor}` : "")}
        ${row("Open", t.open)}
        ${row("Decision", t.decision, "color:#f8fafc;font-weight:700")}
        ${row("Snoozed", t.snooze)}
        ${row("Last word", t.lastword)}
        ${row("Comments", t.comments)}
        ${row("Assigned", t.assigned)}
        ${row("Reviews", t.reviews)}
        ${row("CI", t.ci)}
        ${row("Size", t.size)}
        ${row("Jira", t.jira)}
        ${row("Labels", t.labels)}
      </div>
      <div class="kb-tt-hint">${hint}</div>
    `
    this.tooltipTarget.hidden = false
    this._position(card)
  }

  _position(card) {
    const tt = this.tooltipTarget
    const r = card.getBoundingClientRect()
    const W = tt.offsetWidth || 270
    let left = r.right + 10
    if (left + W > window.innerWidth - 8) left = r.left - W - 10
    left = Math.max(8, left)
    const top = Math.max(8, Math.min(r.top, window.innerHeight - tt.offsetHeight - 8))
    tt.style.left = `${left}px`
    tt.style.top = `${top}px`
  }

  _esc(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }
}
