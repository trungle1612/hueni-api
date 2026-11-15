import { Controller } from "@hotwired/stimulus"

// Bắt đầu (#266, board Onboarding.dc.html): one step at a time. Inside a step, [data-when] shows what fits this browser:
// install = ios | prompt (Chrome can install) | manual | installed; notif = ask | granted | denied | unsupported.
// Already opened from the Home Screen: no install step.
export default class extends Controller {
  static targets = ["step", "bar", "kicker", "progress"]
  static values = { done: String }

  connect() {
    if (matchMedia("(display-mode: standalone)").matches || navigator.standalone) this.drop("install")
    const ios = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
    this.set("install", ios ? "ios" : window.installPrompt ? "prompt" : "manual")
    this.set("notif", { granted: "granted", denied: "denied" }[window.Notification?.permission] || "ask")
    if (!this.hasStepTarget) return Turbo.visit(this.doneValue)
    this.index = 0
    this.show()
  }

  next() {
    if (this.index == this.stepTargets.length - 1) return Turbo.visit(this.doneValue)
    this.index++
    this.show()
  }

  async install() {
    const prompt = window.installPrompt
    if (!prompt) return this.set("install", "manual")
    prompt.prompt()
    const { outcome } = await prompt.userChoice
    window.installPrompt = null
    this.set("install", outcome == "accepted" ? "installed" : "manual")
  }

  installed() {
    this.set("install", "installed")
  }

  // push#enable's answer.
  pushed({ detail: { on, permission } }) {
    this.set("notif", on ? "granted" : [ "denied", "unsupported" ].includes(permission) ? permission : "ask")
  }

  show() {
    const n = this.stepTargets.length
    this.stepTargets.forEach((step, i) => step.hidden = i != this.index)
    this.barTargets.forEach((bar, i) => {
      bar.classList.toggle("bg-pms-primary", i <= this.index)
      bar.classList.toggle("bg-pms-border", i > this.index)
    })
    this.kickerTargets.forEach((kicker) => kicker.textContent = `BƯỚC ${this.index + 1} / ${n}`)
    this.progressTarget.ariaLabel = `Bước ${this.index + 1} trên ${n}`
    scrollTo(0, 0)
  }

  set(name, state) {
    this.step(name)?.querySelectorAll("[data-when]").forEach((el) => el.hidden = !el.dataset.when.split(" ").includes(state))
  }

  drop(name) {
    this.step(name)?.remove()
    this.barTargets.find((bar) => bar.dataset.step == name)?.remove()
  }

  step(name) {
    return this.stepTargets.find((step) => step.dataset.step == name)
  }
}
