import { Controller } from "@hotwired/stimulus"

// Sao chép (#292): copies the source's visible text, e.g. the Nhận sheet's message to paste into Zalo.
export default class extends Controller {
  static targets = ["source", "button"]

  // No navigator.clipboard in Zalo's webview or over plain http.
  copy() {
    const failed = () => { this.buttonTarget.textContent = "Không sao chép được" }
    if (!navigator.clipboard) return failed()
    navigator.clipboard.writeText(this.sourceTarget.innerText.trim()).then(
      () => { this.buttonTarget.textContent = "Đã sao chép" },
      failed
    )
  }
}
