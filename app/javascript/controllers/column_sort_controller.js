import { Controller } from "@hotwired/stimulus"

// Per-browser column order: the shared drag order, or by landing quarter.
// Writes the cookie, then lets the server re-render the board (morph refresh),
// like the grouping pills.
export default class extends Controller {
  choose(event) {
    const sort = event.currentTarget.dataset.sort
    document.cookie = `board_column_sort=${sort}; path=/; max-age=31536000; samesite=lax`
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
