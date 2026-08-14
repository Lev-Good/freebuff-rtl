/* ==========================================================================
 * Freebuff Desktop — RTL injection script (v6)
 * --------------------------------------------------------------------------
 * Sets <html dir="rtl">, injects the RTL override stylesheet, and installs
 * the drag-direction shim (see freebuff-rtl-dragfix.js) that reverses the
 * explorer resize drag for the mirrored layout. Also bundles the in-app
 * update notifier (see freebuff-rtl-updater.js) so the launcher route gets
 * the "new version available" card and the update-and-relaunch button too.
 *
 * Use it three ways:
 *   1. DevTools console (instant):  open DevTools (Ctrl+Shift+I), paste the
 *      whole file, press Enter. Works until the window reloads.
 *   2. CDP launcher (persistent):   freebuff-rtl.ps1 sends this file to
 *      Page.addScriptToEvaluateOnNewDocument + Runtime.evaluate.
 *   3. Any browser tab pointed at the app's local URL — same effect.
 *
 * Safe to run more than once (idempotent): it checks for the style tag.
 *
 * Note: the light palette and sun/moon toggle used to be part of this script;
 * Freebuff now ships its own official light/dark toggle, so they were removed.
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
/* The model picker menu inside the composer is anchored to the trigger's
   LEFT edge (base rule .composer-context .agent-menu { left: 0 }) and grows
   rightward. In RTL the trigger mirrors to the row's right end, so the menu
   extends past the window's right edge and gets clipped. Mirror the anchor
   to the right edge so it grows leftward, into the window. */
html[dir="rtl"] .composer-context .agent-menu {
  left: auto;
  right: 0;
}

/* ---- assistant feedback: keep the action on the physical left ------------ */
/* In the stock LTR layout Give feedback is the leftmost footer action. The
   RTL flex row mirrors it to the right, where it collides with the direction
   toggle and the model picker. Restore its physical left-edge position while
   leaving the rest of the message footer RTL. */
html[dir="rtl"] .msg-footer .msg-feedback {
  order: 2;
  margin-inline-start: auto;
  direction: ltr;
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

/* ---- account: keep the profile clear of the native window-controls overlay --
   On RTL systems the OS-drawn titlebar overlay sits at the window's left
   edge, right where the mirrored flex flow would put the account block -
   hiding it. order:-1 puts the account at the far RIGHT, exactly where it
   sits in the stock LTR layout, away from the overlay. */
html[dir="rtl"] .tabbar-account {
  order: -1;
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
 * RTL/LTR direction toggle — see freebuff-rtl-dir.js for the explanation.
 * ========================================================================== */
(function () {
  'use strict';
  var KEY = 'freebuff-rtl-dir';
  var root = document.documentElement;
  var rtl = true;
  function apply() {
    if (rtl) { root.setAttribute('dir', 'rtl'); }
    else { root.removeAttribute('dir'); }
  }
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
      'position:fixed;right:16px;bottom:16px;z-index:2147483647;' +
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

/* ==========================================================================
 * In-app update notifier + auto-update trigger (bundled copy of
 * freebuff-rtl-updater.js with the release version baked in). See that file
 * for the full explanation.
 * ========================================================================== */
(function () {
  'use strict';

  var VERSION = '1.4.1';
  var REPO = 'Lev-Good/freebuff-rtl';
  var API_URL = 'https://api.github.com/repos/' + REPO + '/releases/latest';
  var RELEASE_BASE = 'https://github.com/' + REPO + '/releases/tag/';
  var RELEASES_URL = 'https://github.com/' + REPO + '/releases';

  var LS_DISMISS = 'freebuff-rtl-update-dismissed';
  var LS_DISMISS_AT = 'freebuff-rtl-update-dismissed-at';
  var LS_LASTCHECK = 'freebuff-rtl-update-lastcheck';
  var LS_LATEST = 'freebuff-rtl-update-latest';

  var CHECK_INTERVAL = 6 * 60 * 60 * 1000;
  var REMIND_INTERVAL = 7 * 24 * 60 * 60 * 1000;

  function lsGet(k) {
    try { return localStorage.getItem(k); } catch (e) { return null; }
  }
  function lsSet(k, v) {
    try { localStorage.setItem(k, v); } catch (e) {}
  }

  function cmpVersion(a, b) {
    var pa = String(a).replace(/^v/i, '').split('.').map(function (n) { return parseInt(n, 10) || 0; });
    var pb = String(b).replace(/^v/i, '').split('.').map(function (n) { return parseInt(n, 10) || 0; });
    var len = Math.max(pa.length, pb.length);
    for (var i = 0; i < len; i++) {
      var va = pa[i] || 0;
      var vb = pb[i] || 0;
      if (va > vb) return 1;
      if (va < vb) return -1;
    }
    return 0;
  }

  function latestKnownTag() {
    return lsGet(LS_LATEST) || '';
  }

  function check() {
    var last = parseInt(lsGet(LS_LASTCHECK) || '0', 10);
    if (last && Date.now() - last < CHECK_INTERVAL) {
      var tag = latestKnownTag();
      if (tag && cmpVersion(tag, VERSION) > 0) showCard(tag);
      return;
    }
    lsSet(LS_LASTCHECK, String(Date.now()));

    var ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, 10000);
    fetch(API_URL, ctrl ? { signal: ctrl.signal } : {})
      .then(function (r) {
        if (!r.ok) throw new Error('http ' + r.status);
        return r.json();
      })
      .then(function (rel) {
        clearTimeout(timer);
        var tag = rel && rel.tag_name ? String(rel.tag_name) : '';
        if (!tag) return;
        lsSet(LS_LATEST, tag);
        if (cmpVersion(tag, VERSION) > 0) showCard(tag, rel);
      })
      .catch(function () { clearTimeout(timer); });
  }

  function openUrl(url) {
    var api = window.freebuffDesktop;
    if (api && typeof api.openExternal === 'function') {
      try { api.openExternal(url); return; } catch (e) {}
    }
    var w = window.open(url, '_blank');
    if (!w) {
      var link = document.getElementById('fb-rtl-upd-link');
      if (link) {
        link.textContent = url;
        link.href = url;
        link.style.display = 'inline';
      }
    }
  }

  function openRelease(tag) {
    openUrl(tag ? RELEASE_BASE + tag : RELEASES_URL);
  }

  function requestRestart(tag) {
    var api = window.freebuffDesktop;
    if (!api || typeof api.saveClipboardImage !== 'function') {
      return Promise.reject(new Error('bridge unavailable'));
    }
    var payload = JSON.stringify({ freebuffRtlRestart: true, version: tag, at: Date.now() });
    var bytes = new TextEncoder().encode(payload);
    var invoke = api.saveClipboardImage(bytes, 'rtlupdate');
    var timeout = new Promise(function (_, reject) {
      setTimeout(function () { reject(new Error('timeout')); }, 4000);
    });
    return Promise.race([invoke, timeout]).then(function (res) {
      if (!res || !res.path) throw new Error('marker not written');
      return res;
    });
  }

  function closeApp() {
    var api = window.freebuffDesktop;
    if (api && typeof api.closeWindow === 'function') {
      try { api.closeWindow(); } catch (e) {}
    }
    setTimeout(function () {
      if (!document.hidden) openRelease(latestKnownTag());
    }, 2500);
  }

  function showCard(tag, rel) {
    if (document.getElementById('freebuff-rtl-update-card')) return;

    var dismissed = lsGet(LS_DISMISS);
    var dismissedAt = parseInt(lsGet(LS_DISMISS_AT) || '0', 10);
    if (dismissed === tag && dismissedAt && Date.now() - dismissedAt < REMIND_INTERVAL) return;

    var note = '';
    if (rel && rel.body) {
      var lines = String(rel.body).split('\n');
      for (var i = 0; i < lines.length; i++) {
        var l = lines[i].replace(/^#+\s*/, '').replace(/[*_`]/g, '').trim();
        if (l) { note = l; break; }
      }
      if (note.length > 140) note = note.slice(0, 137) + '...';
    }

    var card = document.createElement('div');
    card.id = 'freebuff-rtl-update-card';
    card.dir = 'rtl';
    card.setAttribute('role', 'alert');
    card.style.cssText =
      'position:fixed;right:16px;bottom:64px;z-index:2147483647;' +
      'width:min(320px,calc(100vw - 32px));box-sizing:border-box;' +
      'padding:14px 16px;border-radius:14px;' +
      'border:1px solid var(--border,#2a2a2e);' +
      'background:var(--raised,#1c1c20);color:var(--text,#e7e7e8);' +
      'font:13px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;' +
      'box-shadow:0 10px 40px rgba(0,0,0,.45);';

    card.innerHTML =
      '<div style="font-weight:700;font-size:13px;margin-bottom:6px">' +
        '\u{1F4E2} עדכון זמין לסקריפט RTL' +
      '</div>' +
      '<div style="margin-bottom:10px;opacity:.92">' +
        'קיימת גרסה חדשה <b>' + tag + '</b> של הסקריפט לתצוגה מימין-לשמאל.' +
        (note ? '<div style="margin-top:4px;opacity:.7;font-size:12px">' + note + '</div>' : '') +
      '</div>' +
      '<div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center">' +
        '<button id="fb-rtl-upd-go" style="' + btnStyle(true) + '">עדכן והפעל מחדש</button>' +
        '<button id="fb-rtl-upd-manual" style="' + btnStyle(false) + '">הורדה ידנית</button>' +
        '<button id="fb-rtl-upd-close" style="' + btnStyle(false) + '">סגור</button>' +
      '</div>' +
      '<div id="fb-rtl-upd-status" style="display:none;margin-top:8px;font-size:12px;opacity:.85"></div>' +
      '<a id="fb-rtl-upd-link" href="#" target="_blank" rel="noreferrer" ' +
        'style="display:none;margin-top:8px;font-size:12px;color:#7cff3f;word-break:break-all"></a>';

    function btnStyle(primary) {
      return primary
        ? 'padding:7px 12px;border-radius:8px;border:0;background:#7cff3f;color:#0c0d0f;' +
          'font:600 12px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;cursor:pointer'
        : 'padding:7px 12px;border-radius:8px;border:1px solid var(--border,#333338);' +
          'background:transparent;color:var(--text,#e7e7e8);' +
          'font:600 12px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;cursor:pointer';
    }

    var status = card.querySelector('#fb-rtl-upd-status');
    function setStatus(text) {
      if (text) { status.style.display = 'block'; status.textContent = text; }
      else { status.style.display = 'none'; status.textContent = ''; }
    }

    card.querySelector('#fb-rtl-upd-go').addEventListener('click', function () {
      var go = card.querySelector('#fb-rtl-upd-go');
      var manual = card.querySelector('#fb-rtl-upd-manual');
      var close = card.querySelector('#fb-rtl-upd-close');
      go.disabled = true; manual.disabled = true; close.disabled = true;
      setStatus('מוריד ומתקין את הגרסה החדשה… התוכנה תיסגר ותיפתח מחדש.');
      requestRestart(tag)
        .then(function () {
          setStatus('מוכן. סוגרים את Freebuff ומפעילים אותו מחדש עם הסקריפט החדש…');
          setTimeout(closeApp, 1200);
        })
        .catch(function () {
          setStatus('לא ניתן לעדכן אוטומטית — פותחים את דף ההורדה.');
          go.disabled = false; manual.disabled = false; close.disabled = false;
          setTimeout(function () { openRelease(tag); }, 600);
        });
    });

    card.querySelector('#fb-rtl-upd-manual').addEventListener('click', function () {
      openRelease(tag);
    });

    card.querySelector('#fb-rtl-upd-close').addEventListener('click', function () {
      lsSet(LS_DISMISS, tag);
      lsSet(LS_DISMISS_AT, String(Date.now()));
      card.parentNode && card.parentNode.removeChild(card);
    });

    (document.body || document.documentElement).appendChild(card);
  }

  function mount() {
    if (document.getElementById('freebuff-rtl-updater-mounted')) return;
    var mark = document.createElement('meta');
    mark.id = 'freebuff-rtl-updater-mounted';
    (document.head || document.documentElement).appendChild(mark);
    setTimeout(check, 4000);
  }

  if (document.body) { mount(); }
  else { document.addEventListener('DOMContentLoaded', mount); }
})();
