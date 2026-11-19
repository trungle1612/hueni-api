import { Controller } from "@hotwired/stimulus"

// Ảnh phòng (#187): chosen photos are redrawn at 1600px (long edge) as JPEG on the phone before upload, so camera photos
// pass the 5 MB limit and upload fast. The server still checks and re-encodes; a photo the browser can't read goes as it is.
const LONG_EDGE = 1600

export default class extends Controller {
  async shrink() {
    const submit = document.querySelector(`[type=submit][form="${this.element.form?.id}"]`)
    submit?.setAttribute("aria-busy", "true")
    if (submit) submit.disabled = true
    try {
      const files = new DataTransfer()
      for (const file of this.element.files) files.items.add(await this.resize(file))
      this.element.files = files.files
    } finally {
      submit?.removeAttribute("aria-busy")
      if (submit) submit.disabled = false
    }
  }

  async resize(file) {
    try {
      const bitmap = await createImageBitmap(file) // turned upright by its EXIF orientation
      const scale = LONG_EDGE / Math.max(bitmap.width, bitmap.height)
      if (scale >= 1) return file
      const canvas = document.createElement("canvas")
      canvas.width = Math.round(bitmap.width * scale)
      canvas.height = Math.round(bitmap.height * scale)
      canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", 0.85))
      return blob ? new File([ blob ], file.name.replace(/\.[^.]*$/, "") + ".jpg", { type: "image/jpeg" }) : file
    } catch {
      return file
    }
  }
}
