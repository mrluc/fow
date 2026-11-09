export function installPaperModal(root = document) {
  const modals = root.querySelectorAll('[data-paper-modal]')
  if (!modals.length) return
  let previousFocus

  function close(modal) {
    modal.hidden = true
    document.body.classList.remove('paper-modal-open')
    previousFocus?.focus()
  }

  root.querySelectorAll('[data-paper-open]').forEach((button) => button.addEventListener('click', () => {
    const modal = root.getElementById?.(button.dataset.paperOpen) ?? document.getElementById(button.dataset.paperOpen)
    if (!modal) return
    previousFocus = button
    modal.hidden = false
    document.body.classList.add('paper-modal-open')
    modal.querySelector('.paper-modal-close')?.focus()
  }))

  modals.forEach((modal) => {
    modal.querySelectorAll('[data-paper-close]').forEach((button) => button.addEventListener('click', () => close(modal)))
  })
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      const openModal = [...modals].find((modal) => !modal.hidden)
      if (openModal) close(openModal)
    }
  })
}
