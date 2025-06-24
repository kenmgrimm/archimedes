import { Controller } from "@hotwired/stimulus"

// Flash message controller for handling dismissal and auto-hiding
export default class extends Controller {
  connect() {
    console.debug("[FlashController] Connected")
    
    // Auto-hide flash messages after 5 seconds
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, 5000)
  }
  
  disconnect() {
    // Clear timeout if controller is disconnected
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
  
  dismiss() {
    console.debug("[FlashController] Dismissing flash message")
    
    // Add fade-out animation
    this.element.classList.add("opacity-0", "transition-opacity", "duration-500")
    
    // Remove element after animation completes
    setTimeout(() => {
      this.element.remove()
    }, 500)
  }
}
