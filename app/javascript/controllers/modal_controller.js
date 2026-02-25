import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Se ejecuta cada vez que el modal aparece
  connect() {
    console.log("Modal conectado") // Esto te servirá para ver en la consola si el controlador vive
    document.body.classList.add("overflow-hidden")
  }

  close(e) {
    if (e) {
      e.preventDefault()
      e.stopPropagation() // Evita que el clic se propague a otros elementos
    }

    // 1. Limpiamos el contenido visual
    this.element.innerHTML = ""

    // 2. Quitamos el 'src' para que Turbo pueda volver a cargar el frame si clicamos otra vez
    this.element.removeAttribute("src")

    // 3. Si la URL cambió a /verify, la devolvemos al dashboard
    if (window.location.pathname.includes('/verify')) {
      window.history.pushState({}, "", "/dashboard")
    }

    // 4. Remover overflow-hidden del body para permitir scroll del fondo
    document.body.classList.remove("overflow-hidden")

    console.log("Modal cerrado correctamente")
  }
}
