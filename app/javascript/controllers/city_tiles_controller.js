import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tile"]
  static values = {
    images: Array
  }

  connect() {
    if (!this.imagesValue || this.imagesValue.length === 0) return

    this.usedIndices = new Set()
    this.stopped = false
    this.assignInitialImages()
    this.quickInitialSwap()
    this.runCycle()
  }

  disconnect() {
    this.stopped = true
    if (this.timer) clearTimeout(this.timer)
  }

  assignInitialImages() {
    const shuffled = this.shuffleArray([...Array(this.imagesValue.length).keys()])
    this.tileTargets.forEach((tile, i) => {
      const idx = shuffled[i % shuffled.length]
      const img = tile.querySelector("img")
      if (img) {
        img.src = this.imagesValue[idx]
        this.usedIndices.add(idx)
      }
    })
  }

  quickInitialSwap() {
    const tiles = this.shuffleArray([...this.tileTargets])
    const pick = tiles.slice(0, 2)
    pick.forEach((tile, i) => {
      setTimeout(() => {
        if (this.stopped) return
        const img = tile.querySelector("img")
        if (!img) return
        const newIdx = this.pickNewImage()
        tile.style.transition = "opacity 1.5s ease-in-out"
        tile.style.opacity = "0"
        setTimeout(() => {
          if (this.stopped) return
          img.src = this.imagesValue[newIdx]
          img.onload = () => {
            tile.style.transition = "opacity 1.5s ease-in-out"
            tile.style.opacity = "1"
          }
        }, 1500)
      }, 800 + i * 1200)
    })
  }

  runCycle() {
    if (this.stopped) return

    const tiles = this.shuffleArray([...this.tileTargets])
    const selected = tiles.slice(0, 7)

    selected.forEach((tile, i) => {
      const delay = (5000 + Math.random() * 10000)
      setTimeout(() => {
        if (this.stopped) return
        this.swapTile(tile)
      }, delay)
    })

    const cycleEnd = 18000 + Math.random() * 5000
    this.timer = setTimeout(() => {
      this.runCycle()
    }, cycleEnd)
  }

  swapTile(tile) {
    const img = tile.querySelector("img")
    if (!img) return

    const newIdx = this.pickNewImage()

    tile.style.transition = "opacity 3s ease-in-out"
    tile.style.opacity = "0"

    setTimeout(() => {
      if (this.stopped) return
      img.src = this.imagesValue[newIdx]
      img.onload = () => {
        tile.style.transition = "opacity 3s ease-in-out"
        tile.style.opacity = "1"
      }
    }, 3000)
  }

  pickNewImage() {
    let newIdx
    let attempts = 0
    do {
      newIdx = Math.floor(Math.random() * this.imagesValue.length)
      attempts++
    } while (this.usedIndices.has(newIdx) && attempts < this.imagesValue.length)

    if (attempts >= this.imagesValue.length) {
      this.usedIndices.clear()
      this.tileTargets.forEach(t => {
        const tImg = t.querySelector("img")
        if (tImg && tImg.src) {
          const path = new URL(tImg.src, window.location.origin).pathname
          const found = this.imagesValue.indexOf(path)
          if (found !== -1) this.usedIndices.add(found)
        }
      })
      newIdx = Math.floor(Math.random() * this.imagesValue.length)
    }

    this.usedIndices.add(newIdx)
    return newIdx
  }

  shuffleArray(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]]
    }
    return arr
  }
}
