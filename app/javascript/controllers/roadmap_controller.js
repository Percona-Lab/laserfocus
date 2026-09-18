import { Controller } from "@hotwired/stimulus"

// Expands the roadmap line's findings. Closed by default: the line is meant to
// be readable at a glance and only unfold when somebody asks.
export default class extends Controller {
  static targets = ["btn", "body"]

  toggle() {
    if (!this.hasBodyTarget) return
    const open = this.bodyTarget.hidden
    this.bodyTarget.hidden = !open
    this.btnTarget.dataset.open = open ? "1" : "0"
    this.btnTarget.setAttribute("aria-expanded", open ? "true" : "false")
  }
}
