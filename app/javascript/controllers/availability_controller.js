import { Controller } from "@hotwired/stimulus"

// Re-checks room and dates as they change: reloads the #availability frame and the room's guest limit. Moving check-in onto or past
// check-out moves check-out to the next day, so the form never sits on a zero-night stay.
export default class extends Controller {
  static targets = ["frame", "start", "end", "guests", "max"]
  static values = { url: String }

  check() {
    if (this.startTarget.value && this.endTarget.value <= this.startTarget.value) {
      const next = new Date(`${this.startTarget.value}T00:00:00Z`)
      next.setUTCDate(next.getUTCDate() + 1)
      this.endTarget.value = next.toISOString().slice(0, 10)
    }
    const url = new URL(this.urlValue, location.href)
    url.searchParams.set("start_date", this.startTarget.value)
    url.searchParams.set("end_date", this.endTarget.value)
    const room = this.element.elements["booking[room_id]"]
    if (room) url.searchParams.set("room_id", room.value)
    const max = room?.selectedOptions?.[0]?.dataset.maxGuests
    if (max && this.hasMaxTarget) {
      this.maxTarget.textContent = max
      this.guestsTarget.max = max
    }
    this.frameTarget.src = url.toString()
  }
}
