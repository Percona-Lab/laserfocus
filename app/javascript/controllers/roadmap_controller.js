import { Controller } from "@hotwired/stimulus"

// Expands the roadmap line's findings. Closed by default: the line is meant to
// be readable at a glance and only unfold when somebody asks. A board refresh
// morphs the server's markup back in with the panel closed, so the reader's
// choice is kept here and re-applied once the morph settles.
export default class extends Controller {
  static targets = ["btn", "body"]

  connect() {
    this._open = this.hasBodyTarget && !this.bodyTarget.hidden
    this._onMorph = () => this.apply()
    document.addEventListener("turbo:morph", this._onMorph)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this._onMorph)
  }

  toggle() {
    if (!this.hasBodyTarget) return
    this._open = !this._open
    this.apply()
  }

  apply() {
    if (!this.hasBodyTarget) return
    this.bodyTarget.hidden = !this._open
    this.btnTarget.dataset.open = this._open ? "1" : "0"
    this.btnTarget.setAttribute("aria-expanded", this._open ? "true" : "false")
  }
}
