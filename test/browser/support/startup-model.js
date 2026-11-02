// Browser-only executable model for ADR 0001. Not imported by the library or generators.
// Iframes stand in for native documents; these tests make no native presentation claims.
(() => {
  const {pages, css} = window.startupFixture;
  const cached = document.querySelector('#cached');
  let candidate, generation = 0, currentPath = '/';
  const events = [];
  function cancel() {
    candidate?.remove(); candidate = null;
  }
  function showCached(path) {
    generation++; cancel(); currentPath = path;
    document.body.dataset.presentation = 'cached';
    cached.hidden = false;
    cached.srcdoc = '<!doctype html><html><head><style>' + css + '</style></head><body>' + pages[path].snapshot.html + '</body></html>';
    cached.onload = () => cached.contentDocument.addEventListener('click', event => {
      const link = event.target.closest('a[href]');
      if (!link) return;
      const url = new URL(link.getAttribute('href'), location.origin);
      event.preventDefault();
      if (url.origin === location.origin && pages[url.pathname]) {
        showCached(url.pathname); recover();
      }
    });
    events.push({kind:'cached', path});
  }
  function recover() {
    if (document.body.dataset.presentation === 'live') return;
    cancel();
    const attempt = String(++generation);
    candidate = document.createElement('iframe');
    candidate.id = 'candidate'; candidate.title = 'Pending live page';
    candidate.name = attempt;
    candidate.setAttribute('aria-hidden', 'true'); candidate.inert = true;
    candidate.src = currentPath;
    document.body.append(candidate);
    events.push({kind:'attempt', attempt, path:currentPath});
  }
  window.addEventListener('message', event => {
    const message = event.data;
    if (event.origin !== location.origin || !candidate || event.source !== candidate.contentWindow ||
      message?.kind !== 'fog-of-war-test-root-mounted' || message.attempt !== String(generation) ||
      message.path !== currentPath) return;
    cached.hidden = true;
    candidate.style.opacity = '1'; candidate.style.pointerEvents = 'auto';
    candidate.inert = false; candidate.removeAttribute('aria-hidden');
    document.body.dataset.presentation = 'live';
    events.push({kind:'committed', attempt:message.attempt, path:currentPath});
  });
  window.addEventListener('online', recover); // Deterministic stand-in for a host retry trigger.
  window.startupModel = {
    inspect: () => ({path:currentPath, generation, events:[...events]}),
    // Internal host callbacks for race tests, not public application controls.
    navigate: path => {showCached(path); recover()},
    retry: recover,
  };
  showCached('/'); recover();
})();
