import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Se ejecuta cada vez que el modal aparece
  connect() {
    console.log("Modal conectado")
    document.body.classList.add("overflow-hidden")
  }

  // Se ejecuta cuando el elemento se elimina del DOM
  disconnect() {
    document.body.classList.remove("overflow-hidden")
    console.log("Modal desconectado")
  }

  close(e) {
    if (e) {
      e.preventDefault()
      e.stopPropagation() // Evita que el clic se propague a otros elementos
    }

    // 1. Encontramos el turbo-frame que contiene este modal
    const frame = this.element.closest("turbo-frame")

    if (frame) {
      // 2. Limpiamos el contenido del frame completamente para no dejar fondos
      frame.innerHTML = ""
      // 3. Quitamos el 'src' para que Turbo pueda volver a cargar el frame si clicamos otra vez
      frame.removeAttribute("src")
    }

    // 4. Si la URL cambió a /verify, la devolvemos al dashboard
    if (window.location.pathname.includes('/verify')) {
      window.history.pushState({}, "", "/dashboard")
    }

    // 5. Remover overflow-hidden del body para permitir scroll del fondo
    document.body.classList.remove("overflow-hidden")

    console.log("Modal cerrado correctamente")
  }

  closeOutside(e) {
    // Si el clic fue directamente en el contenedor exterior (el fondo oscuro)
    if (e.target === this.element) {
      this.close(e)
    }
  }
}
