import { Controller } from "@hotwired/stimulus"

// Ảnh phòng (#187): a thumbnail opens the full-screen popover at that photo; swipe (CSS scroll-snap), arrows or ← → move.
export default class extends Controller {
  static targets = ["track", "slide"]

  show({ params: { index } }) {
    this.index = index
  }

  opened(event) {
    if (event.newState === "open") this.slideTargets[this.index ?? 0]?.scrollIntoView({ behavior: "instant", block: "nearest", inline: "start" })
  }

  next() { this.trackTarget.scrollBy({ left: this.trackTarget.clientWidth }) }

  prev() { this.trackTarget.scrollBy({ left: -this.trackTarget.clientWidth }) }
}
