import { Controller } from "@hotwired/stimulus"

// Keeps only the select's options that match what is typed (no diacritics, any case). The blank and the
// chosen option always stay. Rebuilds the list: iOS Safari ignores `hidden` on options.
export default class extends Controller {
  static targets = ["input", "select"]

  connect() {
    this.options = [...this.selectTarget.options]
  }

  filter() {
    const query = fold(this.inputTarget.value)
    const chosen = this.selectTarget.value
    this.selectTarget.replaceChildren(...this.options.filter((option) =>
      option.value === "" || option.value === chosen || fold(option.text).includes(query)))
    this.selectTarget.value = chosen
  }
}

const fold = (text) => text.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/gi, "d").toLowerCase().trim()
