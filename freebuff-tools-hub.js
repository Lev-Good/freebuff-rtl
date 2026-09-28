/* freebuff-tools-hub v1 */
// Freebuff Control Hub (v1.0)
// Unified in-app settings: Hebrew translation, RTL direction, Ad blocker, Auto-updates, Update Notifier
(function () {
  'use strict';

  window.__FREEBUFF_TOOLS_HUB__ = true;

  var CURRENT_VERSION = '1.7.0';
  var REPO = 'Lev-Good/freebuff-rtl';
  var API_URL = 'https://api.github.com/repos/' + REPO + '/releases/latest';
  var RELEASES_PAGE = 'https://github.com/' + REPO + '/releases';

  var KEY_HUB_RTL = 'freebuff-rtl-dir';
  var KEY_HUB_TRANS = 'freebuff-auto-translate-enabled';
  var KEY_HUB_UPDATES = 'freebuff-updates-disabled';
  var KEY_HUB_ADS = 'freebuff-ads-blocked';

  var LS_LASTCHECK = 'freebuff-tools-lastcheck';
  var LS_LATEST_TAG = 'freebuff-tools-latest-tag';
  var LS_DISMISSED = 'freebuff-tools-dismissed-tag';
  var CHECK_INTERVAL = 4 * 60 * 60 * 1000; // 4 hours

  var root = document.documentElement;

  // 1. Initial State
  var rtlEnabled = localStorage.getItem(KEY_HUB_RTL) !== '0';
  var transEnabled = localStorage.getItem(KEY_HUB_TRANS) !== '0';
  var updatesDisabled = localStorage.getItem(KEY_HUB_UPDATES) !== '0';
  var adsBlocked = localStorage.getItem(KEY_HUB_ADS) !== '0';
  var newReleaseAvailable = null;

  function applyRtl() {
    if (rtlEnabled) { root.setAttribute('dir', 'rtl'); }
    else { root.removeAttribute('dir'); }
  }
  applyRtl();

  function applyAdBlockCss() {
    var adStyleEl = document.getElementById('freebuff-ad-hide-style');
    if (adsBlocked) {
      if (!adStyleEl) {
        adStyleEl = document.createElement('style');
        adStyleEl.id = 'freebuff-ad-hide-style';
        adStyleEl.textContent = '[data-component*="ad"], [class*="AdContainer"], [class*="partner-ad"], [class*="inline-ad"], [data-testid*="ad-"] { display: none !important; }';
        (document.head || root).appendChild(adStyleEl);
      }
    } else if (adStyleEl) {
      adStyleEl.remove();
    }
  }
  applyAdBlockCss();

  // 2. Request backend updates file change via clipboard IPC (or keeper)
  function requestToggleUpdates(disable) {
    var api = window.freebuffDesktop;
    if (api && typeof api.saveClipboardImage === 'function') {
      try {
        var payload = JSON.stringify({
          freebuffAction: 'set-updates',
          disableUpdates: disable,
          at: Date.now()
        });
        api.saveClipboardImage(new TextEncoder().encode(payload), 'rtlupdate');
      } catch (e) {}
    }
  }

  function requestRestart(tag) {
    var api = window.freebuffDesktop;
    if (api && typeof api.saveClipboardImage === 'function') {
      try {
        var payload = JSON.stringify({
          freebuffRtlRestart: true,
          version: tag,
          at: Date.now()
        });
        return Promise.resolve(api.saveClipboardImage(new TextEncoder().encode(payload), 'rtlupdate'));
      } catch (e) {}
    }
    return Promise.reject(new Error('no bridge'));
  }

  // 3. Version comparison helper
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

  // 4. Update check logic
  function checkForUpdates(onDone) {
    fetch(API_URL)
      .then(function (res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      })
      .then(function (data) {
        try { localStorage.setItem(LS_LASTCHECK, String(Date.now())); } catch (e) {}
        if (!data || !data.tag_name) {
          if (onDone) onDone(false, 'לא התקבל מידע מ-GitHub');
          return;
        }
        var latestTag = String(data.tag_name);
        try { localStorage.setItem(LS_LATEST_TAG, latestTag); } catch (e) {}
        var isNewer = cmpVersion(latestTag, CURRENT_VERSION) > 0;
        if (isNewer) {
          newReleaseAvailable = data;
          showUpdateBadge(true);
          showUpdateCard(data);
          if (onDone) onDone(true, latestTag, data);
        } else {
          newReleaseAvailable = null;
          showUpdateBadge(false);
          if (onDone) onDone(false, 'הגרסה שבידך (v' + CURRENT_VERSION + ') היא המעודכנת ביותר!');
        }
      })
      .catch(function (err) {
        if (onDone) onDone(false, 'שגיאה בבדיקה: ' + (err.message || 'אין חיבור לרשת'));
      });
  }

  function showUpdateBadge(show) {
    var dot = document.getElementById('fb-tools-update-badge');
    if (show) {
      if (!dot) {
        dot = document.createElement('span');
        dot.id = 'fb-tools-update-badge';
        dot.style.cssText =
          'position:absolute;top:-2px;right:-2px;width:10px;height:10px;' +
          'background:#10b981;border:2px solid var(--raised,#232327);border-radius:50%;' +
          'box-shadow:0 0 8px #10b981;';
        var btn = document.getElementById('freebuff-tools-hub-btn');
        if (btn) btn.appendChild(dot);
      }
    } else if (dot) {
      dot.remove();
    }
  }

  function showUpdateCard(data) {
    if (document.getElementById('freebuff-update-alert-card')) return;
    var tag = data.tag_name || 'חדשה';
    try {
      if (localStorage.getItem(LS_DISMISSED) === tag) return;
    } catch (e) {}

    var assetUrl = '';
    if (data.assets && data.assets.length > 0) {
      for (var i = 0; i < data.assets.length; i++) {
        if (data.assets[i].name && data.assets[i].name.indexOf('.zip') !== -1) {
          assetUrl = data.assets[i].browser_download_url;
          break;
        }
      }
    }
    if (!assetUrl) assetUrl = data.zipball_url || RELEASES_PAGE;

    var card = document.createElement('div');
    card.id = 'freebuff-update-alert-card';
    card.style.cssText =
      'position:fixed;bottom:110px;right:16px;z-index:2147483647;width:300px;' +
      'background:var(--raised,#1b1b1f);border:1px solid var(--border,rgba(128,128,128,0.3));' +
      'border-radius:14px;box-shadow:0 14px 40px rgba(0,0,0,0.45);padding:14px;box-sizing:border-box;' +
      'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;direction:rtl;' +
      'color:var(--text,currentColor);font-size:12px;';

    card.innerHTML =
      '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;">' +
        '<span style="font-weight:700;font-size:13px;display:flex;align-items:center;gap:6px;">' +
          '<span>🚀</span><span>עדכון חדש זמין: ' + tag + '</span>' +
        '</span>' +
        '<button id="fb-card-close" style="background:none;border:none;color:var(--text,currentColor);opacity:0.6;cursor:pointer;font-size:14px;padding:0;line-height:1;">✕</button>' +
      '</div>' +
      '<div style="font-size:11px;opacity:0.8;margin-bottom:12px;line-height:1.4;">' +
        'קיימת מהדורה חדשה של כלי Freebuff ב-GitHub עם שיפורים ותיקונים נוספים.' +
      '</div>' +
      '<div style="display:flex;gap:8px;flex-direction:column;">' +
        '<button id="fb-btn-download-zip" style="height:34px;background:#10b981;color:#fff;border:none;border-radius:8px;font-weight:600;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;box-shadow:0 2px 8px rgba(16,185,129,0.3);">' +
          '<span>📥</span><span>הורד עדכון ישיר (ZIP)</span>' +
        '</button>' +
        '<div style="display:flex;gap:6px;">' +
          '<button id="fb-btn-relaunch" style="flex:1;height:28px;background:var(--border,rgba(128,128,128,0.2));color:var(--text,currentColor);border:none;border-radius:6px;font-size:11px;cursor:pointer;">' +
            '🔄 עדכן והפעל מחדש' +
          '</button>' +
          '<button id="fb-btn-open-gh" style="flex:1;height:28px;background:var(--border,rgba(128,128,128,0.2));color:var(--text,currentColor);border:none;border-radius:6px;font-size:11px;cursor:pointer;">' +
            '🌐 דף המהדורה' +
          '</button>' +
        '</div>' +
      '</div>';

    card.querySelector('#fb-card-close').onclick = function () {
      try { localStorage.setItem(LS_DISMISSED, tag); } catch (e) {}
      card.remove();
    };

    card.querySelector('#fb-btn-download-zip').onclick = function () {
      window.open(assetUrl, '_blank');
    };

    card.querySelector('#fb-btn-open-gh').onclick = function () {
      window.open(data.html_url || RELEASES_PAGE, '_blank');
    };

    card.querySelector('#fb-btn-relaunch').onclick = function () {
      var selfBtn = this;
      selfBtn.textContent = 'מכין עדכון...';
      selfBtn.disabled = true;
      requestRestart(tag).then(function () {
        setTimeout(function () {
          var api = window.freebuffDesktop;
          if (api && api.closeWindow) api.closeWindow();
        }, 1200);
      }).catch(function () {
        window.open(assetUrl, '_blank');
      });
    };

    (document.body || root).appendChild(card);
  }

  // 5. UI Menu injection
  function mountHub() {
    // Remove obsolete single buttons if present
    var oldDir = document.getElementById('freebuff-dir-toggle');
    if (oldDir) oldDir.remove();
    var oldLang = document.getElementById('freebuff-lang-toggle');
    if (oldLang) oldLang.remove();

    if (document.getElementById('freebuff-tools-hub-container')) return;

    var container = document.createElement('div');
    container.id = 'freebuff-tools-hub-container';

    // Load saved position or default to elevated position above the settings & Discord icons
    var savedPos = null;
    try {
      var rawPos = localStorage.getItem('freebuff-tools-hub-pos');
      if (rawPos) savedPos = JSON.parse(rawPos);
    } catch (e) {}

    var posStyle = 'right:16px;bottom:64px;';
    if (savedPos && savedPos.left && savedPos.top) {
      posStyle = 'left:' + savedPos.left + ';top:' + savedPos.top + ';right:auto;bottom:auto;';
    }

    container.style.cssText =
      'position:fixed;' + posStyle + 'z-index:2147483647;' +
      'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;' +
      'direction:rtl;user-select:none;touch-action:none;';

    // Main Toggle Button
    var btn = document.createElement('button');
    btn.id = 'freebuff-tools-hub-btn';
    btn.title = 'מרכז הכלים וההגדרות (גרור לשינוי מיקום)';
    btn.setAttribute('aria-label', 'Freebuff Tools Hub');
    btn.innerHTML = '<span style="font-size:15px;line-height:1;margin-left:4px;">⚙️</span><span style="font-size:12px;font-weight:600;">כלים</span>';
    btn.style.cssText =
      'position:relative;height:36px;padding:0 14px;border-radius:18px;' +
      'border:1px solid var(--border,rgba(128,128,128,0.28));' +
      'background:var(--raised,#232327);color:var(--text,currentColor);' +
      'cursor:grab;display:flex;align-items:center;justify-content:center;' +
      'box-shadow:0 3px 14px rgba(0,0,0,.3);opacity:.9;transition:opacity .15s ease-in-out, transform .15s ease-in-out;outline:none;user-select:none;';

    btn.addEventListener('mouseenter', function () { btn.style.opacity = '1'; btn.style.transform = 'scale(1.04)'; });
    btn.addEventListener('mouseleave', function () { btn.style.opacity = '.9'; btn.style.transform = 'scale(1)'; });

    // Dropdown Modal / Popup
    var popup = document.createElement('div');
    popup.id = 'freebuff-tools-hub-popup';
    popup.style.cssText =
      'display:none;position:absolute;bottom:46px;right:0;width:275px;' +
      'background:var(--raised,#1b1b1f);border:1px solid var(--border,rgba(128,128,128,0.25));' +
      'border-radius:14px;box-shadow:0 12px 36px rgba(0,0,0,.35);' +
      'padding:14px;box-sizing:border-box;color:var(--text,currentColor);z-index:2147483647;font-size:12px;';

    function adjustPopupPosition() {
      var rect = container.getBoundingClientRect();
      if (rect.top > 330) {
        popup.style.bottom = '46px';
        popup.style.top = 'auto';
      } else {
        popup.style.top = '46px';
        popup.style.bottom = 'auto';
      }
      if (rect.left < 280) {
        popup.style.left = '0';
        popup.style.right = 'auto';
      } else {
        popup.style.right = '0';
        popup.style.left = 'auto';
      }
    }

    function renderPopup() {
      popup.innerHTML =
        '<div style="font-size:13px;font-weight:700;margin-bottom:12px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--border,rgba(128,128,128,0.2));padding-bottom:8px;">' +
          '<span>🛠️ מרכז שליטה והגדרות</span>' +
          '<button id="fb-hub-close" style="background:none;border:none;color:var(--text,currentColor);opacity:0.6;cursor:pointer;font-size:14px;padding:0 4px;line-height:1;">✕</button>' +
        '</div>' +
        '<div style="display:flex;flex-direction:column;gap:12px;">' +
          rowItem('🇮🇱 תרגום ממשק לעברית', transEnabled, 'fb-toggle-trans', 'מתרגם כפתורים ותפריטים') +
          rowItem('↔️ תצוגה מימין לשמאל (RTL)', rtlEnabled, 'fb-toggle-rtl', 'היפוך כיוון צ\'אט ועמודות') +
          rowItem('🚫 חסימת פרסומות בצ\'אט', adsBlocked, 'fb-toggle-ads', 'מנטרל פרסומות והצעות') +
          rowItem('🛑 חסימת עדכונים אוטומטיים', updatesDisabled, 'fb-toggle-updates', 'מונע דריסת קבצים והגדרות') +
        '</div>' +
        '<div style="margin-top:12px;padding-top:10px;border-top:1px solid var(--border,rgba(128,128,128,0.2));display:flex;flex-direction:column;gap:6px;">' +
          '<div style="display:flex;align-items:center;justify-content:space-between;font-size:11px;color:var(--text,currentColor);opacity:0.85;">' +
            '<span>גרסה מותקנת: <b>v' + CURRENT_VERSION + '</b></span>' +
            '<button id="fb-btn-check-updates" style="background:none;border:none;color:#10b981;font-weight:600;font-size:11px;cursor:pointer;padding:0;text-decoration:underline;">' +
              'בדוק עדכונים' +
            '</button>' +
          '</div>' +
          '<div id="fb-check-status" style="font-size:10px;color:var(--text,currentColor);opacity:0.75;text-align:center;min-height:14px;"></div>' +
        '</div>';

      popup.querySelector('#fb-hub-close').onclick = function () { popup.style.display = 'none'; };

      // Bind toggles
      popup.querySelector('#fb-toggle-trans').onchange = function (e) {
        transEnabled = e.target.checked;
        localStorage.setItem(KEY_HUB_TRANS, transEnabled ? '1' : '0');
        window.location.reload();
      };

      popup.querySelector('#fb-toggle-rtl').onchange = function (e) {
        rtlEnabled = e.target.checked;
        localStorage.setItem(KEY_HUB_RTL, rtlEnabled ? '1' : '0');
        applyRtl();
      };

      popup.querySelector('#fb-toggle-ads').onchange = function (e) {
        adsBlocked = e.target.checked;
        localStorage.setItem(KEY_HUB_ADS, adsBlocked ? '1' : '0');
        applyAdBlockCss();
      };

      popup.querySelector('#fb-toggle-updates').onchange = function (e) {
        updatesDisabled = e.target.checked;
        localStorage.setItem(KEY_HUB_UPDATES, updatesDisabled ? '1' : '0');
        requestToggleUpdates(updatesDisabled);
      };

      popup.querySelector('#fb-btn-check-updates').onclick = function (e) {
        e.stopPropagation();
        var statusEl = popup.querySelector('#fb-check-status');
        statusEl.textContent = 'בודק מול GitHub...';
        checkForUpdates(function (hasUpdate, msg, data) {
          if (hasUpdate) {
            statusEl.innerHTML = '<span style="color:#10b981;font-weight:600;">קיים עדכון ' + msg + '!</span>';
          } else {
            statusEl.textContent = msg;
          }
        });
      };
    }

    function rowItem(title, checked, id, subtitle) {
      return '<div style="display:flex;align-items:center;justify-content:space-between;gap:8px;">' +
        '<div style="max-width:190px;">' +
          '<div style="font-weight:600;color:var(--text,currentColor);line-height:1.3;">' + title + '</div>' +
          (subtitle ? '<div style="font-size:11px;color:var(--text,currentColor);opacity:0.65;margin-top:2px;line-height:1.2;">' + subtitle + '</div>' : '') +
        '</div>' +
        '<label style="position:relative;display:inline-block;width:34px;height:18px;cursor:pointer;flex-shrink:0;">' +
          '<input type="checkbox" id="' + id + '" ' + (checked ? 'checked' : '') + ' style="opacity:0;width:0;height:0;">' +
          '<span style="position:absolute;top:0;left:0;right:0;bottom:0;background:' + (checked ? '#10b981' : 'rgba(128,128,128,0.35)') + ';border-radius:18px;transition:.2s;"></span>' +
          '<span style="position:absolute;content:\'\';height:12px;width:12px;left:' + (checked ? '18px' : '4px') + ';bottom:3px;background:#ffffff;box-shadow:0 1px 3px rgba(0,0,0,0.3);border-radius:50%;transition:.2s;"></span>' +
        '</label>' +
      '</div>';
    }

    // Drag and Click handling
    var isDragging = false;
    var startX = 0, startY = 0, origX = 0, origY = 0;
    var hasMoved = false;

    btn.addEventListener('mousedown', function (e) {
      if (e.button !== 0) return;
      isDragging = true;
      hasMoved = false;
      startX = e.clientX;
      startY = e.clientY;
      var rect = container.getBoundingClientRect();
      origX = rect.left;
      origY = rect.top;
      btn.style.cursor = 'grabbing';
      e.preventDefault();
    });

    document.addEventListener('mousemove', function (e) {
      if (!isDragging) return;
      var dx = e.clientX - startX;
      var dy = e.clientY - startY;
      if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
        hasMoved = true;
      }
      var newLeft = Math.max(8, Math.min(window.innerWidth - 100, origX + dx));
      var newTop = Math.max(8, Math.min(window.innerHeight - 50, origY + dy));
      container.style.left = newLeft + 'px';
      container.style.top = newTop + 'px';
      container.style.right = 'auto';
      container.style.bottom = 'auto';
    });

    document.addEventListener('mouseup', function () {
      if (!isDragging) return;
      isDragging = false;
      btn.style.cursor = 'grab';
      if (hasMoved) {
        try {
          localStorage.setItem('freebuff-tools-hub-pos', JSON.stringify({
            left: container.style.left,
            top: container.style.top
          }));
        } catch (e) {}
      }
    });

    btn.addEventListener('click', function (e) {
      if (hasMoved) {
        e.stopPropagation();
        return;
      }
      e.stopPropagation();
      if (popup.style.display === 'none') {
        renderPopup();
        adjustPopupPosition();
        popup.style.display = 'block';
      } else {
        popup.style.display = 'none';
      }
    });

    document.addEventListener('click', function (e) {
      if (!container.contains(e.target)) {
        popup.style.display = 'none';
      }
    });

    container.appendChild(popup);
    container.appendChild(btn);
    (document.body || root).appendChild(container);

    // Initial check on load (delayed by 3 seconds so UI isn't blocked)
    setTimeout(function () {
      var lastCheck = 0;
      try { lastCheck = parseInt(localStorage.getItem(LS_LASTCHECK) || '0', 10); } catch (e) {}
      if (Date.now() - lastCheck > CHECK_INTERVAL) {
        checkForUpdates();
      }
    }, 3000);
  }

  function ensureHub() {
    var oldDir = document.getElementById('freebuff-dir-toggle');
    if (oldDir) oldDir.remove();
    var oldLang = document.getElementById('freebuff-lang-toggle');
    if (oldLang) oldLang.remove();

    if (document.body && !document.getElementById('freebuff-tools-hub-container')) {
      mountHub();
    }
  }

  ensureHub();
  if (document.body) {
    try { new MutationObserver(ensureHub).observe(document.body, { childList: true }); } catch (e) {}
  }
  try { new MutationObserver(ensureHub).observe(root, { childList: true }); } catch (e) {}
  document.addEventListener('DOMContentLoaded', ensureHub);
})();
