import { Controller } from "@hotwired/stimulus"

// Analysis controller for handling content analysis interactions
export default class extends Controller {
  static targets = ["button", "results", "spinner"]
  
  connect() {
    console.debug("[AnalysisController] Connected")
    
    // Listen for the custom success event
    document.addEventListener('analysis:success', this.handleSuccess.bind(this))
  }
  
  disconnect() {
    // Clean up event listener when controller is disconnected
    document.removeEventListener('analysis:success', this.handleSuccess.bind(this))
  }
  
  // Handler for the custom success event
  handleSuccess() {
    console.debug("[AnalysisController] Received success event")
    this.success()
  }
  
  start(event) {
    console.debug("[AnalysisController] Analysis started")
    
    // Prevent default form submission behavior
    if (event) {
      event.preventDefault()
    }
    
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = true
      this.buttonTarget.classList.add("opacity-50")
      this.buttonTarget.querySelector('span').textContent = "Analyzing..."
      
      // Show spinner
      if (this.hasSpinnerTarget) {
        console.debug("[AnalysisController] Showing spinner")
        this.spinnerTarget.classList.remove("hidden")
      }
      
      // Get the form element
      const form = this.buttonTarget.closest('form')
      if (form) {
        console.debug("[AnalysisController] Submitting form via fetch")
        
        // Submit the form via fetch to handle it as AJAX
        const url = form.action
        const method = form.method || 'post'
        const formData = new FormData(form)
        
        fetch(url, {
          method: method,
          body: formData,
          headers: {
            'Accept': 'text/vnd.turbo-stream.html',
            'X-Requested-With': 'XMLHttpRequest'
          },
          credentials: 'same-origin'
        })
        .then(response => {
          if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`)
          }
          return response.text()
        })
        .then(html => {
          console.debug("[AnalysisController] Response received, processing Turbo Stream")
          
          // Process the Turbo Stream response
          const parser = new DOMParser()
          const doc = parser.parseFromString(html, 'text/html')
          const streamElements = doc.querySelectorAll('turbo-stream')
          
          if (streamElements && streamElements.length > 0) {
            console.debug(`[AnalysisController] Found ${streamElements.length} turbo-stream elements`)
            
            // Process each turbo-stream element
            streamElements.forEach(element => {
              const action = element.getAttribute('action')
              const target = element.getAttribute('target')
              console.debug(`[AnalysisController] Processing turbo-stream: ${action} for ${target}`)
              
              // Apply the Turbo Stream
              if (action === 'update' && target === 'flash_messages') {
                const flashContainer = document.getElementById('flash_messages')
                if (flashContainer) {
                  flashContainer.innerHTML = element.querySelector('template').content.firstElementChild.innerHTML
                  console.debug('[AnalysisController] Updated flash messages')
                }
              } else {
                // For other actions, let Turbo handle it
                document.body.appendChild(element)
              }
            })
          } else {
            console.debug("[AnalysisController] No turbo-stream elements found")
          }
          
          // Call success handler
          this.success()
          
          // Show notification
          document.dispatchEvent(new CustomEvent('notification:show', {
            detail: {
              message: 'Analysis completed successfully',
              type: 'success',
              duration: 5000
            }
          }))
        })
        .catch(error => {
          console.error("[AnalysisController] Error:", error)
          this.error({ detail: error })
        })
      }
    }
  }
  
  success(event = null) {
    console.debug("[AnalysisController] Analysis completed successfully")
    
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      this.buttonTarget.classList.remove("opacity-50")
      
      // Restore button text
      const buttonSpan = this.buttonTarget.querySelector('span')
      if (buttonSpan) {
        buttonSpan.textContent = "Analyze"
      }
      
      // Hide spinner
      if (this.hasSpinnerTarget) {
        console.debug("[AnalysisController] Hiding spinner")
        this.spinnerTarget.classList.add("hidden")
      }
    }
    
    if (this.hasResultsTarget) {
      this.resultsTarget.classList.add("animate-fade-in")
    }
  }
  
  error(event) {
    console.error("[AnalysisController] Analysis failed", event.detail)
    
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      this.buttonTarget.classList.remove("opacity-50")
      this.buttonTarget.textContent = "Retry Analysis"
    }
  }
}
