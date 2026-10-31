import { Controller } from "@hotwired/stimulus"

// Keeps the select's options that best match what is typed, forgiving typos: a typed word matches when its
// letters appear in order in the name ("hose" → "House"), no diacritics, any case; only the options matching
// the most words stay. The blank and the chosen option always stay. Rebuilds the list: iOS Safari ignores
// `hidden` on options.
export default class extends Controller {
  static targets = ["input", "select"]

  connect() {
    this.options = [...this.selectTarget.options]
    this.filter()
  }

  filter() {
    const words = fold(this.inputTarget.value).split(/\s+/).filter(Boolean)
    const chosen = this.selectTarget.value
    const scores = new Map(this.options.map((option) => [option, words.filter((word) => inOrder(word, fold(option.text))).length]))
    const best = Math.max(0, ...scores.values())
    this.selectTarget.replaceChildren(...this.options.filter((option) =>
      option.value === "" || option.value === chosen || !words.length || (best > 0 && scores.get(option) === best)))
    this.selectTarget.value = chosen
  }
}

const fold = (text) => text.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/gi, "d").toLowerCase().trim()

const inOrder = (word, text) => {
  let i = 0
  for (const char of text) if (char === word[i]) i++
  return i === word.length
}
