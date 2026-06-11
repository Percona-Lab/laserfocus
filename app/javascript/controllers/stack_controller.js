import { Controller } from "@hotwired/stimulus"

// Manages per-column expand/collapse for To Do, Done, and all middle status groups.
// Also reports hidden filter matches up to the board controller for the
// "n matches" highlight on the stack button.
export default class extends Controller {
  static targets = [
    "todoBtn", "todoBody", "todoTrail", "todoShadow", "todoWrap", "middleDivider",
    "doneBtn", "doneBody", "doneTrail", "doneShadow", "doneWrap",
    "middleBtn", "middleBody", "middleShadow", "middleTrail", "collapseAllBtn"
  ]
  static values = {
    todoOpen: Boolean,
    doneOpen: Boolean,
    middleOpen: Object
  }

  connect() {
    this.element.stackController = this
    this._intendedTodoOpen = this.todoOpenValue
    this._intendedDoneOpen = this.doneOpenValue
    const initialMiddle = {}
    this.middleBtnTargets.forEach(btn => { initialMiddle[btn.dataset.status] = true })
    this.middleOpenValue = initialMiddle
    this._intendedMiddleOpen = { ...initialMiddle }
    this.applyTodo()
    this.applyDone()
    this.applyMiddle()
    this._onMorph = this._onMorph.bind(this)
    this.element.addEventListener("turbo:morph-element", this._onMorph)
  }

  disconnect() {
    this.element.removeEventListener("turbo:morph-element", this._onMorph)
  }

  toggleTodo() {
    this.todoOpenValue = !this.todoOpenValue
    this._intendedTodoOpen = this.todoOpenValue
    this.applyTodo()
  }

  toggleDone() {
    this.doneOpenValue = !this.doneOpenValue
    this._intendedDoneOpen = this.doneOpenValue
    this.applyDone()
  }

  toggleMiddle(event) {
    const status = event.currentTarget.dataset.status
    const current = { ...this.middleOpenValue }
    current[status] = !current[status]
    this.middleOpenValue = current
    this._intendedMiddleOpen = { ...current }
    this.applyMiddle()
  }

  toggleAll() {
    const newState = !this._isAnyOpen()
    if (this.hasTodoBtnTarget) { this.todoOpenValue = newState; this._intendedTodoOpen = newState }
    if (this.hasDoneBtnTarget) { this.doneOpenValue = newState; this._intendedDoneOpen = newState }
    const middle = {}
    this.middleBtnTargets.forEach(btn => { middle[btn.dataset.status] = newState })
    this.middleOpenValue = middle
    this._intendedMiddleOpen = { ...middle }
    this.applyTodo()
    this.applyDone()
    this.applyMiddle()
  }

  _onMorph(event) {
    if (event.target !== this.element) return
    this.todoOpenValue = this._intendedTodoOpen
    this.doneOpenValue = this._intendedDoneOpen
    // Restore middle state; default-open any new groups that appeared after morph
    const restored = { ...this._intendedMiddleOpen }
    this.middleBtnTargets.forEach(btn => {
      if (!(btn.dataset.status in restored)) restored[btn.dataset.status] = true
    })
    this.middleOpenValue = { ...restored }
    this._intendedMiddleOpen = { ...restored }
    this.applyTodo()
    this.applyDone()
    this.applyMiddle()
  }

  applyTodo() {
    if (!this.hasTodoBtnTarget) return
    const open = this.todoOpenValue
    this.todoBtnTarget.dataset.open = open ? "1" : "0"
    this.todoBodyTarget.hidden = !open
    if (this.hasTodoShadowTarget) this.todoShadowTarget.hidden = open
    if (this.hasMiddleDividerTarget) this.middleDividerTarget.hidden = !open
    this.refreshHits()
    this._updateCollapseAllBtn()
  }

  applyDone() {
    if (!this.hasDoneBtnTarget) return
    const open = this.doneOpenValue
    this.doneBtnTarget.dataset.open = open ? "1" : "0"
    this.doneBodyTarget.hidden = !open
    if (this.hasDoneShadowTarget) this.doneShadowTarget.hidden = open
    this.refreshHits()
    this._updateCollapseAllBtn()
  }

  applyMiddle() {
    this.middleBtnTargets.forEach(btn => {
      const status = btn.dataset.status
      const open = this.middleOpenValue[status] !== false
      btn.dataset.open = open ? "1" : "0"
      const body = this.middleBodyTargets.find(b => b.dataset.status === status)
      if (body) body.hidden = !open
      const shadow = this.middleShadowTargets.find(s => s.dataset.status === status)
      if (shadow) shadow.hidden = open
      const trail = this.middleTrailTargets.find(t => t.dataset.status === status)
      if (trail) trail.textContent = open ? "hide" : "show"
    })
    this._updateCollapseAllBtn()
  }

  _isAnyOpen() {
    if (this.hasTodoBtnTarget && this.todoOpenValue) return true
    if (this.hasDoneBtnTarget && this.doneOpenValue) return true
    return this.middleBtnTargets.some(btn => this.middleOpenValue[btn.dataset.status] !== false)
  }

  _updateCollapseAllBtn() {
    if (!this.hasCollapseAllBtnTarget) return
    const anyOpen = this._isAnyOpen()
    this.collapseAllBtnTarget.dataset.open = anyOpen ? "1" : "0"
    this.collapseAllBtnTarget.title = anyOpen ? "Collapse all sections" : "Expand all sections"
  }

  refreshHits() {
    if (this.hasTodoBtnTarget && this.hasTodoBodyTarget) {
      const hits = this._countHits(this.todoBodyTarget)
      this._renderHits(this.todoBtnTarget, this.todoTrailTarget, this.todoOpenValue, hits, this.todoBodyTarget)
    }
    if (this.hasDoneBtnTarget && this.hasDoneBodyTarget) {
      const hits = this._countHits(this.doneBodyTarget)
      this._renderHits(this.doneBtnTarget, this.doneTrailTarget, this.doneOpenValue, hits, this.doneBodyTarget)
    }
  }

  _countHits(body) {
    let n = 0
    body.querySelectorAll(".kb-card").forEach((c) => {
      if (c.dataset.dim !== "1") {
        const isMatch = c.dataset.spotlight === "1"
        if (isMatch) n++
      }
    })
    return n
  }

  _renderHits(btn, trail, open, hits, body) {
    const old = btn.querySelector(".kb-stack-hits")
    if (old) old.remove()
    if (!trail) return
    if (!open && hits > 0) {
      trail.hidden = true
      btn.dataset.flag = "1"
      const chip = document.createElement("span")
      chip.className = "kb-stack-hits"
      chip.innerHTML = `
        <svg width="9" height="9" viewBox="0 0 11 11" fill="none" stroke="#fff" stroke-width="1.8">
          <circle cx="4.5" cy="4.5" r="3"/><path d="M7 7l2.5 2.5" stroke-linecap="round"/>
        </svg>${hits} match${hits === 1 ? "" : "es"}`
      btn.appendChild(chip)
    } else {
      trail.hidden = false
      btn.dataset.flag = "0"
      trail.textContent = open ? "hide" : "show"
    }
  }
}
