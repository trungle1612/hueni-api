import { Controller } from "@hotwired/stimulus"

// Đặt phòng mới (#232). Reloads the free rooms and the total (#quote) from the whole form as it changes, looks up
// Khách cũ by phone (#returning), and asks before throwing away what was typed. Rules stay on the server: this only
// sends the form. Moving check-in onto or past check-out moves check-out to the next day, as on /admin.
export default class extends Controller {
  static targets = ["form", "start", "end", "quote", "returning", "name", "discard"]
  static values = { roomsUrl: String, guestUrl: String }

  refresh() {
    if (this.startTarget.value && this.endTarget.value <= this.startTarget.value) {
      const next = new Date(`${this.startTarget.value}T00:00:00Z`)
      next.setUTCDate(next.getUTCDate() + 1)
      this.endTarget.value = next.toISOString().slice(0, 10)
    }
    this.load(this.quoteTarget, this.roomsUrlValue)
  }

  lookup() {
    this.load(this.returningTarget, this.guestUrlValue)
  }

  useName({ params: { name } }) {
    this.nameTarget.value = name
    this.returningTarget.replaceChildren()
  }

  edited() {
    this.dirty = true
  }

  close(event) {
    if (!this.dirty) return
    event.preventDefault()
    this.discardTarget.showPopover()
  }

  load(frame, url) {
    const params = new URLSearchParams(new FormData(this.formTarget))
    params.delete("authenticity_token")
    clearTimeout(frame.timer)
    frame.timer = setTimeout(() => { frame.src = `${url}?${params}` }, 250)
  }
}
