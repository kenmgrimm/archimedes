import { Controller } from "@hotwired/stimulus"

// Navbar controller for handling mobile menu toggle
export default class extends Controller {
  static targets = ["menu", "menuIcon", "closeIcon"]
  
  connect() {
    console.debug("[NavbarController] Connected")
  }
  
  toggleMenu() {
    console.debug("[NavbarController] Toggling mobile menu")
    
    if (this.hasMenuTarget) {
      this.menuTarget.classList.toggle("hidden")
      
      if (this.hasMenuIconTarget && this.hasCloseIconTarget) {
        this.menuIconTarget.classList.toggle("hidden")
        this.closeIconTarget.classList.toggle("hidden")
      }
    }
  }
}
