/* freebuff-auto-translate v1 */
// Freebuff Auto-Translator Engine (v2.0)
// High-performance DOM translation with React VDOM safety, multi-engine fallback & offline dictionary.
(function () {
  'use strict';

  var STORAGE_KEY_ENABLED = 'freebuff-auto-translate-enabled';
  var STORAGE_KEY_CACHE = 'freebuff-translation-cache-v1';

  var isEnabled = true;
  try {
    var stored = localStorage.getItem(STORAGE_KEY_ENABLED);
    if (stored === '0') isEnabled = false;
  } catch (e) {}

  // In-memory cache loaded from LocalStorage (persisted forever across runs)
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
    }, 1000);
  }

  // Pre-seeded comprehensive dictionary for core Freebuff terms (0ms instant translation)
  var SEED_DICT = {
    // Navigation & Common Actions
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
    'Save all': 'שמור הכל',
    'Cancel': 'ביטול',
    'Close': 'סגור',
    'Close tab': 'סגור כרטיסייה',
    'Close other tabs': 'סגור כרטיסיות אחרות',
    'Apply': 'החל',
    'Apply diff': 'החל שינויים',
    'Accept': 'קבל',
    'Accept change': 'קבל שינוי',
    'Accept all': 'קבל הכל',
    'Reject': 'דחה',
    'Reject change': 'דחה שינוי',
    'Reject all': 'דחה הכל',
    'Discard': 'בטל שינויים',
    'Delete': 'מחק',
    'Remove': 'הסר',
    'Rename': 'שנה שם',
    'Copy': 'העתק',
    'Copy code': 'העתק קוד',
    'Paste': 'הדבק',
    'Cut': 'גזור',
    'Undo': 'בטל',
    'Redo': 'בצע שוב',
    'Search': 'חיפוש',
    'Search files': 'חיפוש קבצים',
    'Search codebase': 'חיפוש בבסיס הקוד',
    'Refresh': 'רענן',
    'Reload': 'טען מחדש',
    'Reload window': 'טען חלון מחדש',
    
    // Chat & Prompts
    'Type a message...': 'הקלד הודעה...',
    'Ask anything...': 'שאל כל דבר...',
    'Ask a question or describe a task...': 'שאל שאלה או תאר משימה...',
    'Send': 'שלח',
    'Stop': 'עצור',
    'Stop generating': 'עצור הפקה',
    'Clear': 'נקה',
    'Clear chat': 'נקה שיחה',
    'Clear history': 'נקה היסטוריה',
    'History': 'היסטוריה',
    'No conversations yet': 'אין עדיין שיחות',
    'Sign in': 'התחבר',
    'Sign out': 'התנתק',
    'Log out': 'התנתק',
    'Try again': 'נסה שוב',
    'Retry': 'נסה שוב',
    'Thinking...': 'חושב...',
    'Searching codebase...': 'מחפש בבסיס הקוד...',
    'Reading files...': 'קורא קבצים...',
    'Writing file...': 'כותב קובץ...',
    'Running command...': 'מריץ פקודה...',
    'Command executed': 'הפקודה בוצעה',
    'Changes applied': 'השינויים הוחלו',
    
    // Approvals & Security
    'Allow once': 'אפשר פעם אחת',
    'Always allow': 'אפשר תמיד',
    'Deny': 'דחה',
    'Confirm': 'אישור',
    'Are you sure?': 'האם אתה בטוח?',
    
    // Models & Configuration
    'Model': 'מודל',
    'Models': 'מודלים',
    'Default model': 'מודל ברירת מחדל',
    'Provider': 'ספק',
    'Providers': 'ספקים',
    'API Key': 'מפתח API',
    'Enter API key...': 'הזן מפתח API...',
    'Tokens': 'טוקנים',
    'Usage': 'שימוש',
    'Help': 'עזרה',
    'Documentation': 'תיעוד',
    'Keyboard Shortcuts': 'קיצורי מקשים',
    'Shortcuts': 'קיצורים',
    'Custom Instructions': 'הוראות מותאמות אישית',
    'System prompt': 'הנחיית מערכת',
    'Temperature': 'טמפרטורה (יצירתיות)',
    'Context window': 'חלון הקשר',
    'Max output tokens': 'מקסימום טוקנים לפלט',
    'Thinking budget': 'תקציב חשיבה',
    'Prompt caching': 'מטמון הנחיות',
    'Workspace': 'סביבת עבודה',
    'Indexing': 'יצירת אינדקס',
    'Indexing status': 'סטטוס אינדקס',
    'Files indexed': 'קבצים שאונדקסו',
    'Reindex': 'אנדקס מחדש',
    
    // File tree & editor
    'Open folder': 'פתח תיקייה',
    'Add project': 'הוסף פרויקט',
    'New file': 'קובץ חדש',
    'New folder': 'תיקייה חדשה',
    'Collapse all': 'כווץ הכל',
    'Reveal in explorer': 'הצג בסייר הקבצים',
    'Give feedback': 'משוב'
  };

  for (var k in SEED_DICT) {
    if (!translationCache[k]) {
      translationCache[k] = SEED_DICT[k];
    }
  }

  // Tags whose internal text MUST NOT be translated (code, scripts, styles)
  var EXCLUDED_TEXT_TAGS = {
    SCRIPT: 1, STYLE: 1, CODE: 1, PRE: 1, SVG: 1, PATH: 1,
    NOSCRIPT: 1, KBD: 1
  };

  // Check if an element is strictly code or technical editor
  function isCodeOrTechnical(node) {
    var cur = node.nodeType === 3 ? node.parentElement : node;
    while (cur && cur !== document.body && cur !== document.documentElement) {
      if (EXCLUDED_TEXT_TAGS[cur.tagName]) return true;
      if (cur.isContentEditable) return true;
      if (cur.getAttribute('translate') === 'no') return true;

      var cls = cur.className;
      if (typeof cls === 'string') {
        if (cls.indexOf('monaco-editor') !== -1 ||
            cls.indexOf('xterm') !== -1 ||
            cls.indexOf('terminal') !== -1 ||
            cls.indexOf('code-block') !== -1) {
          return true;
        }
      }
      cur = cur.parentElement;
    }
    return false;
  }

  // Regex patterns to skip non-translatable text
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
    if (REGEX_ONLY_SYMBOLS.test(trimmed)) return false; // Only symbols/numbers
    if (REGEX_IS_PATH.test(trimmed)) return false; // File paths
    if (REGEX_IS_TECH.test(trimmed)) return false; // URLs / Identifiers
    if (REGEX_MODEL_ID.test(trimmed)) return false; // Model IDs
    return true;
  }

  // Translation Queue & Fetching Engine (Chrome Extension API + MyMemory Fallback)
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
      setTimeout(function () {
        if (translationCache[text]) callback(translationCache[text]);
      }, 400);
      return;
    }

    pendingTexts.add(text);
    queue.push({ text: text, callback: callback });

    if (!batchTimer) {
      batchTimer = setTimeout(processBatch, 80);
    }
  }

  function processBatch() {
    batchTimer = null;
    if (queue.length === 0) return;

    var currentBatch = queue.splice(0, 25);
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

    function applyResult(orig, trans) {
      if (trans && trans !== orig) {
        translationCache[orig] = trans;
        persistCache();
        var cbs = batchMap.get(orig) || [];
        cbs.forEach(function (cb) { cb(trans); });
      }
      pendingTexts.delete(orig);
    }

    textsToFetch.forEach(function (text, idx) {
      setTimeout(function () {
        // Primary: Google Translate Chrome Extension endpoint (Fast, unblocked, reliable)
        var url1 = 'https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=en&tl=iw&q=' + encodeURIComponent(text);
        fetch(url1)
          .then(function (res) {
            if (!res.ok) throw new Error('status ' + res.status);
            return res.json();
          })
          .then(function (data) {
            var trans = (Array.isArray(data) && data[0]) ? data[0] : (typeof data === 'string' ? data : null);
            if (trans && trans !== text) {
              applyResult(text, trans);
            } else {
              throw new Error('empty');
            }
          })
          .catch(function () {
            // Secondary Fallback: MyMemory API
            var url2 = 'https://api.mymemory.translated.net/get?q=' + encodeURIComponent(text) + '&langpair=en|he';
            fetch(url2)
              .then(function (r) { return r.json(); })
              .then(function (d) {
                if (d && d.responseData && d.responseData.translatedText) {
                  var trans2 = d.responseData.translatedText;
                  if (trans2 && trans2 !== text && trans2.indexOf('MYMEMORY') === -1) {
                    applyResult(text, trans2);
                    return;
                  }
                }
                pendingTexts.delete(text);
              })
              .catch(function () {
                pendingTexts.delete(text);
              });
          });
      }, idx * 40);
    });
  }

  // Translate text node with React Virtual-DOM resilience
  var handledNodes = new WeakSet();

  function translateTextNode(node) {
    if (!isEnabled || handledNodes.has(node)) return;
    if (isCodeOrTechnical(node)) return;

    var parent = node.parentElement;
    if (parent && (parent.tagName === 'INPUT' || parent.tagName === 'TEXTAREA')) return;

    var original = node.nodeValue;
    if (!shouldTranslate(original)) return;

    var trimmed = original.trim();

    // Check instant cache
    if (translationCache[trimmed]) {
      var trans = translationCache[trimmed];
      node.nodeValue = original.replace(trimmed, trans);
      handledNodes.add(node);
      return;
    }

    // Queue for translation
    enqueueForTranslation(trimmed, function (translated) {
      if (node.isConnected) {
        node.nodeValue = original.replace(trimmed, translated);
        handledNodes.add(node);
      }
    });
  }

  // Translate attributes (placeholders, tooltips, aria-labels) even on inputs
  function translateAttributes(el) {
    if (!isEnabled) return;
    if (isCodeOrTechnical(el)) return;

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
    if (!node || isCodeOrTechnical(node)) return;

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

  // MutationObserver for dynamic React DOM changes & modal popups
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
