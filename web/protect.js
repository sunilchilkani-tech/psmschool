// Basic copy protection for the web app.
// Blocks the right-click / keyboard context menu everywhere (text fields
// included), "save page", "view source", developer-tools shortcuts,
// dragging and text selection outside form fields. Printing (Ctrl+P),
// copy (Ctrl+C), paste (Ctrl+V) and typing keep working.
// Note: no web page can fully stop a determined person (or a browser
// extension) from inspecting what the browser downloads; this removes the
// easy ways and the release build is already minified and obfuscated.
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
