import { Controller } from "@hotwired/stimulus"

// Search controller for handling semantic search interactions
export default class extends Controller {
  static targets = ["input", "button", "results"]
  
  connect() {
    console.debug("[SearchController] Connected")
  }
  
  submit(event) {
    // Allow the form to submit normally with Turbo
    console.debug("[SearchController] Form submitted with query:", this.inputTarget.value)
  }
  
  searching(event) {
    console.debug("[SearchController] Search in progress")
    
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = true
      this.buttonTarget.value = "Searching..."
      this.buttonTarget.classList.add("opacity-70")
    }
    
    // The button will be re-enabled when Turbo completes the request
    document.addEventListener('turbo:load', this.#searchComplete.bind(this), { once: true })
    document.addEventListener('turbo:frame-load', this.#searchComplete.bind(this), { once: true })
  }
  
  #searchComplete() {
    console.debug("[SearchController] Search completed")
    
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      this.buttonTarget.value = "Search"
      this.buttonTarget.classList.remove("opacity-70")
    }
    
    if (this.hasResultsTarget) {
      this.resultsTarget.classList.add("animate-fade-in")
    }
  }
}
