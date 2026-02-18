import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fileInput", "dropZone", "uploadIcon",
    "previewArea", "imagePreview", "pdfIcon", "filename"
  ]

  close() {
    const frame = this.element.closest("turbo-frame")
    if (frame) frame.innerHTML = ""
  }

  triggerFileInput(event) {
    // Avoid double-trigger when clicking the file input itself
    if (event.target === this.fileInputTarget) return
    this.fileInputTarget.click()
  }

  dragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.classList.add("!border-indigo-400", "!bg-indigo-50")
  }

  dragLeave(event) {
    event.stopPropagation()
    this.dropZoneTarget.classList.remove("!border-indigo-400", "!bg-indigo-50")
  }

  dropFile(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dragLeave(event)

    const files = event.dataTransfer?.files
    if (files?.length > 0) {
      this.#assignFilesToInput(files)
      this.#showPreview(files[0])
    }
  }

  previewFile(event) {
    const file = event.target.files?.[0]
    if (file) this.#showPreview(file)
  }

  // — Private helpers —

  #assignFilesToInput(fileList) {
    const dt = new DataTransfer()
    dt.items.add(fileList[0])
    this.fileInputTarget.files = dt.files
  }

  #showPreview(file) {
    if (this.hasFilenameTarget) {
      this.filenameTarget.textContent = file.name
    }

    this.uploadIconTarget.classList.add("hidden")
    this.previewAreaTarget.classList.remove("hidden")

    if (file.type === "application/pdf") {
      this.imagePreviewTarget.classList.add("hidden")
      this.pdfIconTarget.classList.remove("hidden")
    } else {
      this.pdfIconTarget.classList.add("hidden")
      const reader = new FileReader()
      reader.onload = (e) => {
        this.imagePreviewTarget.src = e.target.result
        this.imagePreviewTarget.classList.remove("hidden")
      }
      reader.readAsDataURL(file)
    }
  }
}
