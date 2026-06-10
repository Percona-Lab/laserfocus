import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const saved = localStorage.getItem("korkban-theme")
    if (saved) document.documentElement.dataset.theme = saved
  }

  toggle() {
    const cur = document.documentElement.dataset.theme === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = cur
    localStorage.setItem("korkban-theme", cur)
  }
}
