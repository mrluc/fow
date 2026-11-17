export function createLogoutHook(lockAccount) {
  return {
    mounted() {
      let pending = false
      let replaying = false
      const status = this.el.querySelector('[data-fow-logout-status]')
      const forward = async (event, resume) => {
        if (replaying || event.defaultPrevented) return
        event.preventDefault()
        event.stopImmediatePropagation()
        if (pending) return

        pending = true
        status.textContent = ''
        try {
          await lockAccount()
          replaying = true
          resume()
        } catch (error) {
          console.error('[FogOfWar] Could not clear the account key', error)
          status.textContent = 'Could not clear offline access. Please try signing out again.'
        } finally {
          replaying = false
          pending = false
        }
      }

      this.onLogoutClick = event => {
        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
        const control = event.target.closest?.('a[href], button, input[type="submit"], [phx-click]')
        if (!control || !this.el.contains(control) || control.matches(':disabled')) return
        // Forms inside the wrapper go through submit, which also covers Enter.
        if (control.form && this.el.contains(control.form) && control.type === 'submit') return
        forward(event, () => { if (control.isConnected) control.click() })
      }
      this.onLogoutSubmit = event => {
        const form = event.target
        const submitter = event.submitter
        forward(event, () => {
          if (!form.isConnected) return
          if (submitter) HTMLFormElement.prototype.requestSubmit.call(form, submitter)
          else HTMLFormElement.prototype.requestSubmit.call(form)
        })
      }
      this.el.addEventListener('click', this.onLogoutClick, true)
      this.el.addEventListener('submit', this.onLogoutSubmit, true)
    },
    destroyed() {
      this.el.removeEventListener('click', this.onLogoutClick, true)
      this.el.removeEventListener('submit', this.onLogoutSubmit, true)
    }
  }
}
