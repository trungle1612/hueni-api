import { Controller } from "@hotwired/stimulus"

// Gửi link (#245): the phone's share sheet (Zalo is in it) where there is one, and Sao chép link.
export default class extends Controller {
  static targets = ["source", "share", "copy"]

  connect() {
    if (!navigator.share) this.shareTarget.hidden = true
  }

  share() {
    navigator.share({ text: this.sourceTarget.value }).catch(() => {})
  }

  copy() {
    navigator.clipboard.writeText(this.sourceTarget.value).then(
      () => { this.copyTarget.textContent = "Đã sao chép link" },
      () => { this.sourceTarget.select() }
    )
  }
}
