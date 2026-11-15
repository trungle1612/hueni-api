import { Controller } from "@hotwired/stimulus"

// A VND field (#233): 500000 shows as 500.000 while typing, the caret kept after the same digit. Shorthand with a
// letter ("300k") is left as typed; the server (VndPrice) parses both.
export default class extends Controller {
  format() {
    const input = this.element
    if (/[^\d.\s]/.test(input.value)) return
    const digitsBefore = input.value.slice(0, input.selectionStart).replace(/\D/g, "").length
    const digits = input.value.replace(/\D/g, "").replace(/^0+(?=\d)/, "")
    input.value = digits.replace(/\B(?=(\d{3})+(?!\d))/g, ".")
    let caret = 0
    for (let seen = 0; caret < input.value.length && seen < digitsBefore; caret++) if (/\d/.test(input.value[caret])) seen++
    input.setSelectionRange(caret, caret)
  }
}
