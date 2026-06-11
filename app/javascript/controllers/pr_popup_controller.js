import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { prs: Array }

  open(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.prsValue.length === 0) return

    if (this.prsValue.length === 1) {
      window.open(this.prsValue[0].url, "_blank", "noreferrer")
      return
    }

    // Toggle popup for multiple PRs
    if (this._popup) {
      this._removePopup()
    } else {
      this._showPopup()
    }
  }

  _showPopup() {
    const popup = document.createElement("div")
    popup.className = "kb-pr-popup"

    this.prsValue.forEach(pr => {
      const a = document.createElement("a")
      a.href = pr.url
      a.target = "_blank"
      a.rel = "noreferrer"
      a.className = "kb-pr-row"

      const dot = document.createElement("span")
      dot.className = "kb-pr-dot"
      dot.style.background = pr.merged ? "#22c55e" : "#8b5cf6"

      const title = document.createElement("span")
      title.className = "kb-pr-row-title"
      title.textContent = pr.title || pr.url

      a.appendChild(dot)
      a.appendChild(title)
      popup.appendChild(a)
    })

    document.body.appendChild(popup)
    this._popup = popup

    // Position below the button, keep within viewport
    const rect = this.element.getBoundingClientRect()
    const popupW = 260
    let left = rect.left
    if (left + popupW > window.innerWidth - 8) left = window.innerWidth - popupW - 8
    popup.style.left = `${Math.max(4, left)}px`
    popup.style.top = `${rect.bottom + 4}px`

    // Close on outside click (defer one tick so this click doesn't immediately close it)
    this._docClick = (e) => {
      if (!popup.contains(e.target)) this._removePopup()
    }
    setTimeout(() => document.addEventListener("click", this._docClick), 0)
  }

  _removePopup() {
    this._popup?.remove()
    this._popup = null
    if (this._docClick) {
      document.removeEventListener("click", this._docClick)
      this._docClick = null
    }
  }

  disconnect() {
    this._removePopup()
  }
}
