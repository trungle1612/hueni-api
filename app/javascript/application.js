// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Trạng thái tải (#259, board Loading.dc.html). Chuyển màn: the progress bar after 300ms, the old screen stays.
Turbo.config.drive.progressBarDelay = 300

// Nút đang lưu: Turbo locks the submit button; it also spins, and a "Lưu …" button reads "Đang lưu…".
// Capture phase: Turbo reads data-turbo-submits-with before turbo:submit-start.
addEventListener("submit", ({ submitter }) => {
  if (submitter?.textContent.trim().startsWith("Lưu") && !submitter.dataset.turboSubmitsWith) submitter.dataset.turboSubmitsWith = "Đang lưu…"
}, true)
addEventListener("turbo:submit-start", ({ detail }) => detail.formSubmission.submitter?.setAttribute("aria-busy", "true"))
addEventListener("turbo:submit-end", ({ detail }) => detail.formSubmission.submitter?.removeAttribute("aria-busy"))

// A form that leaves the app (Zalo login, data-turbo="false") gets the same lock until the page goes;
// Back from Zalo shows the page from the bfcache, so put the button back.
addEventListener("submit", ({ target, submitter, defaultPrevented }) => {
  if (defaultPrevented || target.dataset.turbo != "false" || !submitter?.dataset.turboSubmitsWith) return
  submitter.dataset.label = submitter.innerHTML
  submitter.innerHTML = submitter.dataset.turboSubmitsWith
  submitter.ariaBusy = "true"
  submitter.disabled = true
})
addEventListener("pageshow", ({ persisted }) => {
  if (persisted) document.querySelectorAll("[data-label]").forEach(button => {
    button.innerHTML = button.dataset.label
    button.removeAttribute("data-label")
    button.removeAttribute("aria-busy")
    button.disabled = false
  })
})

// A tap outside an open sheet only closes it. The browser makes a popover's backdrop click-through, so the same tap
// would also open the bar or room under the scrim. The sheet is still open on pointerdown, already closed on click.
// Its own button still goes through: the browser keeps the sheet open for it, and the click toggles it shut.
let openSheet = null
addEventListener("pointerdown", () => openSheet = document.querySelector(".pms-sheet:popover-open"), true)
addEventListener("click", event => {
  const own = event.target.closest("[popovertarget]")?.popoverTargetElement == openSheet
  if (openSheet && !own && !event.target.closest(".pms-sheet")) { event.preventDefault(); event.stopPropagation() }
  openSheet = null
}, true)
