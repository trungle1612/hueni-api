import { Controller } from "@hotwired/stimulus"

// Còn N phút on a request waiting for an answer (#284). Counted from the seconds the server had left, not the phone's
// clock; at zero the page reloads so the request moves to Hết hạn.
export default class extends Controller {
  static values = { seconds: Number }

  connect() {
    this.deadline = Date.now() + this.secondsValue * 1000
    this.timer = setInterval(() => this.tick(), 15000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const left = Math.ceil((this.deadline - Date.now()) / 60000)
    if (left <= 0) return Turbo.visit(location.href, { action: "replace" })
    this.element.textContent = `Còn ${left} phút`
    this.element.classList.toggle("pms-badge-warn", left <= 10)
    this.element.classList.toggle("pms-badge-out", left > 10)
  }
}
