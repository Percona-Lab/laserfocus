import { Controller } from "@hotwired/stimulus"

// Manages the per-column expand/collapse for the To Do and Done stacks.
// Also reports hidden filter matches up to the board controller for the
// "n matches" highlight on the stack button.
export default class extends Controller {
  static targets = [
    "todoBtn", "todoBody", "todoTrail", "todoShadow", "todoWrap", "middleDivider",
    "doneBtn", "doneBody", "doneTrail", "doneShadow", "doneWrap"
  ]
  static values = {
    todoOpen: Boolean,
    doneOpen: Boolean
  }

  connect() {
    // expose self so the board controller can ask us to refresh hit counts
    this.element.stackController = this
    // The board auto-refreshes via turbo-stream morph; the server re-renders
    // the column with the default open=false attributes, which would otherwise
    // collapse the user's expanded sections. Track intent here and restore
    // after each morph of this section.
    this._intendedTodoOpen = this.todoOpenValue
    this._intendedDoneOpen = this.doneOpenValue
    this.applyTodo()
    this.applyDone()
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

  _onMorph(event) {
    if (event.target !== this.element) return
    this.todoOpenValue = this._intendedTodoOpen
    this.doneOpenValue = this._intendedDoneOpen
    this.applyTodo()
    this.applyDone()
  }

  applyTodo() {
    if (!this.hasTodoBtnTarget) return
    const open = this.todoOpenValue
    this.todoBtnTarget.dataset.open = open ? "1" : "0"
    this.todoBodyTarget.hidden = !open
    if (this.hasTodoShadowTarget) this.todoShadowTarget.hidden = open
    if (this.hasMiddleDividerTarget) this.middleDividerTarget.hidden = !open
    this.refreshHits()
  }

  applyDone() {
    if (!this.hasDoneBtnTarget) return
    const open = this.doneOpenValue
    this.doneBtnTarget.dataset.open = open ? "1" : "0"
    this.doneBodyTarget.hidden = !open
    if (this.hasDoneShadowTarget) this.doneShadowTarget.hidden = open
    this.refreshHits()
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
    // remove old hits chip
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
