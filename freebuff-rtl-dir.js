/* freebuff-rtl-dir v1 */
(function () {
  'use strict';
  var KEY = 'freebuff-rtl-dir';
  var root = document.documentElement;
  var rtl = true;

  function apply() {
    if (rtl) { root.setAttribute('dir', 'rtl'); }
    else { root.removeAttribute('dir'); }
  }

  /* Restore the saved preference on load (overrides the static dir="rtl"
     that apply-rtl.bat writes into index.html). */
  try {
    var saved = localStorage.getItem(KEY);
    if (saved === '0') { rtl = false; apply(); }
    else if (saved === '1') { rtl = true; apply(); }
  } catch (e) {}

  function mount() {
    var btn = document.createElement('button');
    btn.id = 'freebuff-dir-toggle';
    btn.title = rtl ? 'Switch to left-to-right' : 'Switch to right-to-left';
    btn.setAttribute('aria-label', 'Toggle text direction (RTL / LTR)');
    btn.textContent = rtl ? 'RTL' : 'LTR';
    btn.style.cssText =
      'position:fixed;right:16px;bottom:60px;z-index:2147483647;' +
      'height:36px;min-width:44px;padding:0 10px;border-radius:18px;' +
      'border:1px solid var(--border,#2a2a2e);' +
      'background:var(--raised,#232327);color:var(--text,#e7e7e8);' +
      'cursor:pointer;display:flex;align-items:center;justify-content:center;' +
      'font-size:11px;font-weight:650;letter-spacing:.04em;' +
      'box-shadow:0 2px 12px rgba(0,0,0,.28);' +
      'opacity:.8;transition:opacity .15s;';
    btn.addEventListener('mouseenter', function () { btn.style.opacity = '1'; });
    btn.addEventListener('mouseleave', function () { btn.style.opacity = '.8'; });
    btn.addEventListener('click', function () {
      rtl = !rtl;
      apply();
      try { localStorage.setItem(KEY, rtl ? '1' : '0'); } catch (e) {}
      btn.textContent = rtl ? 'RTL' : 'LTR';
      btn.title = rtl ? 'Switch to left-to-right' : 'Switch to right-to-left';
    });
    (document.body || root).appendChild(btn);
  }

  if (document.body) { mount(); }
  else { document.addEventListener('DOMContentLoaded', mount); }
})();
