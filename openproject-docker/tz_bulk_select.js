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
  function injectBackButton() {
    var body = document.body;
    if (!body) return;

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
    if (classStr.indexOf("users_settings") !== -1) return;

    var isAvatarsSettings = classStr.indexOf("avatars") !== -1 &&
                            classStr.indexOf("admin/settings") !== -1;
    var inTarget =
      TARGETS.some(function (c) { return clsList.contains(c); }) ||
      isAvatarsSettings;
    if (!inTarget) return;

    // Index pages already have their own toolbar (Filter + Action button)
    // so they don't need a back button. Also exclude the permissions
    // report page (controller-roles + action-report) — the user
    // doesn't want a back button on it.
    if (clsList.contains("action-index")) return;
    if (clsList.contains("controller-roles") && clsList.contains("action-report")) return;

    var header = document.querySelector(".PageHeader");
    if (!header) return;
    if (header.querySelector(".tz-back-btn")) return; // idempotent

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
  }

  function bootstrap() {
    init();
    injectBackButton();
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
