/* ================================================================
   OPENPROJECT CUSTOM JS
   ----------------------------------------------------------------
   File   : openproject-docker/openproject-custom.js
   Served : /app/public/custom-redesign.js  (bind-mounted volume)
   Loaded : <script src="/custom-redesign.js" defer> injected by
            css_injector.rb middleware.

   Adds a "Reset" button to the filter panel that clears every
   active filter + the search text in one click.
   ================================================================ */

(function () {
  'use strict';

  /* Marker log — open DevTools Console; if you do NOT see this line,
     the JS file is not being injected (restart the container). */
  try { console.log('[op-custom] custom-redesign.js loaded'); } catch (e) {}

  var RESET_BTN_CLASS = 'op-custom-reset-filters';
  var RESET_BTN_SELECTOR = '.' + RESET_BTN_CLASS;
  var TOOLBAR_CLASS = 'op-custom-filter-toolbar';

  function clearSearchInput(container) {
    var inputs = container.querySelectorAll('#filter_search input');
    inputs.forEach(function (input) {
      if (!input || input.type === 'hidden') return;
      if (!input.value) return;
      try {
        var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
        if (nativeSetter) nativeSetter.call(input, ''); else input.value = '';
      } catch (e) { input.value = ''; }
      input.dispatchEvent(new Event('input',  { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
      input.dispatchEvent(new Event('blur',   { bubbles: true }));
    });
  }

  /* Remove filters one at a time. Each click destroys an Angular component,
     so we wait a tick and re-query before the next click — clicking detached
     elements silently no-ops. Safety cap to avoid any infinite loop. */
  function removeFiltersSequentially(container, done) {
    var safety = 50;
    function step() {
      if (--safety <= 0) return done && done();
      var btn = container.querySelector('.advanced-filters--remove-filter button');
      if (!btn) return done && done();
      try { btn.click(); } catch (e) { /* swallow */ }
      setTimeout(step, 40);
    }
    step();
  }

  function closeFilterPanel(container) {
    /* Try the native close button first (Angular's (clicked)="closeFilter()"). */
    var closeBtn =
      container.querySelector('.advanced-filters--close button') ||
      container.querySelector('.advanced-filters--close') ||
      container.querySelector('primer-icon-button.advanced-filters--close');
    if (closeBtn) {
      try { closeBtn.click(); return; } catch (e) { /* fall through */ }
    }
    /* Fallback: click the top-toolbar Filter trigger to toggle visibility. */
    var trigger = document.querySelector('.advanced-filters--toggle, [data-test-selector="wp-filter-button"]');
    if (trigger) {
      try { trigger.click(); } catch (e) { /* ignore */ }
    }
  }

  function resetAllFilters(container) {
    removeFiltersSequentially(container, function () {
      clearSearchInput(container);
      /* Give Angular a moment to flush the last value-clear before closing. */
      setTimeout(function () { closeFilterPanel(container); }, 60);
    });
  }

  var ICON_SVG =
    '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true" focusable="false">' +
    '<path fill="currentColor" d="M8 3V1L4.5 4 8 7V5a3 3 0 1 1-3 3H3.5A4.5 4.5 0 1 0 8 3z"/>' +
    '</svg>';

  function buildResetButton(container) {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = RESET_BTN_CLASS;
    btn.setAttribute('title', 'Clear all filters');
    btn.setAttribute('aria-label', 'Reset all filters');
    btn.innerHTML = ICON_SVG + '<span class="op-custom-reset-filters--label">Reset</span>';
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      if (btn.classList.contains('is-empty')) return;
      btn.classList.add('is-resetting');
      resetAllFilters(container);
      setTimeout(function () { btn.classList.remove('is-resetting'); }, 600);
    });
    return btn;
  }

  /* Has anything to reset? — any filter row OR any value in the search input. */
  function hasActiveFilters(container) {
    if (container.querySelector('.advanced-filters--remove-filter button')) return true;
    var searchInputs = container.querySelectorAll('#filter_search input');
    for (var i = 0; i < searchInputs.length; i++) {
      if (searchInputs[i].type !== 'hidden' && searchInputs[i].value) return true;
    }
    return false;
  }

  function refreshResetButtonState(container) {
    var btn = container.querySelector(RESET_BTN_SELECTOR);
    if (!btn) return;
    btn.classList.toggle('is-empty', !hasActiveFilters(container));
  }

  function injectResetButton(container) {
    if (!container) return;
    if (container.querySelector(RESET_BTN_SELECTOR)) {
      refreshResetButtonState(container);
      return;
    }

    /* Build a normal-flow toolbar at the TOP of the panel so the button is
       always visible — no off-screen risk like absolute positioning. */
    var toolbar = document.createElement('div');
    toolbar.className = TOOLBAR_CLASS;

    var btn = buildResetButton(container);
    toolbar.appendChild(btn);

    /* Insert before the filter list so it appears at the top of the panel. */
    var firstChild = container.firstElementChild;
    if (firstChild) container.insertBefore(toolbar, firstChild);
    else container.appendChild(toolbar);

    refreshResetButtonState(container);

    /* Watch this panel — show/hide Reset as filters and search-text change. */
    var localObs = new MutationObserver(function () { refreshResetButtonState(container); });
    localObs.observe(container, { childList: true, subtree: true });
    container.addEventListener('input',  function () { refreshResetButtonState(container); });
    container.addEventListener('change', function () { refreshResetButtonState(container); });

    try { console.log('[op-custom] Reset button injected into filter panel', container); } catch (e) {}
  }

  function scanAndInject(root) {
    var containers = (root || document).querySelectorAll('.advanced-filters--container');
    containers.forEach(injectResetButton);
  }

  var observer = new MutationObserver(function (mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var m = mutations[i];
      for (var j = 0; j < m.addedNodes.length; j++) {
        var node = m.addedNodes[j];
        if (node.nodeType !== 1) continue;
        if (node.matches && node.matches('.advanced-filters--container')) {
          injectResetButton(node);
        } else if (node.querySelectorAll) {
          scanAndInject(node);
        }
      }
    }
  });

  function start() {
    scanAndInject(document);
    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
