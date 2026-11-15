import { Controller } from "@hotwired/stimulus"

// A bottom sheet that opens with the page (#245): a form the server refused, the link after Mời nhân viên.
export default class extends Controller {
  connect() {
    this.element.showPopover?.()
  }
}
