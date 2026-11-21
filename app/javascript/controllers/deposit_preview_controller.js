import { Controller } from "@hotwired/stimulus"

// Nhận sheet (#284): the guest's message follows the room and Cọc picked. Amounts come from the server per room.
export default class extends Controller {
  static targets = ["amount", "deposit", "none"]

  connect() {
    this.update()
  }

  update() {
    const room = this.element.querySelector("[name=room_id]:checked")
    const percent = this.element.querySelector("[name=deposit_percent]:checked")?.value
    const amount = room && JSON.parse(room.dataset.deposits)[percent]
    this.amountTarget.textContent = amount || ""
    this.depositTarget.hidden = !amount
    this.noneTarget.hidden = !!amount
  }
}
