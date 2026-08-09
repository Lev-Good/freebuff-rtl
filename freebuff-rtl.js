/* ==========================================================================
 * Freebuff Desktop — RTL + light-mode injection script (v3)
 * --------------------------------------------------------------------------
 * Sets <html dir="rtl">, injects the RTL override stylesheet, installs the
 * drag-direction shim (see freebuff-rtl-dragfix.js) that reverses the
 * explorer resize drag for the mirrored layout, and adds the light-mode
 * palette + sun/moon toggle button (see freebuff-light.css/js).
 *
 * Use it three ways:
 *   1. DevTools console (instant):  open DevTools (Ctrl+Shift+I), paste the
 *      whole file, press Enter. Works until the window reloads.
 *   2. CDP launcher (persistent):   freebuff-rtl.ps1 sends this file to
 *      Page.addScriptToEvaluateOnNewDocument + Runtime.evaluate.
 *   3. Any browser tab pointed at the app's local URL — same effect.
 *
 * Safe to run more than once (idempotent): it checks for the style tag.
 * ========================================================================== */
(function () {
  'use strict';

  var CSS = /*__CSS__*/ `
/* ==== freebuff-rtl ==== */
/* ==========================================================================
   Freebuff Desktop — RTL layout override (v2)
   --------------------------------------------------------------------------
   The app is built LTR-only. This sheet flips it to a proper right-to-left
   layout once <html dir="rtl"> is set (the freebuff-rtl.js script does that).

   Design decisions:
   * dir="rtl" does the heavy lifting — flex rows, text alignment and
     logical properties mirror automatically.
   * The floating panels (explorer / preview, prompt-rail) are mirrored from
     the right edge to the left edge — the "end" side in RTL.
   * All the physical left/right paddings and margins the app hard-codes are
     swapped here so gutters and reserves land on the correct sides.
   * The collapsed explorer strip is anchored to the container's LEFT edge
     (the container sits at the window's left), with the resize handle on
     the strip's right edge — matching the mirrored layout.
   * Code (pre/code/xterm) is pinned back to LTR — code stays left-to-right
     even in an RTL interface.
   ========================================================================== */

/* ---- base: inherit RTL from the <html dir="rtl"> attribute ---------------- */
html[dir="rtl"] body {
  direction: rtl;
}

/* ---- floating panels: mirror right-anchored panels to the left ------------ */
html[dir="rtl"] .explorer {
  left: 10px;
  right: auto;
}
/* collapsed strip: anchor to the container's LEFT edge (container is at the
   window's left). Must beat the base .explorer.collapsed .explorer-header
   rule (inset: 0 0 0 auto), which would leave the strip floating mid-window. */
html[dir="rtl"] .explorer.collapsed .explorer-header {
  inset: 0 auto 0 0;
}
/* collapsed resize handle: sits at the strip's RIGHT edge (between the strip
   and the content) — mirror of the base left-edge placement. */
html[dir="rtl"] .explorer.collapsed .explorer-resize-handle {
  left: calc(var(--explorer-visible-width) - 8px);
  right: auto;
}
/* collapsed tab badges mirror to the opposite corner */
html[dir="rtl"] .explorer.collapsed .explorer-tab-count,
html[dir="rtl"] .explorer.collapsed .explorer-tab-dot {
  right: auto;
  left: 3px;
}
html[dir="rtl"] .explorer-resize-handle {
  left: calc(var(--explorer-visible-width) - 8px);
  right: auto;
}
html[dir="rtl"] .prompt-rail {
  left: 12px;
  right: auto;
}

/* ---- reserves: the space kept clear for those panels moves to the left --- */
html[dir="rtl"] .thread-body {
  padding-left: var(--explorer-reserve);
  padding-right: 0;
}
html[dir="rtl"] .thread-bottom {
  padding-left: var(--rail-reserve);
  padding-right: 0;
}
html[dir="rtl"] .empty {
  padding-left: var(--explorer-reserve);
  padding-right: 0;
}
html[dir="rtl"] .working-dock {
  left: var(--rail-reserve);
  right: 0;
}

/* ---- chat transcript gutters: swap the asymmetric padding ---------------- */
html[dir="rtl"] .messages {
  margin-left: calc(-1 * var(--explorer-reserve));
  margin-right: 0;
  padding-left: calc(var(--chat-gutter) + var(--rail-reserve) + var(--explorer-reserve));
  padding-right: var(--chat-gutter);
}

/* ---- text alignment that was hard-coded to left --------------------------- */
html[dir="rtl"] .tab-select,
html[dir="rtl"] .home-threads,
html[dir="rtl"] .home-thread,
html[dir="rtl"] .header-menu-item,
html[dir="rtl"] .prompt-rail-item {
  text-align: right;
}

/* ---- chat bubbles: mirror the tail corner --------------------------------- */
html[dir="rtl"] .bubble {
  border-radius: 13px 3px 13px 13px;
}

/* ---- tab strip: close / pop-out buttons and paddings mirror ---------------- */
html[dir="rtl"] .tab-select {
  padding-left: 46px;
  padding-right: 6px;
}
html[dir="rtl"] .tab-close {
  left: 5px;
  right: auto;
}
html[dir="rtl"] .tab-popout {
  left: 24px;
  right: auto;
}
html[dir="rtl"] .tab-unseen-dot {
  margin: 5px 0 0 5px;
}
html[dir="rtl"] .tab-premium {
  margin-right: auto;
  margin-left: 0;
}
html[dir="rtl"] .tab-project {
  margin-right: 6px;
  margin-left: 0;
}
html[dir="rtl"] .tabbar {
  padding-left: calc(10px + 100vw - env(titlebar-area-x, 0px) - env(titlebar-area-width, 100%));
  padding-right: 10px;
}

/* ---- explorer internals ---------------------------------------------------- */
html[dir="rtl"] .explorer-header {
  padding-left: 8px;
  padding-right: 0;
}
html[dir="rtl"] .explorer-tabs {
  padding-right: 8px;
  padding-left: 0;
}

/* ---- keep code left-to-right even inside an RTL layout --------------------- */
html[dir="rtl"] pre,
html[dir="rtl"] code,
html[dir="rtl"] .xterm {
  direction: ltr;
  text-align: left;
  unicode-bidi: isolate;
}

/* ---- light theme (see freebuff-light.css) -------------------------------- */
html[data-theme="light"] {
  color-scheme: light;
  --bg: #f7f7f8;
  --surface: #ffffff;
  --surface-2: #f0f0f2;
  --raised: #e6e6e9;
  --border: #d6d6db;
  --text: #1a1a1d;
  --muted: #565660;
  --faint: #8a8a93;
  --brand: #17803c;
  --brand-dim: #156a32;
  --accent: #27272c;
  --accent-dim: #6c6c75;
  --premium: #b45309;
  --green: #17803c;
  --danger: #d42626;
  --focus-ring: color-mix(in srgb, var(--accent) 55%, transparent);
}
html[data-theme="light"] .tabbar {
  background: var(--surface-2);
}
`;

  function apply() {
    var root = document.documentElement;
    if (!root || !document.head) {
      requestAnimationFrame(apply);
      return;
    }
    root.setAttribute('dir', 'rtl');
    if (document.getElementById('freebuff-rtl-style')) return;
    var style = document.createElement('style');
    style.id = 'freebuff-rtl-style';
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  apply();
})();

/* ==========================================================================
 * RTL drag-direction fix — see freebuff-rtl-dragfix.js for the explanation.
 * ========================================================================== */
!function () {
  'use strict';
  var dragging = false;
  function shim(e) {
    var t = e.target;
    if (!dragging && e.type === 'pointerdown' && t && t.closest && t.closest('.explorer-resize-handle')) {
      dragging = true;
    }
    if (!dragging) return;
    if (e.type === 'pointerup' || e.type === 'pointercancel') dragging = false;
    var v = e.clientX;
    Object.defineProperty(e, 'clientX', {
      configurable: true,
      get: function () { return window.innerWidth - v; }
    });
  }
  document.addEventListener('pointerdown', shim, true);
  document.addEventListener('pointermove', shim, true);
  document.addEventListener('pointerup', shim, true);
  document.addEventListener('pointercancel', shim, true);
}();

/* ==========================================================================
 * Light-mode toggle — see freebuff-light.js for the explanation.
 * ========================================================================== */
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
    btn.innerHTML = cur ? '&#127769;' : '&#9728;&#65039;';
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
