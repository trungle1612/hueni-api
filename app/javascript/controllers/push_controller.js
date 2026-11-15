import { Controller } from "@hotwired/stimulus"

// Thông báo trên điện thoại này (#237): Web Push, asked for only after a tap on the switch in Cài đặt thông báo.
// On every page it hands an existing subscription to the server again, so a new login on this phone takes it over.
// iPhone: push works only once hueni is added to the Home Screen and opened from there.
export default class extends Controller {
  static targets = ["toggle", "status"]
  static values = { key: String, url: String }

  async connect() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) return this.unsupported()
    this.registration = await navigator.serviceWorker.ready
    const subscription = await this.registration.pushManager.getSubscription()
    if (subscription && Notification.permission === "granted") this.send("POST", subscription)
    this.show(!!subscription)
  }

  async toggle() {
    this.toggleTarget.disabled = true
    const current = await this.registration.pushManager.getSubscription()
    if (current) {
      await this.send("DELETE", current)
      await current.unsubscribe()
      return this.show(false)
    }
    if ((await Notification.requestPermission()) !== "granted") return this.show(false)
    try {
      const subscription = await this.registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: this.applicationServerKey })
      this.show((await this.send("POST", subscription)).ok)
    } catch {
      this.show(false, "Không bật được. Thử lại sau.")
    }
  }

  show(on, message) {
    if (!this.hasToggleTarget) return
    const blocked = Notification.permission === "denied"
    this.toggleTarget.disabled = blocked
    this.toggleTarget.setAttribute("aria-checked", on)
    this.statusTarget.textContent = message || (blocked ? "Bạn đã chặn thông báo. Mở cài đặt của trình duyệt để cho phép hueni."
      : on ? "Đang bật: báo ngay cả khi không mở ứng dụng." : "Đang tắt: chỉ xem trong mục này.")
  }

  unsupported() {
    if (!this.hasToggleTarget) return
    const ios = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
    this.statusTarget.textContent = ios
      ? "Trên iPhone: bấm Chia sẻ, chọn Thêm vào MH chính, rồi mở hueni từ biểu tượng đó để bật thông báo."
      : "Trình duyệt này không nhận được thông báo. Dùng Chrome hoặc cài hueni lên màn hình chính."
  }

  send(method, subscription) {
    return fetch(this.urlValue, {
      method,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body: JSON.stringify(subscription)
    })
  }

  get applicationServerKey() {
    const raw = atob(this.keyValue.replace(/-/g, "+").replace(/_/g, "/"))
    return Uint8Array.from(raw, (c) => c.charCodeAt(0))
  }
}
