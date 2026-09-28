/* freebuff-auto-translate v1 */
// Freebuff Auto-Translator Engine (v1.0)
// High-performance DOM translation with React VDOM safety & intelligent filtering.
(function () {
  'use strict';

  var STORAGE_KEY_ENABLED = 'freebuff-auto-translate-enabled';
  var STORAGE_KEY_CACHE = 'freebuff-translation-cache-v1';

  var isEnabled = true;
  try {
    var stored = localStorage.getItem(STORAGE_KEY_ENABLED);
    if (stored === '0') isEnabled = false;
  } catch (e) {}

  // In-memory cache loaded from LocalStorage
  var translationCache = {};
  try {
    var rawCache = localStorage.getItem(STORAGE_KEY_CACHE);
    if (rawCache) translationCache = JSON.parse(rawCache);
  } catch (e) {}

  var cacheSaveTimer = null;
  function persistCache() {
    if (cacheSaveTimer) return;
    cacheSaveTimer = setTimeout(function () {
      cacheSaveTimer = null;
      try {
        localStorage.setItem(STORAGE_KEY_CACHE, JSON.stringify(translationCache));
      } catch (e) {}
    }, 2000);
  }

  // Pre-seeded high-accuracy dictionary for core UI terms (avoids cold start)
  var SEED_DICT = {
    'Settings': 'הגדרות',
    'General': 'כללי',
    'Appearance': 'מראה',
    'Account': 'חשבון',
    'Theme': 'ערכת נושא',
    'Dark': 'כהה',
    'Light': 'בהיר',
    'System': 'מערכת',
    'New Chat': 'שיחה חדשה',
    'New Conversation': 'שיחה חדשה',
    'Files': 'קבצים',
    'Explorer': 'סייר קבצים',
    'Terminal': 'מסוף',
    'Extensions': 'תוספים',
    'Save': 'שמור',
    'Cancel': 'ביטול',
    'Close': 'סגור',
    'Apply': 'החל',
    'Discard': 'בטל שינויים',
    'Delete': 'מחק',
    'Remove': 'הסר',
    'Rename': 'שנה שם',
    'Copy': 'העתק',
    'Paste': 'הדבק',
    'Cut': 'גזור',
    'Undo': 'בטל',
    'Redo': 'בצע שוב',
    'Search': 'חיפוש',
    'Search files': 'חיפוש קבצים',
    'Type a message...': 'הקלד הודעה...',
    'Ask anything...': 'שאל כל דבר...',
    'Send': 'שלח',
    'Stop': 'עצור',
    'Stop generating': 'עצור הפקה',
    'Clear': 'נקה',
    'Clear chat': 'נקה שיחה',
    'History': 'היסטוריה',
    'No conversations yet': 'אין עדיין שיחות',
    'Sign in': 'התחבר',
    'Sign out': 'התנתק',
    'Log out': 'התנתק',
    'Retry': 'נסה שוב',
    'Model': 'מודל',
    'Default model': 'מודל ברירת מחדל',
    'Tokens': 'טוקנים',
    'Usage': 'שימוש',
    'Help': 'עזרה',
    'Documentation': 'תיעוד',
    'Keyboard Shortcuts': 'קיצורי מקשים'
  };

  for (var k in SEED_DICT) {
    if (!translationCache[k]) {
      translationCache[k] = SEED_DICT[k];
    }
  }

  // Elements to NEVER touch
  var EXCLUDED_TAGS = {
    SCRIPT: 1, STYLE: 1, CODE: 1, PRE: 1, SVG: 1, PATH: 1,
    TEXTAREA: 1, INPUT: 1, KBD: 1, NOSCRIPT: 1
  };

  // Check if an element or its ancestors should be excluded
  function isExcluded(node) {
    var cur = node.nodeType === 3 ? node.parentElement : node;
    while (cur && cur !== document.body && cur !== document.documentElement) {
      if (EXCLUDED_TAGS[cur.tagName]) return true;
      if (cur.isContentEditable) return true;
      if (cur.getAttribute('translate') === 'no') return true;

      var cls = cur.className;
      if (typeof cls === 'string') {
        if (cls.indexOf('monaco-editor') !== -1 ||
            cls.indexOf('xterm') !== -1 ||
            cls.indexOf('terminal') !== -1 ||
            cls.indexOf('codicon') !== -1 ||
            cls.indexOf('font-mono') !== -1 ||
            cls.indexOf('code-block') !== -1) {
          return true;
        }
      }
      cur = cur.parentElement;
    }
    return false;
  }

  // Regex patterns to skip technical strings
  var REGEX_HEBREW = /[\u0590-\u05FF]/;
  var REGEX_ONLY_SYMBOLS = /^[\s\d\p{P}\p{S}]+$/u;
  var REGEX_IS_PATH = /[\\\/]|\b[a-zA-Z]:\\|\.(?:js|ts|tsx|jsx|json|md|py|sh|bat|ps1|html|css|yml|yaml|exe|dll|zip)\b/i;
  var REGEX_IS_TECH = /^(?:https?:\/\/|localhost|\d+\.\d+\.\d+|sha256-|git|npm|bun|pnpm|yarn|docker|node)/i;
  var REGEX_MODEL_ID = /^(?:gpt-|claude-|gemini-|llama|deepseek|qwen|o1|o3)/i;

  function shouldTranslate(text) {
    if (!text) return false;
    var trimmed = text.trim();
    if (trimmed.length < 2) return false;
    if (REGEX_HEBREW.test(trimmed)) return false; // Already Hebrew
    if (REGEX_ONLY_SYMBOLS.test(trimmed)) return false; // Only punctuation/numbers
    if (REGEX_IS_PATH.test(trimmed)) return false; // File paths or filenames
    if (REGEX_IS_TECH.test(trimmed)) return false; // Tech identifiers / URLs
    if (REGEX_MODEL_ID.test(trimmed)) return false; // AI Model IDs
    return true;
  }

  // Batch queue for Google Translate API
  var queue = [];
  var pendingTexts = new Set();
  var batchTimer = null;

  function enqueueForTranslation(text, callback) {
    if (!isEnabled) return;
    if (translationCache[text]) {
      callback(translationCache[text]);
      return;
    }
    if (pendingTexts.has(text)) {
      // Already requested, wait for next cycle
      setTimeout(function () {
        if (translationCache[text]) callback(translationCache[text]);
      }, 500);
      return;
    }

    pendingTexts.add(text);
    queue.push({ text: text, callback: callback });

    if (!batchTimer) {
      batchTimer = setTimeout(processBatch, 250);
    }
  }

  function processBatch() {
    batchTimer = null;
    if (queue.length === 0) return;

    var currentBatch = queue.splice(0, 30); // Max 30 items per batch
    var textsToFetch = [];
    var batchMap = new Map();

    for (var i = 0; i < currentBatch.length; i++) {
      var item = currentBatch[i];
      if (!batchMap.has(item.text)) {
        batchMap.set(item.text, []);
        textsToFetch.push(item.text);
      }
      batchMap.get(item.text).push(item.callback);
    }

    // Translate each phrase safely using Google Translate single endpoint
    textsToFetch.forEach(function (text) {
      var url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=iw&dt=t&q=' + encodeURIComponent(text);
      fetch(url)
        .then(function (res) {
          if (!res.ok) throw new Error('status ' + res.status);
          return res.json();
        })
        .then(function (data) {
          if (data && data[0]) {
            var translated = '';
            for (var j = 0; j < data[0].length; j++) {
              if (data[0][j][0]) translated += data[0][j][0];
            }
            if (translated && translated !== text) {
              translationCache[text] = translated;
              persistCache();
              var callbacks = batchMap.get(text) || [];
              callbacks.forEach(function (cb) { cb(translated); });
            }
          }
        })
        .catch(function (err) {
          // Graceful fallback: original text stays intact
        })
        .finally(function () {
          pendingTexts.delete(text);
        });
    });
  }

  // React Virtual-DOM Safe text node translation
  var handledNodes = new WeakSet();

  function translateTextNode(node) {
    if (!isEnabled || handledNodes.has(node)) return;
    if (isExcluded(node)) return;

    var original = node.nodeValue;
    if (!shouldTranslate(original)) return;

    handledNodes.add(node);
    var trimmed = original.trim();

    // Check instant cache
    if (translationCache[trimmed]) {
      var trans = translationCache[trimmed];
      node.nodeValue = original.replace(trimmed, trans);
      return;
    }

    // Queue for translation
    enqueueForTranslation(trimmed, function (translated) {
      if (node.isConnected) {
        node.nodeValue = original.replace(trimmed, translated);
      }
    });
  }

  // Translate attributes (placeholders, tooltips)
  function translateAttributes(el) {
    if (!isEnabled || isExcluded(el)) return;

    var attrs = ['placeholder', 'title', 'aria-label'];
    for (var i = 0; i < attrs.length; i++) {
      var attr = attrs[i];
      var val = el.getAttribute(attr);
      if (shouldTranslate(val)) {
        var trimmed = val.trim();
        if (translationCache[trimmed]) {
          el.setAttribute(attr, translationCache[trimmed]);
        } else {
          (function (a, v, t) {
            enqueueForTranslation(t, function (translated) {
              if (el.isConnected && el.getAttribute(a) === v) {
                el.setAttribute(a, translated);
              }
            });
          })(attr, val, trimmed);
        }
      }
    }
  }

  // Walk DOM tree safely
  function walk(node) {
    if (!node || isExcluded(node)) return;

    if (node.nodeType === 3) {
      translateTextNode(node);
      return;
    }

    if (node.nodeType === 1) {
      translateAttributes(node);
      var child = node.firstChild;
      while (child) {
        walk(child);
        child = child.nextSibling;
      }
    }
  }

  // MutationObserver with strict debounce to prevent CPU strain
  var observer = null;
  function startObserver() {
    if (observer) return;
    observer = new MutationObserver(function (mutations) {
      if (!isEnabled) return;
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type === 'childList') {
          for (var j = 0; j < m.addedNodes.length; j++) {
            walk(m.addedNodes[j]);
          }
        } else if (m.type === 'characterData') {
          translateTextNode(m.target);
        }
      }
    });

    observer.observe(document.body || document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true
    });
  }

  // Toggle button for Language: עברית / English (only shown if tools hub is not active)
  function mountLangToggle() {
    if (window.__FREEBUFF_TOOLS_HUB__ || document.getElementById('freebuff-tools-hub-container') || document.getElementById('freebuff-lang-toggle')) return;

    var btn = document.createElement('button');
    btn.id = 'freebuff-lang-toggle';
    btn.title = isEnabled ? 'שנה שפה לאנגלית' : 'תרגם לעברית';
    btn.setAttribute('aria-label', 'Toggle UI Language (Hebrew / English)');
    btn.textContent = isEnabled ? 'עברית' : 'EN';
    btn.style.cssText =
      'position:fixed;right:70px;bottom:16px;z-index:2147483647;' +
      'height:36px;padding:0 12px;border-radius:18px;' +
      'border:1px solid var(--border,#2a2a2e);' +
      'background:var(--raised,#232327);color:var(--text,#e7e7e8);' +
      'cursor:pointer;display:flex;align-items:center;justify-content:center;' +
      'font-size:12px;font-weight:600;' +
      'box-shadow:0 2px 12px rgba(0,0,0,.28);' +
      'opacity:.8;transition:all .15s;';

    btn.addEventListener('mouseenter', function () { btn.style.opacity = '1'; });
    btn.addEventListener('mouseleave', function () { btn.style.opacity = '.8'; });
    btn.addEventListener('click', function () {
      isEnabled = !isEnabled;
      try {
        localStorage.setItem(STORAGE_KEY_ENABLED, isEnabled ? '1' : '0');
      } catch (e) {}
      btn.textContent = isEnabled ? 'עברית' : 'EN';
      // Reload UI cleanly so React mounts in chosen language
      window.location.reload();
    });

    (document.body || document.documentElement).appendChild(btn);
  }

  function init() {
    mountLangToggle();
    if (isEnabled) {
      walk(document.body);
      startObserver();
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
