/* freebuff-light v2 */
(function () {
  'use strict';
  var KEY = 'freebuff-light';
  var root = document.documentElement;
  var cur = null;
  try { cur = localStorage.getItem(KEY) === '1'; } catch (e) {}

  var ICON_SUN = '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';
  var ICON_MOON = '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';

  /* The app's window is dark by default; the OS-drawn titlebar overlay (the
     close/min/max buttons) is painted with that dark color. When the light
     theme is on, recolor the overlay so the top-left strip stops being black. */
  function paintOverlay() {
    try {
      if (navigator.windowControlsOverlay && navigator.windowControlsOverlay.setTitleBarOverlay) {
        navigator.windowControlsOverlay.setTitleBarOverlay(
          cur ? { color: '#f0f0f2', symbolColor: '#3a3a40' } : { color: '#0a0a0b', symbolColor: '#9a9aa0' }
        );
      }
    } catch (e) {}
  }

  function paint() {
    if (cur) { root.setAttribute('data-theme', 'light'); }
    else { root.removeAttribute('data-theme'); }
    paintOverlay();
  }
  paint();

  function mount() {
    var btn = document.createElement('button');
    btn.id = 'freebuff-light-toggle';
    btn.title = 'Toggle light / dark mode';
    btn.setAttribute('aria-label', 'Toggle light / dark mode');
    btn.innerHTML = cur ? ICON_MOON : ICON_SUN;
    btn.style.cssText =
      'position:fixed;right:16px;bottom:16px;z-index:2147483647;' +
      'width:36px;height:36px;border-radius:50%;' +
      'border:1px solid var(--border,#2a2a2e);' +
      'background:var(--raised,#232327);color:var(--text,#e7e7e8);' +
      'cursor:pointer;display:flex;align-items:center;justify-content:center;' +
      'box-shadow:0 2px 12px rgba(0,0,0,.28);' +
      'opacity:.8;transition:opacity .15s;';
    btn.addEventListener('mouseenter', function () { btn.style.opacity = '1'; });
    btn.addEventListener('mouseleave', function () { btn.style.opacity = '.8'; });
    btn.addEventListener('click', function () {
      cur = !cur;
      paint();
      try { localStorage.setItem(KEY, cur ? '1' : '0'); } catch (e) {}
      btn.innerHTML = cur ? ICON_MOON : ICON_SUN;
    });
    (document.body || root).appendChild(btn);
  }

  if (document.body) { mount(); }
  else { document.addEventListener('DOMContentLoaded', mount); }
})();
