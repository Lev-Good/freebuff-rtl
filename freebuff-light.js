/* freebuff-light */
(function () {
  'use strict';
  var KEY = 'freebuff-light';
  var root = document.documentElement;
  var cur = null;
  try { cur = localStorage.getItem(KEY) === '1'; } catch (e) {}

  function paint() {
    if (cur) { root.setAttribute('data-theme', 'light'); }
    else { root.removeAttribute('data-theme'); }
  }
  paint();

  function mount() {
    var btn = document.createElement('button');
    btn.id = 'freebuff-light-toggle';
    btn.title = 'Toggle light / dark mode';
    btn.setAttribute('aria-label', 'Toggle light / dark mode');
    btn.innerHTML = cur ? '&#127769;' : '&#9728;&#65039;'; /* moon / sun */
    btn.style.cssText =
      'position:fixed;right:16px;bottom:16px;z-index:2147483647;' +
      'width:36px;height:36px;border-radius:50%;' +
      'border:1px solid var(--border,#2a2a2e);' +
      'background:var(--raised,#232327);color:var(--text,#e7e7e8);' +
      'cursor:pointer;display:flex;align-items:center;justify-content:center;' +
      'font-size:16px;line-height:1;box-shadow:0 2px 12px rgba(0,0,0,.28);' +
      'opacity:.8;transition:opacity .15s;';
    btn.addEventListener('mouseenter', function () { btn.style.opacity = '1'; });
    btn.addEventListener('mouseleave', function () { btn.style.opacity = '.8'; });
    btn.addEventListener('click', function () {
      cur = !cur;
      paint();
      try { localStorage.setItem(KEY, cur ? '1' : '0'); } catch (e) {}
      btn.innerHTML = cur ? '&#127769;' : '&#9728;&#65039;';
    });
    (document.body || root).appendChild(btn);
  }

  if (document.body) { mount(); }
  else { document.addEventListener('DOMContentLoaded', mount); }
})();
