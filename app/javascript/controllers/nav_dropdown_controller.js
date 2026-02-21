import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "chevron", "logoutForm"]

  connect() {
    console.log("✅ nav_dropdown_controller conectado")
    document.addEventListener("click", this.boundOutside = this.handleOutside.bind(this))
    document.addEventListener("keydown", this.boundEscape = this.handleEscape.bind(this))
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
    document.removeEventListener("keydown", this.boundEscape)
  }

  toggle(event) {
    event.stopPropagation()
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.menuTarget.style.display = "block"
    this.chevronTarget.style.transform = "rotate(180deg)"
  }

  close() {
    this.menuTarget.style.display = "none"
    this.chevronTarget.style.transform = "rotate(0deg)"
  }

  get isOpen() { return this.menuTarget.style.display === "block" }

  logout(event) {
    event.preventDefault()
    this.logoutFormTarget.submit()
  }

  handleOutside(event) {
    if (this.isOpen && !this.element.contains(event.target)) this.close()
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close()
  }
}