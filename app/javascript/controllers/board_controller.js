import { Controller } from "@hotwired/stimulus"

// Owns the global board state: text search, status-pill highlight,
// people-filter (set from the people controller), and hover tooltip.
// Each card has data-search/data-assignee/data-display-status driving the match.
export default class extends Controller {
  static targets = ["statusPill", "statusClear", "activityPill", "activityClear", "ghostEpicBtn", "search", "root", "tooltip", "statusFilterBtn", "activityFilterBtn"]
  static values = {
    statuses: Array,
    assignees: Array,
    query: String,
    activity: Object,
    ghostEpic: Boolean
  }

  connect() {
    this._hydrate()
    this._onWinResize = () => this._positionTooltip()
    window.addEventListener("scroll", this._onWinResize, true)
    window.addEventListener("resize", this._onWinResize)
    this._setupColumnDrag()
    this._localizesyncTimestamp()
    this._onTurboRender = () => setTimeout(() => this._localizesyncTimestamp(), 0)
    document.addEventListener("turbo:before-stream-render", this._onTurboRender)
    if (this.hasTooltipTarget) {
      this._ttEnter = () => clearTimeout(this._ttHideTimer)
      this._ttLeave = () => { this._ttHideTimer = setTimeout(() => this._doHide(), 80) }
      this.tooltipTarget.addEventListener("mouseenter", this._ttEnter)
      this.tooltipTarget.addEventListener("mouseleave", this._ttLeave)
    }
    this._onMorphRestore = () => this._hydrate()
    document.addEventListener("turbo:morph", this._onMorphRestore)
  }

  disconnect() {
    window.removeEventListener("scroll", this._onWinResize, true)
    window.removeEventListener("resize", this._onWinResize)
    this._teardownColumnDrag()
    if (this._onTurboRender) document.removeEventListener("turbo:before-stream-render", this._onTurboRender)
    if (this.hasTooltipTarget && this._ttEnter) {
      this.tooltipTarget.removeEventListener("mouseenter", this._ttEnter)
      this.tooltipTarget.removeEventListener("mouseleave", this._ttLeave)
    }
    document.removeEventListener("turbo:morph", this._onMorphRestore)
  }

  // ---------- search ----------
  search(event) {
    this.queryValue = event.target.value || ""
    this.persist()
    this.apply()
  }

  // ---------- status pills ----------
  toggleStatus(event) {
    const el = event.currentTarget
    const id = el.dataset.state
    const set = new Set(this.statusesValue)
    set.has(id) ? set.delete(id) : set.add(id)
    this.statusesValue = [...set]
    this.persist()
    this.syncStatusUI()
    this.apply()
  }

  clearStatuses() {
    this.statusesValue = []
    this.persist()
    this.syncStatusUI()
    this.apply()
  }

  // ---------- activity pills ----------
  toggleActivity(event) {
    const el = event.currentTarget
    const elDir = el.dataset.dir || null
    const elDays = el.dataset.days ? parseInt(el.dataset.days, 10) : null
    const cur = this.activityValue || {}

    if (elDir && elDays) {
      // legacy combined button
      this.activityValue = (cur.dir === elDir && cur.days === elDays) ? {} : { dir: elDir, days: elDays }
    } else if (elDir) {
      // direction-only: keep current days or pick first available
      const days = cur.days || this._firstActivityDays()
      this.activityValue = { dir: elDir, days }
    } else if (elDays) {
      // days-only: keep current direction or default to "newer"
      this.activityValue = { dir: cur.dir || "newer", days: elDays }
    }

    this.persist()
    this.syncActivityUI()
    this.apply()
  }

  _firstActivityDays() {
    const pill = this.activityPillTargets.find((p) => p.dataset.days)
    return pill ? parseInt(pill.dataset.days, 10) : 7
  }

  clearActivity() {
    this.activityValue = {}
    this.persist()
    this.syncActivityUI()
    this.apply()
  }

  // ---------- ghost epic filter ----------
  toggleGhostEpic() {
    this.ghostEpicValue = !this.ghostEpicValue
    this.persist()
    this.syncGhostEpicUI()
    this.apply()
  }

  startSync(event) {
    const el = event.currentTarget
    el.dataset.syncing = "1"
    const label = el.querySelector(".kb-sync-label")
    if (label) label.textContent = "syncing..."
  }

  _localizesyncTimestamp() {
    const el = document.getElementById("kb-sync-status")
    if (!el || !el.dataset.syncTs) return
    const local = new Date(el.dataset.syncTs).toLocaleString(undefined, {
      month: "short", day: "numeric", hour: "numeric", minute: "2-digit"
    })
    el.title = el.title.replace(el.dataset.syncTs, local)
  }

  syncGhostEpicUI() {
    if (this.hasGhostEpicBtnTarget) {
      this.ghostEpicBtnTarget.dataset.on = this.ghostEpicValue ? "1" : "0"
    }
  }

  syncActivityUI() {
    const act = this.activityValue || {}
    const on = !!(act.dir && act.days)
    this.activityPillTargets.forEach((el) => {
      const elDir = el.dataset.dir || null
      const elDays = el.dataset.days ? parseInt(el.dataset.days, 10) : null
      let match
      if (elDir && elDays) {
        match = on && elDir === act.dir && elDays === act.days
      } else if (elDir) {
        match = !!act.dir && elDir === act.dir
      } else if (elDays) {
        match = !!act.days && elDays === act.days
      } else {
        match = false
      }
      el.dataset.on = match ? "1" : "0"
    })
    if (this.hasActivityFilterBtnTarget) {
      const btn = this.activityFilterBtnTarget
      btn.dataset.on = on ? "1" : "0"
      const badge = btn.querySelector(".kb-filter-badge")
      if (badge) {
        if (on) {
          badge.textContent = `${act.dir === "newer" ? "≤" : "≥"}${act.days}d`
          badge.hidden = false
        } else {
          badge.hidden = true
        }
      }
    }
    if (this.hasActivityClearTarget) this.activityClearTarget.hidden = !on
  }

  syncStatusUI() {
    const sel = new Set(this.statusesValue)
    const anyOn = sel.size > 0
    this.statusPillTargets.forEach((el) => {
      const on = sel.has(el.dataset.state)
      const color = el.dataset.color
      el.dataset.on = on ? "1" : "0"
      el.dataset.muted = (anyOn && !on) ? "1" : "0"
      // legacy inline styles only for old .kb-pill elements (now unused)
      if (el.classList.contains("kb-pill")) {
        if (on) {
          el.style.background = color
          el.style.borderColor = color
          const dot = el.querySelector(".kb-pill-dot")
          if (dot) dot.style.background = "#fff"
        } else {
          el.style.background = ""
          el.style.borderColor = ""
          const dot = el.querySelector(".kb-pill-dot")
          if (dot) dot.style.background = color
        }
      }
    })
    this._syncStatusFilterBtn()
    if (this.hasStatusClearTarget) this.statusClearTarget.hidden = !anyOn
  }

  _syncStatusFilterBtn() {
    if (!this.hasStatusFilterBtnTarget) return
    const sel = new Set(this.statusesValue)
    const btn = this.statusFilterBtnTarget
    btn.dataset.on = sel.size > 0 ? "1" : "0"
    const dotsEl = btn.querySelector(".kb-filter-dots")
    if (dotsEl) {
      dotsEl.innerHTML = [...sel].map((id) => {
        const pill = this.statusPillTargets.find((p) => p.dataset.state === id)
        const color = pill?.dataset.color || "#94a3b8"
        return `<span class="kb-filter-dot-preview" style="background:${color};"></span>`
      }).join("")
    }
  }

  // ---------- people filter (called by people controller) ----------
  setAssignees(list) {
    this.assigneesValue = list
    this.persist()
    this.apply()
  }

  // ---------- core filter pass ----------
  apply() {
    const q = (this.queryValue || "").trim().toLowerCase()
    const sel = new Set(this.statusesValue)
    const pset = new Set(this.assigneesValue)
    const act = this.activityValue || {}
    const activityOn = !!(act.dir && act.days)
    const ghostEpicOn = this.ghostEpicValue
    const anyFilter = q.length > 0 || sel.size > 0 || pset.size > 0 || activityOn || ghostEpicOn

    const cards = this.element.querySelectorAll(".kb-card")
    cards.forEach((c) => {
      const search = c.dataset.search || ""
      const status = c.dataset.displayStatus || ""
      const assignee = c.dataset.assignee || ""
      const dsuRaw = c.dataset.daysSinceChange
      const dsu = dsuRaw === "" || dsuRaw == null ? null : parseInt(dsuRaw, 10)
      const matchQ = !q || search.includes(q)
      const matchS = sel.size === 0 || sel.has(status)
      const matchP = pset.size === 0 || pset.has(assignee)
      let matchA = true
      if (activityOn) {
        if (dsu == null || Number.isNaN(dsu)) matchA = false
        else if (act.dir === "newer") matchA = dsu <= act.days
        else matchA = dsu > act.days
      }
      const matchG = !ghostEpicOn || c.dataset.ghostEpic === "1"
      const match = matchQ && matchS && matchP && matchA && matchG
      if (anyFilter) {
        c.dataset.dim = match ? "0" : "1"
        c.dataset.spotlight = match ? "1" : "0"
      } else {
        c.dataset.dim = "0"
        c.dataset.spotlight = "0"
      }
    })

    const hasMatch = (root) => {
      const inner = root.querySelectorAll(".kb-card")
      if (inner.length === 0) return true
      for (const c of inner) if (c.dataset.dim !== "1") return true
      return false
    }

    this.element.querySelectorAll(".kb-stack-wrap").forEach((w) => {
      w.dataset.dim = (anyFilter && !hasMatch(w)) ? "1" : "0"
    })

    this.element.querySelectorAll(".kb-col").forEach((col) => {
      col.dataset.dim = (anyFilter && !hasMatch(col)) ? "1" : "0"
    })

    document.querySelectorAll("[data-controller~=stack]").forEach((el) => {
      if (el.stackController) el.stackController.refreshHits()
    })
  }

  // ---------- hover tooltip ----------
  showTooltip(event) {
    const card = event.currentTarget
    clearTimeout(this._ttTimer)
    clearTimeout(this._ttHideTimer)
    this._ttTimer = setTimeout(() => this._renderTooltip(card), 140)
  }

  hideTooltip() {
    clearTimeout(this._ttTimer)
    this._ttHideTimer = setTimeout(() => this._doHide(), 80)
  }

  _doHide() {
    if (this.hasTooltipTarget) this.tooltipTarget.hidden = true
    this._ttAnchor = null
  }

  _renderTooltip(card) {
    if (!this.hasTooltipTarget) return
    const ds = card.dataset
    const stateColor = ds.tooltipStateColor || "#94a3b8"
    const stale = ds.tooltipStale && ds.tooltipStale !== "fresh"
    const staleClass = stale ? ds.tooltipStale : null
    const staleColor = ds.tooltipStale === "critical" ? "#fca5a5"
                    : ds.tooltipStale === "stale" ? "#fdba74" : "#e8ecf2"
    const parentRow = ds.tooltipParent
      ? `<span class="lbl">Parent</span><span class="val">${this._esc(ds.tooltipParent)}</span>`
      : ""
    const labelsRow = ds.tooltipLabels
      ? `<span class="lbl">Labels</span><span class="val">${this._esc(ds.tooltipLabels)}</span>`
      : ""
    const componentsRow = ds.tooltipComponents
      ? `<span class="lbl">Components</span><span class="val">${this._esc(ds.tooltipComponents)}</span>`
      : ""
    let prs = []
    try { prs = JSON.parse(ds.tooltipPrs || "[]") } catch (_) {}
    const prsHtml = prs.length
      ? `<div class="kb-tt-prs">${prs.map(pr => `
          <a class="kb-tt-pr-link" href="${this._esc(pr.url)}" target="_blank" rel="noreferrer">
            <span class="kb-tt-pr-dot" style="background:${pr.merged ? "#8b5cf6" : pr.closed ? "#ef4444" : "#22c55e"}"></span>
            <span class="kb-tt-pr-title">${this._esc(pr.title || pr.url)}</span>
          </a>`).join("")}</div>`
      : ""
    this.tooltipTarget.innerHTML = `
      <div class="kb-tt-row">
        <span class="kb-tt-id">${ds.tooltipId || ""}</span>
        <span class="kb-tt-state-pill" style="background:${stateColor}">${ds.tooltipState || ""}</span>
      </div>
      <div class="kb-tt-title">${this._esc(ds.tooltipTitle || "")}</div>
      <div class="kb-tt-grid">
        <span class="lbl">Type</span><span class="val">${this._esc(ds.tooltipType || "—")}</span>
        ${parentRow}
        ${labelsRow}
        ${componentsRow}
        <span class="lbl">Assignee</span><span class="val">${this._esc(ds.tooltipAssignee || "Unassigned")}</span>
        <span class="lbl">In state</span><span class="val" style="color:${staleColor}">${ds.tooltipDays ? ds.tooltipDays + " days" : "—"}${stale ? " · " + staleClass : ""}</span>
        <span class="lbl">Priority</span><span class="val">${this._esc(ds.tooltipPriority || "Medium")}</span>
        <span class="lbl">Jira status</span><span class="val">${this._esc(ds.tooltipStatusRaw || "—")}</span>
      </div>
      ${prsHtml}
      <div class="kb-tt-hint">Click card to open in Jira ↗</div>
    `
    this._ttAnchor = card
    this.tooltipTarget.hidden = false
    this._positionTooltip()
  }

  _positionTooltip() {
    if (!this.hasTooltipTarget || !this._ttAnchor || this.tooltipTarget.hidden) return
    const tt = this.tooltipTarget
    const r = this._ttAnchor.getBoundingClientRect()
    const W = 270
    let left = r.right + 10
    if (left + W > window.innerWidth - 8) left = r.left - W - 10
    let top = r.top
    const ttH = tt.offsetHeight || 240
    top = Math.min(top, window.innerHeight - ttH - 8)
    top = Math.max(8, top)
    tt.style.left = left + "px"
    tt.style.top = top + "px"
    tt.style.width = W + "px"
  }

  _esc(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }

  // ---------- private helpers ----------
  _hydrate() {
    this.loadFromHash()
    this.syncStatusUI()
    this.syncActivityUI()
    this.syncGhostEpicUI()
    if (this.hasSearchTarget) this.searchTarget.value = this.queryValue
    this.apply()
  }

  // ---------- column drag-and-drop ----------
  _setupColumnDrag() {
    const root = this.rootTarget
    this._draggedCol = null
    this._dropTarget = null
    this._dropBefore = false

    this._onColDragStart = (e) => {
      const head = e.target.closest(".kb-col-head")
      if (!head) return
      const col = head.closest(".kb-col")
      if (!col) return
      this._draggedCol = col
      col.dataset.dragging = "1"
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", col.dataset.epicKey || "")
    }

    this._onColDragOver = (e) => {
      if (!this._draggedCol) return
      const col = e.target.closest(".kb-col")
      if (!col || col === this._draggedCol) return
      e.preventDefault()
      e.dataTransfer.dropEffect = "move"
      const rect = col.getBoundingClientRect()
      const before = e.clientX < rect.left + rect.width / 2
      if (this._dropTarget !== col || this._dropBefore !== before) {
        root.querySelectorAll(".kb-col[data-drop-side]").forEach(c => delete c.dataset.dropSide)
        col.dataset.dropSide = before ? "left" : "right"
        this._dropTarget = col
        this._dropBefore = before
      }
    }

    this._onColDrop = (e) => {
      e.preventDefault()
      root.querySelectorAll(".kb-col[data-drop-side]").forEach(c => delete c.dataset.dropSide)
      if (this._dropTarget && this._draggedCol) {
        if (this._dropBefore) {
          root.insertBefore(this._draggedCol, this._dropTarget)
        } else {
          this._dropTarget.after(this._draggedCol)
        }
        this._saveColOrder()
      }
      this._dropTarget = null
    }

    this._onColDragEnd = () => {
      if (this._draggedCol) {
        delete this._draggedCol.dataset.dragging
        this._draggedCol = null
      }
      root.querySelectorAll(".kb-col[data-drop-side]").forEach(c => delete c.dataset.dropSide)
      this._dropTarget = null
    }

    root.addEventListener("dragstart", this._onColDragStart)
    root.addEventListener("dragover", this._onColDragOver)
    root.addEventListener("drop", this._onColDrop)
    root.addEventListener("dragend", this._onColDragEnd)
  }

  _teardownColumnDrag() {
    if (!this.hasRootTarget) return
    const root = this.rootTarget
    root.removeEventListener("dragstart", this._onColDragStart)
    root.removeEventListener("dragover", this._onColDragOver)
    root.removeEventListener("drop", this._onColDrop)
    root.removeEventListener("dragend", this._onColDragEnd)
  }

  _saveColOrder() {
    const order = [...this.rootTarget.querySelectorAll(":scope > .kb-col")].map(c => c.dataset.epicKey)
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch("/column_order", {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ order })
    })
      .then(res => { if (!res.ok) console.error("Failed to save column order", res.status) })
      .catch(e => console.error("Failed to save column order", e))
  }

  // ---------- persistence ----------
  persist() {
    const state = {
      q: this.queryValue,
      s: this.statusesValue,
      a: this.assigneesValue,
      v: this.activityValue,
      g: this.ghostEpicValue
    }
    location.hash = encodeURIComponent(JSON.stringify(state))
  }

  loadFromHash() {
    if (!location.hash) return
    try {
      const state = JSON.parse(decodeURIComponent(location.hash.slice(1)))
      this.queryValue = state.q || ""
      this.statusesValue = state.s || []
      this.assigneesValue = state.a || []
      this.activityValue = state.v || {}
      this.ghostEpicValue = state.g || false
    } catch {}
  }
}
