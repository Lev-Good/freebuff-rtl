/* freebuff-rtl-updater v1
 * --------------------------------------------------------------------------
 * In-app update notifier for the Freebuff RTL script.
 *
 * Injected into index.html by freebuff-rtl-patch.ps1 (which bakes the
 * __VERSION__ placeholder from the VERSION file), and bundled into
 * freebuff-rtl.js for the DevTools / CDP launcher route.
 *
 * What it does:
 *   1. Checks https://api.github.com/repos/Lev-Good/freebuff-rtl/releases/latest
 *      (CORS is open on api.github.com) against the version baked into this
 *      file. Rate-limited to one check every few hours, remembered in
 *      localStorage, so it never hammers GitHub on every load.
 *   2. If a newer version exists, shows a small card above the RTL/LTR toggle
 *      button: "a new version is available" with three actions.
 *   3. "Update & relaunch": asks the auto-patch keeper to install the new
 *      version and restart Freebuff. The keeper runs in the background
 *      (install-permanent.bat) and is the only process that can download,
 *      replace the old script files and relaunch the app - the renderer is
 *      sandboxed. The handshake is a tiny JSON marker written through the
 *      app's own clipboard-image IPC into %TEMP%\freebuff-desktop-pastes\
 *      (the one renderer->disk channel the app exposes); the keeper watches
 *      that folder. Then this script closes the window, the keeper waits for
 *      the exit and starts Freebuff again with the new files applied.
 *   4. "Manual download": opens the GitHub release page in the browser (used
 *      by installs that do not run the keeper, e.g. the apply-rtl.bat route).
 *
 * Safe to run more than once (idempotent): guarded by a DOM id. Silent when
 * the network is unavailable or the app already runs the latest version.
 * ========================================================================== */
(function () {
  'use strict';

  var VERSION = '__VERSION__';
  var REPO = 'Lev-Good/freebuff-rtl';
  var API_URL = 'https://api.github.com/repos/' + REPO + '/releases/latest';
  var RELEASE_BASE = 'https://github.com/' + REPO + '/releases/tag/';
  var RELEASES_URL = 'https://github.com/' + REPO + '/releases';

  var LS_DISMISS = 'freebuff-rtl-update-dismissed';
  var LS_DISMISS_AT = 'freebuff-rtl-update-dismissed-at';
  var LS_LASTCHECK = 'freebuff-rtl-update-lastcheck';
  var LS_LATEST = 'freebuff-rtl-update-latest';

  var CHECK_INTERVAL = 6 * 60 * 60 * 1000;   // at most one GitHub call / 6h
  var REMIND_INTERVAL = 7 * 24 * 60 * 60 * 1000; // re-show a dismissed update after a week

  function lsGet(k) {
    try { return localStorage.getItem(k); } catch (e) { return null; }
  }
  function lsSet(k, v) {
    try { localStorage.setItem(k, v); } catch (e) {}
  }

  /* Compare "1.4.0"-style versions. Returns 1 / -1 / 0. */
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
      // Still show the card for a version we already learned about.
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
      // Popup blocked and no bridge: surface the link inside the card instead.
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

  /* Renderer -> keeper handshake: write a JSON marker into the app's own
     temp paste folder via clipboard:saveImage. The keeper watches for
     *.rtlupdate files there. */
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
    // If the window is somehow still here a moment later, the app could not
    // close itself - fall back to the manual download page.
    setTimeout(function () {
      if (!document.hidden) openRelease(latestKnownTag());
    }, 2500);
  }

  function showCard(tag, rel) {
    if (document.getElementById('freebuff-rtl-update-card')) return;

    // A dismissed version stays hidden for a week, then gently re-appears.
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
    // Let the app settle before we talk to GitHub.
    setTimeout(check, 4000);
  }

  if (document.body) { mount(); }
  else { document.addEventListener('DOMContentLoaded', mount); }
})();
