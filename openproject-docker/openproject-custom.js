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


/* ================================================================
   WORK-PACKAGE TABLE LAYOUT FIX
   ----------------------------------------------------------------
   OpenProject's WP table is an Angular component that writes
   column widths to inline styles with high specificity — CSS
   !important rules don't always win. Worse, there's often a
   leading hidden hierarchy/select column, so :nth-child(N) in CSS
   targets the WRONG visual column.

   This script identifies columns by data-property-name (the OP
   semantic attribute), header text, or class, and forces the right
   width onto BOTH the <col> AND the <th>/<td> via setProperty
   with 'important' priority — which is the only way to beat
   inline !important set by JS. It also kills the reserved
   hierarchy indent so Subject titles sit flush-left.

   Re-runs on DOM mutations to survive Angular re-renders.
   ================================================================ */
(function () {
  'use strict';

  var COL_WIDTH_PX = {
    id: 70,
    subject: 380,
  };

  function identifyColumn(th) {
    var data = th.getAttribute('data-property-name') ||
               th.getAttribute('data-column-name') ||
               th.getAttribute('data-attribute');
    if (data) return data.toLowerCase().replace(/[^a-z]/g, '');

    var cls = (th.className || '').toLowerCase();
    var known = ['id', 'subject', 'type', 'status', 'assignee', 'priority'];
    for (var i = 0; i < known.length; i++) {
      if (cls.indexOf(known[i]) !== -1) return known[i];
    }

    var text = (th.textContent || '').trim().toLowerCase();
    if (known.indexOf(text) !== -1) return text;
    return null;
  }

  function lockWidth(el, w) {
    el.style.setProperty('width', w + 'px', 'important');
    el.style.setProperty('min-width', w + 'px', 'important');
    el.style.setProperty('max-width', w + 'px', 'important');
    el.style.setProperty('box-sizing', 'border-box', 'important');
  }

  function flushLeft(el) {
    el.style.setProperty('text-align', 'left', 'important');
    el.style.setProperty('justify-content', 'flex-start', 'important');
  }

  function killHierarchyIndent(el) {
    var cls = (el.className || '');
    if (typeof cls !== 'string') return;
    if (cls.indexOf('hierarchy') !== -1 || cls.indexOf('indicator') !== -1) {
      el.style.setProperty('padding-left', '0', 'important');
      el.style.setProperty('margin-left', '0', 'important');
    }
  }

  /* --- Status / Priority pill palette ----------------------------- */
  var NEUTRAL_PILL = { bg: '#f3f4f6', fg: '#1f2937', border: '#e5e7eb' };
  var STATUS_COLORS = [
    { match: 'in progress',     bg: '#fef3c7', fg: '#b45309', border: '#fde68a' },
    { match: 'in specification',bg: '#fef3c7', fg: '#b45309', border: '#fde68a' },
    { match: 'to be scheduled', bg: '#fef9c3', fg: '#a16207', border: '#fde68a' },
    { match: 'on hold',         bg: '#ffedd5', fg: '#c2410c', border: '#fed7aa' },
    { match: 'closed',          bg: '#dcfce7', fg: '#15803d', border: '#bbf7d0' },
    { match: 'resolved',        bg: '#dcfce7', fg: '#15803d', border: '#bbf7d0' },
    { match: 'done',            bg: '#dcfce7', fg: '#15803d', border: '#bbf7d0' },
    { match: 'developed',       bg: '#dcfce7', fg: '#15803d', border: '#bbf7d0' },
    { match: 'scheduled',       bg: '#ecfccb', fg: '#4d7c0f', border: '#d9f99d' },
    { match: 'rejected',        bg: '#fee2e2', fg: '#b91c1c', border: '#fecaca' },
    { match: 'opened',          bg: '#fee2e2', fg: '#b91c1c', border: '#fecaca' },
    { match: 'reopened',        bg: '#cffafe', fg: '#0891b2', border: '#a5f3fc' },
    { match: 'new',             bg: '#cffafe', fg: '#0e7490', border: '#a5f3fc' },
    { match: 'open',            bg: '#cffafe', fg: '#0e7490', border: '#a5f3fc' },
  ];
  var PRIORITY_COLORS = [
    { match: 'immediate', bg: '#fee2e2', fg: '#b91c1c', border: '#fecaca' },
    { match: 'high',      bg: '#ffedd5', fg: '#c2410c', border: '#fed7aa' },
    { match: 'normal',    bg: '#dbeafe', fg: '#1d4ed8', border: '#bfdbfe' },
    { match: 'low',       bg: '#f1f5f9', fg: '#475569', border: '#e2e8f0' },
  ];

  function pickColor(text, palette) {
    var t = (text || '').toLowerCase().trim();
    for (var i = 0; i < palette.length; i++) {
      if (t.indexOf(palette[i].match) !== -1) return palette[i];
    }
    return NEUTRAL_PILL;
  }

  function findPillTarget(cell) {
    // Prefer .op-status / .op-priority wrappers; fall back to first
    // non-empty inline child; if nothing, style the cell itself.
    var t = cell.querySelector('.op-status, .op-priority, op-status, op-priority');
    if (t) return t;
    var children = cell.children;
    for (var i = 0; i < children.length; i++) {
      var c = children[i];
      if ((c.textContent || '').trim().length > 0) return c;
    }
    return cell;
  }

  function applyPill(cell, color) {
    var target = findPillTarget(cell);
    target.style.setProperty('display', 'inline-flex', 'important');
    target.style.setProperty('align-items', 'center', 'important');
    target.style.setProperty('gap', '6px', 'important');
    target.style.setProperty('padding', '4px 12px', 'important');
    target.style.setProperty('border-radius', '999px', 'important');
    target.style.setProperty('background-color', color.bg, 'important');
    target.style.setProperty('color', color.fg, 'important');
    target.style.setProperty('border', '1px solid ' + color.border, 'important');
    target.style.setProperty('font-weight', '600', 'important');
    target.style.setProperty('font-size', '12.5px', 'important');
    target.style.setProperty('line-height', '1.2', 'important');
    target.style.setProperty('white-space', 'nowrap', 'important');
    target.style.setProperty('text-transform', 'none', 'important');
    target.style.setProperty('letter-spacing', '0', 'important');

    // The colored OP dot becomes redundant inside the colored pill;
    // hide it so the pill reads cleanly.
    var dots = target.querySelectorAll(
      '.op-status--dot, .op-priority--dot, [class*="--dot"]'
    );
    for (var i = 0; i < dots.length; i++) {
      dots[i].style.setProperty('display', 'none', 'important');
    }
  }

  function fixTable(table) {
    var headerRow = table.querySelector('thead tr');
    if (!headerRow) return;

    var ths = headerRow.querySelectorAll('th');
    var cols = table.querySelectorAll('colgroup col');

    for (var i = 0; i < ths.length; i++) {
      var th = ths[i];
      var name = identifyColumn(th);
      var w = name ? COL_WIDTH_PX[name] : null;

      if (w) {
        lockWidth(th, w);
        if (cols[i]) lockWidth(cols[i], w);
      }
      if (name === 'subject') flushLeft(th);

      // Body cells in this column
      var tdSelector = 'tbody tr td:nth-child(' + (i + 1) + ')';
      var tds = table.querySelectorAll(tdSelector);
      for (var j = 0; j < tds.length; j++) {
        var td = tds[j];
        if (w) lockWidth(td, w);

        if (name === 'subject') {
          flushLeft(td);
          td.style.setProperty('padding-left', '18px', 'important');
          var descendants = td.querySelectorAll('*');
          for (var k = 0; k < descendants.length; k++) {
            flushLeft(descendants[k]);
            killHierarchyIndent(descendants[k]);
          }
        } else if (name === 'status') {
          applyPill(td, pickColor(td.textContent, STATUS_COLORS));
        } else if (name === 'priority') {
          applyPill(td, pickColor(td.textContent, PRIORITY_COLORS));
        }
      }
    }
  }

  function fixAllTables() {
    var tables = document.querySelectorAll('table.work-package-table');
    for (var i = 0; i < tables.length; i++) fixTable(tables[i]);
  }

  var pending = false;
  function scheduleFix() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function () {
      pending = false;
      fixAllTables();
    });
  }

  var observer = new MutationObserver(function (mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var m = mutations[i];
      if (m.type !== 'childList') continue;
      for (var j = 0; j < m.addedNodes.length; j++) {
        var node = m.addedNodes[j];
        if (node.nodeType !== 1) continue;
        if (node.matches && (
            node.matches('table.work-package-table') ||
            node.matches('tr') ||
            node.matches('td') ||
            node.matches('col'))) {
          scheduleFix();
          return;
        }
        if (node.querySelector && node.querySelector('table.work-package-table, table.work-package-table tr')) {
          scheduleFix();
          return;
        }
      }
    }
  });

  function start() {
    fixAllTables();
    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();


/* ================================================================
   PLACEHOLDER INJECTOR — Work / Remaining work / % Complete
   ----------------------------------------------------------------
   These fields are inline-edit controls. In the create panels
   (full-create + split-create) they immediately render as
   <input> elements where Angular sets the value to "-" for empty
   state. We:
     1. Strip the "-" value using the native HTMLInputElement setter
        (bypasses Angular's value descriptor)
     2. Dispatch input/change events so the form knows the field is
        empty (otherwise Angular will reset "-")
     3. Set a native `placeholder` attribute as the visible hint
     4. Run on DOM mutations + a 500ms interval for the first 30s
        so newly-rendered inputs are caught even if mutation events
        don't fire (Angular sometimes batches with no childList add)
   ================================================================ */
(function () {
  'use strict';

  try { console.log('[op-custom] placeholder-injector v2 loaded — ' + new Date().toISOString()); } catch (e) {}

  var PLACEHOLDERS = {
    'estimatedTime':       'Enter work (e.g. 8h, 1d)',
    'storyPoints':         'Enter work (e.g. 8h, 1d)',
    'remainingTime':       'Enter remaining work (e.g. 4h)',
    'percentageDone':      'Enter % complete (0 - 100)',
    'derivedEstimatedTime':'Auto-calculated work',
    'derivedRemainingTime':'Auto-calculated remaining'
  };

  // Native value setter (bypasses Angular's value property override)
  var nativeInputValueSetter = null;
  try {
    nativeInputValueSetter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, 'value'
    ).set;
  } catch (e) {}

  function clearValue(el) {
    if (!el) return;
    try {
      if (nativeInputValueSetter) nativeInputValueSetter.call(el, '');
      else el.value = '';
      el.dispatchEvent(new Event('input',  { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    } catch (e) { try { el.value = ''; } catch (e2) {} }
  }

  function applyTo(root) {
    if (!root || !root.querySelectorAll) return 0;
    var found = 0;
    Object.keys(PLACEHOLDERS).forEach(function (fieldName) {
      var hint = PLACEHOLDERS[fieldName];
      var selector = 'input[id*="' + fieldName + '" i], textarea[id*="' + fieldName + '" i], .' + fieldName + ' input, .' + fieldName + ' textarea';

      try {
        var els = root.querySelectorAll(selector);
        if (els.length) {
          try { console.log('[op-custom] placeholder-injector: found ' + els.length + ' element(s) for "' + fieldName + '"'); } catch (e) {}
        }
        els.forEach(function (el) {
          // set placeholder if missing
          if (!el.getAttribute('placeholder') || el.getAttribute('placeholder') === '-') {
            el.setAttribute('placeholder', hint);
            found++;
            try { console.log('[op-custom] set placeholder on', el); } catch (e) {}
          }
          // clear "-" value (Angular often puts this for empty)
          if (el.value === '-' || el.value === ' - ') {
            clearValue(el);
          }
        });
      } catch (e) {
        try { console.warn('[op-custom] selector error for', fieldName, e); } catch (e2) {}
      }
    });
    return found;
  }

  function startPlaceholderInjector() {
    applyTo(document);

    // Mutation observer for dynamic renders
    try {
      var observer = new MutationObserver(function (mutations) {
        mutations.forEach(function (m) {
          m.addedNodes.forEach(function (n) {
            if (n.nodeType === 1) applyTo(n);
          });
          // also re-scan when attributes change (Angular reactive updates)
          if (m.type === 'attributes' && m.target && m.target.nodeType === 1) {
            applyTo(m.target.parentNode || m.target);
          }
        });
      });
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['value', 'id', 'placeholder']
      });
    } catch (e) {}

    // Belt-and-braces: poll every 500ms for the first 30s so we catch
    // anything the observer misses (Angular sometimes patches values
    // without firing childList mutations).
    var ticks = 0;
    var iv = setInterval(function () {
      applyTo(document);
      if (++ticks >= 60) clearInterval(iv);
    }, 500);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startPlaceholderInjector);
  } else {
    startPlaceholderInjector();
  }
})();
