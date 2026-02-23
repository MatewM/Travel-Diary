import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fileInput", "dropZone", "uploadIcon",
    "previewArea", "fileList", "counter"
  ]

  connect() {
    this.files = []
  }

  // — Acciones de UI —

  close() {
    const frame = this.element.closest("turbo-frame")
    if (frame) frame.innerHTML = ""
  }

  triggerFileInput(event) {
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
    const incoming = event.dataTransfer?.files
    if (incoming?.length > 0) this.addFiles(incoming)
  }

  previewFiles(event) {
    const incoming = event.target.files
    if (incoming?.length > 0) this.addFiles(incoming)
    // Resetear el input para que el evento change dispare de nuevo
    // si el usuario selecciona los mismos archivos otra vez.
    event.target.value = ""
  }

  // Llamado desde el botón ✕ de cada fila — el índice viene del data-attribute.
  removeFile(event) {
    event.preventDefault()
    event.stopPropagation()
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.files.splice(index, 1)
    this.#syncInput()
    this.#updatePreview()
  }

  // — API interna (usada por tests y lógica interna) —

  async addFiles(incoming) {
    const existing = this.files.map(f => f.name + f.size)
    const deduplicated = Array.from(incoming)
      .filter(f => !existing.includes(f.name + f.size))
    
    // CRÍTICO: Capturar metadatos de cada archivo ANTES de procesarlo
    for (const file of deduplicated) {
      await this.#captureFileMetadata(file)
    }
    
    this.files = [...this.files, ...deduplicated]
    this.#syncInput()
    this.#updatePreview()
  }

  // — Privado —

  #syncInput() {
    const dt = new DataTransfer()
    this.files.forEach(f => dt.items.add(f))
    this.fileInputTarget.files = dt.files
  }

  #updatePreview() {
    const n = this.files.length

    if (n === 0) {
      // Volver al estado inicial si se eliminaron todos los archivos
      this.uploadIconTarget.classList.remove("hidden")
      this.previewAreaTarget.classList.add("hidden")
      return
    }

    // Contador
    this.counterTarget.textContent =
      n === 1 ? "1 archivo seleccionado" : `${n} archivos seleccionados`

    // Lista de archivos con botón ✕ por fila
    this.fileListTarget.innerHTML = ""
    this.files.forEach((file, index) => {
      const isPdf = file.type === "application/pdf"
      const icon = isPdf ? "📄" : "🖼️"

      const row = document.createElement("div")
      row.className = "flex items-center gap-2 py-1 group"
      row.innerHTML =
        `<span class="text-base leading-none flex-shrink-0">${icon}</span>` +
        `<span class="text-sm text-slate-700 truncate flex-1">${this.#esc(file.name)}</span>` +
        `<span class="text-xs text-slate-400 flex-shrink-0 mr-1">${this.#fmtSize(file.size)}</span>` +
        `<button type="button"
                 data-action="click->upload#removeFile"
                 data-index="${index}"
                 class="flex-shrink-0 w-5 h-5 rounded-full text-slate-400
                        hover:text-red-500 hover:bg-red-50 transition-colors
                        flex items-center justify-center leading-none
                        opacity-0 group-hover:opacity-100 focus:opacity-100"
                 aria-label="Eliminar ${this.#esc(file.name)}">✕</button>`
      this.fileListTarget.appendChild(row)
    })

    // Mostrar área de preview, ocultar el icono inicial
    this.uploadIconTarget.classList.add("hidden")
    this.previewAreaTarget.classList.remove("hidden")

    // Limpiar cualquier error previo
    const errorDiv = document.getElementById("upload_form_errors")
    if (errorDiv) errorDiv.innerHTML = ""
  }

  #esc(str) {
    const d = document.createElement("div")
    d.textContent = str
    return d.innerHTML
  }

  #fmtSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  async #captureFileMetadata(file) {
    try {
      // CAPTURAR METADATOS DEL ARCHIVO ORIGINAL (antes de que se pierdan)
      const metadata = {
        filename: file.name,
        size: file.size,
        type: file.type,
        lastModified: file.lastModified, // Timestamp en milisegundos
        lastModifiedDate: new Date(file.lastModified).toISOString()
      }
      
      console.log(`[UploadController] Captured metadata for ${file.name}:`, metadata)
      
      // ALMACENAR metadatos en el objeto File para enviarlos al servidor
      // Usamos una propiedad personalizada que Rails puede leer
      file._originalMetadata = metadata
      
      // ALTERNATIVA: Crear un input hidden con los metadatos
      this.#addMetadataToForm(file.name, metadata)
      
    } catch (error) {
      console.warn(`[UploadController] Failed to capture metadata for ${file.name}:`, error)
    }
  }

  #addMetadataToForm(filename, metadata) {
    // Crear un input hidden con los metadatos para que Rails los reciba
    const form = this.element.closest('form')
    if (!form) return
    
    // Remover metadatos previos para este archivo (si existen)
    const existingInput = form.querySelector(`input[name="file_metadata[${filename}]"]`)
    if (existingInput) existingInput.remove()
    
    // Crear nuevo input con los metadatos
    const input = document.createElement('input')
    input.type = 'hidden'
    input.name = `file_metadata[${filename}]`
    input.value = JSON.stringify(metadata)
    
    form.appendChild(input)
    
    console.log(`[UploadController] Added metadata input for ${filename}`)
  }
}
