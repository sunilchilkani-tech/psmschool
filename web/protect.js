// Basic copy protection + custom App Zoom shortcuts for the web app.
// - Normal mouse wheel scrolling passes straight through to Flutter.
// - Ctrl + Mouse Scroll Wheel zooms in / out inside the Flutter app.
// - Ctrl + '+' / '=' zooms in, Ctrl + '-' zooms out, Ctrl + '0' resets to 100%.
(function () {
  'use strict';

  function isEditable(el) {
    if (!el) return false;
    var tag = (el.tagName || '').toLowerCase();
    return tag === 'input' || tag === 'textarea' || el.isContentEditable === true ||
      (el.closest && el.closest('flt-text-editing-host, [contenteditable="true"]') !== null);
  }

  // No context menu anywhere (it also offers "Inspect" / "View source").
  // Copy and paste still work with Ctrl+C / Ctrl+V.
  function blockMenu(e) {
    e.preventDefault();
    e.stopPropagation();
    return false;
  }
  window.addEventListener('contextmenu', blockMenu, true);
  document.addEventListener('contextmenu', blockMenu, true);

  if (!window.__psmZoomHookInstalled) {
    window.__psmZoomHookInstalled = true;

    // 1. Ctrl + Mouse Wheel Zoom ONLY (normal scrolling without Ctrl is untouched)
    window.addEventListener('wheel', function (e) {
      if (!(e.ctrlKey || e.metaKey)) {
        return; // Normal scroll wheel: do NOT zoom, let page scroll normally
      }
      e.preventDefault();
      e.stopPropagation();
      var dy = e.deltaY || 0;
      if (Math.abs(dy) < 0.01) return;
      window.postMessage(dy < 0 ? 'PSM_ZOOM_IN_WHEEL' : 'PSM_ZOOM_OUT_WHEEL', '*');
    }, { capture: true, passive: false });

    // 2. Ctrl + (+ / = / NumpadAdd), Ctrl + (- / _ / NumpadSubtract), Ctrl + 0
    window.addEventListener('keydown', function (e) {
      var ctrl = e.ctrlKey || e.metaKey;
      if (!ctrl || e.altKey) return;
      var key = e.key || '';
      var code = e.code || '';

      if (key === '+' || key === '=' || code === 'Equal' || code === 'NumpadAdd') {
        e.preventDefault();
        e.stopPropagation();
        window.postMessage('PSM_ZOOM_IN_KEY', '*');
        return false;
      }
      if (key === '-' || key === '_' || code === 'Minus' || code === 'NumpadSubtract') {
        e.preventDefault();
        e.stopPropagation();
        window.postMessage('PSM_ZOOM_OUT_KEY', '*');
        return false;
      }
      if (key === '0' || code === 'Digit0' || code === 'Numpad0') {
        e.preventDefault();
        e.stopPropagation();
        window.postMessage('PSM_ZOOM_RESET_KEY', '*');
        return false;
      }
    }, { capture: true, passive: false });
  }

  document.addEventListener('keydown', function (e) {
    var key = (e.key || '').toLowerCase();
    var ctrl = e.ctrlKey || e.metaKey;
    var blocked =
      key === 'f12' ||
      (ctrl && (key === 's' || key === 'u')) ||
      (e.shiftKey && key === 'f10') ||
      key === 'contextmenu' ||
      (ctrl && e.shiftKey && (key === 'i' || key === 'j' || key === 'c' || key === 'k')) ||
      (e.metaKey && e.altKey && (key === 'i' || key === 'j' || key === 'c' || key === 'u'));
    if (blocked) {
      e.preventDefault();
      e.stopPropagation();
      return false;
    }
  }, true);

  document.addEventListener('dragstart', function (e) {
    if (!isEditable(e.target)) e.preventDefault();
  }, true);

  document.addEventListener('selectstart', function (e) {
    if (!isEditable(e.target)) e.preventDefault();
  }, true);

  // Refuse to run inside another site's frame (click-jacking / copying).
  try {
    if (window.top !== window.self) {
      window.top.location = window.self.location.href;
    }
  } catch (_) {
    document.documentElement.style.display = 'none';
  }
})();
