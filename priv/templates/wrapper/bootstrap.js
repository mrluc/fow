(() => {
  const bundle = __FOG_BUNDLE__;
  try {
    for (const {snapshot} of Object.values(bundle.pages)) {
      const key = 'fog-of-war:page:' + snapshot.path;
      if (!localStorage.getItem(key)) localStorage.setItem(key, JSON.stringify(snapshot));
    }
  } catch (_) {}
  // Only generated public HTML runs here. Never start a stale LiveView session.
  document.documentElement.dataset.fogOfWarPublicShell = 'true';
  const live = document.createElement('a');
  live.href = bundle.origin + bundle.start_path;
  live.textContent = 'Open live site';
  live.style.cssText = 'position:fixed;right:12px;bottom:12px;padding:10px 14px;border-radius:8px;background:#202124;color:white;font:13px system-ui;z-index:99998';
  document.body.append(live);
  document.addEventListener('click', event => {
    const link = event.target.closest?.('a[href]');
    if (!link) return;
    const url = new URL(link.href);
    if (url.origin === location.origin && (!bundle.pages[url.pathname] || url.search)) {
      event.preventDefault();
      let notice = document.getElementById('public-shell-notice');
      if (!notice) {
        notice = document.createElement('aside'); notice.id = 'public-shell-notice'; notice.role = 'status';
        notice.style.cssText = 'position:fixed;bottom:8px;left:8px;right:8px;padding:8px;background:#202124;color:white;font:12px system-ui;z-index:99999';
        document.body.append(notice);
      }
      notice.textContent = 'That page is not in the offline bundle. Open the live site to continue.';
    }
  });
})();
