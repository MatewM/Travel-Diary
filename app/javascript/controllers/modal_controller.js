import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Se ejecuta cada vez que el modal aparece
  connect() {
    console.log("Modal conectado") // Esto te servirá para ver en la consola si el controlador vive
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
    
    console.log("Modal cerrado correctamente")
  }
}
