// Bulk-selection behaviour for the Users admin index table.
//
// Wires:
//   - Master checkbox in <thead> ↔ all per-row .tz-user-checkbox boxes
//   - Indeterminate state on master when some (not all) rows are selected
//   - Exposes selected IDs on window.tzUserSelection (array of strings)
//   - Fires a CustomEvent("tz:selection-change", { detail: ids }) on document
//     so future bulk-action UI can subscribe without reading globals.
//
// Loaded on every HTML page via css_injector.rb; the init() body returns
// early on pages that aren't the Users index, so cost on other pages is
// effectively zero.

(function () {
  "use strict";

  function init() {
    var body = document.body;
    if (!body) return;
    if (!body.classList.contains("controller-users")) return;
    if (!body.classList.contains("action-index")) return;

    var master = document.querySelector("input.tz-master-checkbox");
    var boxes = Array.prototype.slice.call(
      document.querySelectorAll("input.tz-user-checkbox")
    );

    if (!master || boxes.length === 0) return;

    function selectedIds() {
      return boxes
        .filter(function (b) { return b.checked; })
        .map(function (b) { return b.value; });
    }

    function publishSelection() {
      var ids = selectedIds();
      window.tzUserSelection = ids;
      document.dispatchEvent(
        new CustomEvent("tz:selection-change", { detail: ids })
      );
    }

    function syncMaster() {
      var checkedCount = boxes.filter(function (b) { return b.checked; }).length;
      master.checked = checkedCount > 0 && checkedCount === boxes.length;
      master.indeterminate = checkedCount > 0 && checkedCount < boxes.length;
    }

    master.addEventListener("change", function () {
      var shouldCheck = master.checked;
      boxes.forEach(function (b) { b.checked = shouldCheck; });
      master.indeterminate = false;
      publishSelection();
    });

    boxes.forEach(function (b) {
      b.addEventListener("change", function () {
        syncMaster();
        publishSelection();
      });
    });

    // Initial state
    syncMaster();
    publishSelection();
  }

  // Inject a "← Back" button into the PageHeader on any admin sub-page
  // under Users-and-Permissions (new/edit/show of users, placeholder
  // users, groups, roles; the permissions report; and the avatars
  // settings page). OpenProject's PageHeader has breadcrumbs but no
  // back button — this adds one that calls history.back() (with a
  // sensible fallback URL per controller). Styled by section 15 of
  // the CSS (`button.tz-back-btn`).
  //
  // Returns true when the work is finished (button injected, already
  // present, or this page isn't a target). Returns false when we need
  // to retry — body or .PageHeader isn't in the DOM yet. The bootstrap
  // observer below keeps retrying until this returns true (or times out).
  function injectBackButton() {
    var body = document.body;
    if (!body) return false; // DOM not ready — keep watching

    // Which controllers should get the Back button.
    // Avatars pages have slashes in their class name (e.g.
    // controller-admin/settings/avatars), so we substring-match
    // "avatars". User Settings was deliberately excluded — the
    // user doesn't want the back button there.
    var TARGETS = [
      "controller-users",
      "controller-placeholder_users",
      "controller-groups",
      "controller-roles",
      "controller-avatars"
    ];
    var clsList = body.classList;
    var classStr = body.className;
    // Bail out early if this is the user-settings admin page — it
    // contains both "admin/settings" and "users_settings" in the
    // class but the user doesn't want a back button there.
    if (classStr.indexOf("users_settings") !== -1) return true;

    var isAvatarsSettings = classStr.indexOf("avatars") !== -1 &&
                            classStr.indexOf("admin/settings") !== -1;
    var inTarget =
      TARGETS.some(function (c) { return clsList.contains(c); }) ||
      isAvatarsSettings;
    if (!inTarget) return true; // not a target page — stop watching

    // Index pages already have their own toolbar (Filter + Action button)
    // so they don't need a back button. Also exclude the permissions
    // report page (controller-roles + action-report) — the user
    // doesn't want a back button on it.
    if (clsList.contains("action-index")) return true;
    if (clsList.contains("controller-roles") && clsList.contains("action-report")) return true;

    var header = document.querySelector(".PageHeader");
    if (!header) return false; // PageHeader not rendered yet — keep watching
    if (header.querySelector(".tz-back-btn")) return true; // idempotent

    // Fallback destination per controller — used only when the browser
    // has no history (e.g. page opened directly in a new tab).
    var fallback = "/admin";
    if (isAvatarsSettings) fallback = "/admin/users/avatars";
    else if (clsList.contains("controller-users")) fallback = "/users";
    else if (clsList.contains("controller-placeholder_users")) fallback = "/placeholder_users";
    else if (clsList.contains("controller-groups")) fallback = "/groups";
    else if (clsList.contains("controller-roles")) fallback = "/roles";

    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "tz-back-btn";
    btn.setAttribute("aria-label", "Back");
    btn.innerHTML =
      '<span class="tz-back-arrow" aria-hidden="true">←</span> Back';
    btn.addEventListener("click", function () {
      if (window.history.length > 1) {
        window.history.back();
      } else {
        window.location.href = fallback;
      }
    });

    header.appendChild(btn);
    return true;
  }

  // Holds the MutationObserver that retries injectBackButton() when the
  // PageHeader is rendered asynchronously after bootstrap fires. Tracked
  // at module scope so each turbo navigation can tear down the previous
  // one before starting a fresh watch.
  var pageHeaderObserver = null;
  var pageHeaderObserverTimer = null;

  function stopWatching() {
    if (pageHeaderObserver) {
      pageHeaderObserver.disconnect();
      pageHeaderObserver = null;
    }
    if (pageHeaderObserverTimer) {
      clearTimeout(pageHeaderObserverTimer);
      pageHeaderObserverTimer = null;
    }
  }

  function bootstrap() {
    init();

    // Tear down any retry watcher left over from the previous page.
    stopWatching();

    if (injectBackButton()) return;

    // PageHeader wasn't in the DOM yet — OpenProject renders it after
    // turbo:render in some flows. Watch the body subtree and retry on
    // each mutation until injectBackButton() reports done.
    pageHeaderObserver = new MutationObserver(function () {
      if (injectBackButton()) stopWatching();
    });
    pageHeaderObserver.observe(document.body, { childList: true, subtree: true });

    // Safety net — stop after 10s even if PageHeader never shows up,
    // so we don't leak a forever-running observer on pages where the
    // header simply doesn't exist.
    pageHeaderObserverTimer = setTimeout(stopWatching, 10000);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap);
  } else {
    bootstrap();
  }

  // OpenProject uses Turbo — navigation between pages replaces the
  // DOM without firing DOMContentLoaded. Re-run on every Turbo
  // page-load and render so the back button gets injected.
  document.addEventListener("turbo:load", bootstrap);
  document.addEventListener("turbo:render", bootstrap);
})();
