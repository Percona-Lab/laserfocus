import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this._buffer = ""
    this._idleTimer = null
    this._onKey = (e) => this._handleKey(e)
    this._onClose = () => this._hide()
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
    this._clearOverlay()
  }

  _handleKey(e) {
    const tag = e.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || e.target.isContentEditable) return
    if (e.key === "Escape") { this._hide(); return }

    this._buffer += e.key.toLowerCase()
    if (this._buffer.length > 5) this._buffer = this._buffer.slice(-5)

    clearTimeout(this._idleTimer)
    this._idleTimer = setTimeout(() => { this._buffer = "" }, 2000)

    if (this._buffer.endsWith("shame")) {
      this._buffer = ""
      this._show()
    }
  }

  _show() {
    if (document.getElementById("shame-overlay")) return

    const overlay = document.createElement("div")
    overlay.id = "shame-overlay"
    overlay.style.cssText = [
      "position:fixed", "inset:0", "z-index:9999",
      "background:rgba(0,0,0,0.85)",
      "display:flex", "flex-direction:column",
      "align-items:center", "justify-content:center",
      "cursor:pointer"
    ].join(";")

    const img = document.createElement("img")
    img.src = "/images/shame.gif"
    img.alt = "Shame! Shame! Shame!"
    img.style.cssText = "max-height:70vh;max-width:90vw;border-radius:8px;box-shadow:0 0 60px rgba(0,0,0,0.8)"

    const label = document.createElement("p")
    label.textContent = "SHAME! SHAME! SHAME!"
    label.style.cssText = [
      "margin-top:24px", "color:#dc2626",
      "font-size:2.5rem", "font-weight:800",
      "font-family:'Hanken Grotesk',sans-serif",
      "letter-spacing:0.15em", "text-shadow:0 0 20px rgba(220,38,38,0.7)"
    ].join(";")

    overlay.appendChild(img)
    overlay.appendChild(label)
    overlay.addEventListener("click", this._onClose)
    document.body.appendChild(overlay)

    requestAnimationFrame(() => { overlay.style.opacity = "0"; overlay.style.transition = "opacity 0.2s" })
    requestAnimationFrame(() => requestAnimationFrame(() => { overlay.style.opacity = "1" }))
  }

  _hide() {
    const overlay = document.getElementById("shame-overlay")
    if (!overlay) return
    overlay.style.opacity = "0"
    setTimeout(() => overlay.remove(), 200)
  }

  _clearOverlay() {
    const overlay = document.getElementById("shame-overlay")
    if (overlay) overlay.remove()
  }
}
