import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.menuTarget.hidden = false
  }

  close() {
    this.menuTarget.hidden = true
  }

  closeIfOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
