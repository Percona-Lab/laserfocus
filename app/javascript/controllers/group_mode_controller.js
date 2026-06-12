import { Controller } from "@hotwired/stimulus"

// Per-browser column grouping mode. Writes the cookie, then lets the server
// re-render the board via a same-page Turbo visit (morph refresh).
export default class extends Controller {
  choose(event) {
    const mode = event.currentTarget.dataset.mode
    document.cookie = `board_group_mode=${mode}; path=/; max-age=31536000; samesite=lax`
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
