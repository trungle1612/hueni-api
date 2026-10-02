import { Controller } from "@hotwired/stimulus"

// Submits the surrounding form as soon as an input changes (room on/off switch).
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
