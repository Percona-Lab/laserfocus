import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (localStorage.getItem("kb-density") === "compact") {
      document.documentElement.dataset.density = "compact"
    }
  }

  toggle() {
    const compact = document.documentElement.dataset.density === "compact"
    if (compact) {
      delete document.documentElement.dataset.density
      localStorage.setItem("kb-density", "normal")
    } else {
      document.documentElement.dataset.density = "compact"
      localStorage.setItem("kb-density", "compact")
    }
  }
}
