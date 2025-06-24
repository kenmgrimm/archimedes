import { Controller } from "@hotwired/stimulus"

// Notification controller for showing toast notifications
export default class extends Controller {
  static targets = ["container"]
  
  connect() {
    console.debug("[NotificationController] Connected")
    
    // Listen for notification events
    document.addEventListener('notification:show', this.showNotification.bind(this))
  }
  
  disconnect() {
    // Clean up event listener
    document.removeEventListener('notification:show', this.showNotification.bind(this))
  }
  
  showNotification(event) {
    const { message, type = 'info', duration = 5000 } = event.detail || {}
    console.debug(`[NotificationController] Showing notification: ${message} (${type})`)
    
    if (!message) return
    
    // Create notification element
    const notification = this.createNotificationElement(message, type)
    
    // Add to container
    this.containerTarget.appendChild(notification)
    
    // Animate in
    setTimeout(() => {
      notification.classList.remove('opacity-0')
      notification.classList.remove('-translate-y-4')
    }, 10)
    
    // Auto-dismiss after duration
    setTimeout(() => {
      this.dismissNotification(notification)
    }, duration)
  }
  
  createNotificationElement(message, type) {
    // Determine color scheme based on type
    const colorScheme = {
      success: 'bg-green-500 text-white',
      error: 'bg-red-500 text-white',
      warning: 'bg-yellow-500 text-white',
      info: 'bg-blue-500 text-white'
    }[type] || 'bg-gray-800 text-white'
    
    // Create element
    const element = document.createElement('div')
    element.className = `${colorScheme} rounded-md shadow-lg p-4 mb-3 flex items-center justify-between transform transition-all duration-300 opacity-0 -translate-y-4`
    
    // Add content
    element.innerHTML = `
      <div class="flex items-center">
        <div class="ml-3">
          <p class="text-sm font-medium">${message}</p>
        </div>
      </div>
      <div class="ml-4 flex-shrink-0 flex">
        <button type="button" class="inline-flex text-white focus:outline-none" data-action="click->notification#dismiss">
          <svg class="h-5 w-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
          </svg>
        </button>
      </div>
    `
    
    return element
  }
  
  dismiss(event) {
    const notification = event?.currentTarget?.closest('div') || event
    this.dismissNotification(notification)
  }
  
  dismissNotification(notification) {
    // Animate out
    notification.classList.add('opacity-0')
    notification.classList.add('translate-y-4')
    
    // Remove after animation completes
    setTimeout(() => {
      notification.remove()
    }, 300)
  }
}
