import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  close() {
    const frame = this.element.closest("turbo-frame")
    if (frame) frame.innerHTML = ""
  }
}
