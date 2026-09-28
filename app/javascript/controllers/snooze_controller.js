import { Controller } from "@hotwired/stimulus"

// Right-click menu on stale cards: snooze the staleness highlight for a few
// days, or see and lift an existing snooze. The server broadcasts a board
// refresh after each change, so this controller never redraws cards itself.
export default class extends Controller {
  static targets = [
    "menu", "snoozePane", "infoPane", "snoozeSub", "snoozeNote", "reason",
    "submit", "submitLabel", "infoTitle", "infoSub", "infoReason", "infoNote", "error"
  ]
  static values = { days: { type: Number, default: 7 } }

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    this._onPointer = (e) => {
      if (!this.hasMenuTarget || this.menuTarget.hidden) return
      if (!this.menuTarget.contains(e.target)) this.close()
    }
    // The menu is fixed to where the click was, so anything that moves the
    // cards under it closes it.
    this._onMove = (e) => {
      if (e.type === "scroll" && this.hasMenuTarget && this.menuTarget.contains(e.target)) return
      this.close()
    }
    document.addEventListener("keydown", this._onKey)
    document.addEventListener("mousedown", this._onPointer)
    document.addEventListener("scroll", this._onMove, true)
    window.addEventListener("resize", this._onMove)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
    document.removeEventListener("mousedown", this._onPointer)
    document.removeEventListener("scroll", this._onMove, true)
    window.removeEventListener("resize", this._onMove)
  }

  open(event) {
    const card = event.currentTarget
    const ds = card.dataset
    if (!ds.snoozeKey) return
    event.preventDefault()
    this._key = ds.snoozeKey
    this._hideTooltip()
    this._clearError()

    const snoozed = ds.staleness === "snoozed"
    this.snoozePaneTarget.hidden = snoozed
    this.infoPaneTarget.hidden = !snoozed

    if (snoozed) {
      const left = Number(ds.snoozeDaysLeft)
      this.infoTitleTarget.textContent = `Snoozed until ${ds.snoozedUntil}`
      this.infoSubTarget.textContent = `by ${ds.snoozedBy} · ${left === 1 ? "1 day" : `${left} days`} left`
      this.infoReasonTarget.textContent = ds.snoozeReason || ""
      this.infoReasonTarget.hidden = !ds.snoozeReason
      this.infoNoteTarget.textContent =
        `${ds.daysSinceChange} days in ${ds.snoozeState}. The highlight comes back when the snooze runs out. ` +
        "If the ticket moves, it starts fresh in its new status."
    } else {
      this.snoozeSubTarget.textContent = `${ds.snoozeKey} has been in ${ds.snoozeState} for ${ds.daysSinceChange} days.`
      this.snoozeNoteTarget.textContent = `Shown as fresh until ${this._untilLabel()}, or until the ticket changes status.`
      this.submitLabelTarget.textContent = `Snooze ${this.daysValue} ${this.daysValue === 1 ? "day" : "days"}`
      this.reasonTarget.value = ""
      this.submitTarget.disabled = false
    }

    this.menuTarget.hidden = false
    this._place(event.clientX, event.clientY)
    if (!snoozed) this.reasonTarget.focus()
  }

  close() {
    if (this.hasMenuTarget) this.menuTarget.hidden = true
    this._key = null
  }

  submit(event) {
    event.preventDefault()
    if (!this._key) return
    this.submitTarget.disabled = true
    this._send("PATCH", { key: this._key, reason: this.reasonTarget.value.trim() })
      .catch(() => { this.submitTarget.disabled = false })
  }

  unsnooze() {
    if (!this._key) return
    this._send("DELETE", { key: this._key }).catch(() => {})
  }

  _send(method, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    return fetch("/stale_snooze", {
      method,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify(body)
    }).then((res) => {
      if (!res.ok) throw new Error(`${res.status}`)
      this.close()
    }).catch((e) => {
      console.error("Failed to save snooze", e)
      this._showError("Could not save the snooze. Try again.")
      throw e
    })
  }

  _untilLabel() {
    const d = new Date()
    d.setDate(d.getDate() + this.daysValue)
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric" })
  }

  _place(x, y) {
    const menu = this.menuTarget
    const w = menu.offsetWidth
    const h = menu.offsetHeight
    menu.style.left = `${Math.max(8, Math.min(x, window.innerWidth - w - 8))}px`
    menu.style.top = `${Math.max(8, Math.min(y, window.innerHeight - h - 8))}px`
  }

  _hideTooltip() {
    const tt = this.element.querySelector("[data-board-target='tooltip']")
    if (tt) tt.hidden = true
  }

  _showError(text) {
    this.errorTargets.forEach((el) => { el.textContent = text; el.hidden = false })
  }

  _clearError() {
    this.errorTargets.forEach((el) => { el.textContent = ""; el.hidden = true })
  }
}
