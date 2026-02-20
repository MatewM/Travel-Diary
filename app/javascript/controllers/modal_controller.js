import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  async open(event) {
    event.preventDefault()
    const url = event.currentTarget.dataset.url
    if (!url) return

    // Use Turbo to navigate to the URL, which will load the content into the modal frame
    const frame = document.getElementById("modal")
    if (frame) {
      frame.src = url
    }
  }

  close(event) {
    console.log("Modal close called")
    event.preventDefault()
    const frame = document.getElementById("modal")
    if (frame) {
      console.log("Clearing modal frame")
      frame.innerHTML = ""
    } else {
      console.log("Modal frame not found")
    }
  }

  connect() {
    console.log("Modal controller connected")
  }
}
