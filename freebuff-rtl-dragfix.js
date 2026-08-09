/* freebuff-rtl-dragfix */
/* ==========================================================================
 * Freebuff Desktop — RTL drag-direction fix (v1)
 * --------------------------------------------------------------------------
 * The app's explorer resize math is hardcoded for LTR:
 *     newWidth = startWidth + startX - clientX      (drag left = wider)
 * With the panel mirrored to the left side in RTL, that direction is
 * inverted. This shim flips `clientX` on pointer events that begin on the
 * resize handle, so the same formula behaves correctly for RTL:
 *     drag right = wider, drag left = narrower
 *
 * It runs in the document CAPTURE phase — before React reads the event —
 * and only touches events that started on `.explorer-resize-handle`, so all
 * other pointer logic in the app is untouched.
 *
 * Distributed three ways:
 *   1. apply-rtl.bat injects this file's content into index.html (wrapped
 *      in <script> tags) — the one-click method.
 *   2. freebuff-rtl.js appends the same code — the DevTools / CDP launcher
 *      paths.
 *   3. Free to paste directly in DevTools for a quick test.
 *
 * Safe to run more than once (idempotent) and no-op when no resize handle
 * exists.
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
