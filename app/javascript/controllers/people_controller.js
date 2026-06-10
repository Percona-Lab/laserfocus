import { Controller } from "@hotwired/stimulus"

// Dropdown people-filter. Pushes the selected set up to the nearest board
// controller. Closes when clicking outside.
export default class extends Controller {
  static targets = ["btn", "menu", "row", "label", "clear"]
  static values = { selected: Array }

  connect() {
    this._board = this._findBoard()
    this.syncUI()
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.hidden = !this.menuTarget.hidden
  }

  closeIfOutside(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.hidden = true
    }
  }

  toggleRow(event) {
    event.stopPropagation()
    const row = event.currentTarget
    const name = row.dataset.name
    const set = new Set(this.selectedValue)
    set.has(name) ? set.delete(name) : set.add(name)
    this.selectedValue = [...set]
    this.syncUI()
    this._push()
  }

  clear(event) {
    event.stopPropagation()
    this.selectedValue = []
    this.syncUI()
    this._push()
  }

  syncUI() {
    const sel = new Set(this.selectedValue)
    this.rowTargets.forEach((row) => {
      const on = sel.has(row.dataset.name)
      row.dataset.on = on ? "1" : "0"
      const chk = row.querySelector(".check")
      if (chk) chk.hidden = !on
    })
    if (this.hasBtnTarget) this.btnTarget.dataset.on = sel.size > 0 ? "1" : "0"
    if (this.hasLabelTarget) this.labelTarget.textContent = sel.size === 0
      ? "People"
      : `${sel.size} selected`
    if (this.hasClearTarget) this.clearTarget.hidden = sel.size === 0
  }

  _findBoard() {
    let el = this.element
    while (el) {
      if (el.dataset && (el.dataset.controller || "").includes("board")) {
        return this.application.getControllerForElementAndIdentifier(el, "board")
      }
      el = el.parentElement
    }
    return null
  }

  _push() {
    if (!this._board) this._board = this._findBoard()
    if (this._board) this._board.setAssignees(this.selectedValue)
  }
}
