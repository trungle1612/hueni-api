import { Controller } from "@hotwired/stimulus"

// Sao chép (#292): copies the source's visible text, e.g. the Nhận sheet's message to paste into Zalo.
export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    navigator.clipboard.writeText(this.sourceTarget.innerText.trim()).then(
      () => { this.buttonTarget.textContent = "Đã sao chép" },
      () => {}
    )
  }
}
