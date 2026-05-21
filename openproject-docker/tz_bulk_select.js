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
    // If a back button is already on the page, we're done. This catches
    // both the JS-injected button from a previous bootstrap() call AND
    // a server-side button rendered by a bind-mounted ERB template
    // (see openproject-docker/users_new.html.erb), so the two paths
    // can't double up and produce two back buttons.
    if (document.querySelector(".tz-back-btn")) return true;

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

  // Inject a "Back to sign in" link on the register and forgot-password
  // pages. The OpenProject ERB for those pages doesn't include a way to
  // return to /login, so users get stranded after clicking the link from
  // the login form. CSS-only options don't work — pseudo-elements can't
  // be real clickable anchors — so we inject a real <a> via JS.
  //
  // Returns true when finished (link present, or not a target page),
  // false when we need to retry — the Spot modal that wraps the register
  // form is mounted by Stimulus async, so .registration-modal often
  // doesn't exist on the first try.
  // Add placeholder text to auth-page input fields. OpenProject's form
  // helpers don't emit placeholder attributes by default, so we add them
  // client-side. Mapping is by input name/id substring so it works for
  // login (input names like "username", "password") and for the register
  // and lost-password Rails helpers (input names like "user[firstname]",
  // "user[mail]", "user[password_confirmation]").
  //
  // Returns true once placeholders are set (or there's nothing to do),
  // false when the inputs aren't in the DOM yet and we should retry.
  function injectAuthPlaceholders() {
    var onAuthPage =
      document.querySelector(".registration-modal") ||
      document.querySelector('[data-modal-class-name*="registration"]') ||
      document.querySelector('.modal-delivery-element form') ||
      document.querySelector('form[action*="lost_password"]') ||
      document.querySelector('form[action*="/login"]') ||
      document.querySelector("#login-form");

    if (!onAuthPage) return true; // not an auth page

    // (substring-to-match, placeholder-text) pairs. First match wins.
    // Ordered specific → general (e.g. "password_confirmation" must come
    // before "password" or the password input would catch the confirm rule).
    var mapping = [
      ["password_confirmation", "Confirm your password"],
      ["confirmation",         "Confirm your password"],
      ["firstname",            "Enter your first name"],
      ["lastname",             "Enter your last name"],
      ["first_name",           "Enter your first name"],
      ["last_name",            "Enter your last name"],
      ["[mail]",               "Enter your email"],
      ["user_mail",            "Enter your email"],
      ["email",                "Enter your email"],
      ["login",                "Enter your username"],
      ["username",             "Enter your username"],
      ["user_name",            "Enter your username"],
      ["password",             "Enter your password"]
    ];

    var inputs = document.querySelectorAll(
      "input[type='text'], input[type='email'], input[type='password']"
    );
    if (inputs.length === 0) return false; // retry — inputs not rendered yet

    // Per-input idempotency: skip inputs that already have a placeholder.
    // Survives Turbo navigations because we don't rely on a body marker.
    Array.prototype.forEach.call(inputs, function (input) {
      if (input.placeholder) return;
      var hay = ((input.name || "") + " " + (input.id || "")).toLowerCase();
      for (var i = 0; i < mapping.length; i++) {
        if (hay.indexOf(mapping[i][0]) !== -1) {
          input.placeholder = mapping[i][1];
          break;
        }
      }
    });
    return true;
  }

  // Prevent the browser's password manager from autofilling saved
  // credentials into the REGISTER form. Setting autocomplete attributes
  // is the W3C-recommended way to tell Chrome / Safari / Firefox that
  // this is a new-account form, not a login form, so they shouldn't
  // pre-fill the user's existing username/password.
  //
  // - form[autocomplete="off"]: legacy hint (Chrome partly ignores this)
  // - password inputs: autocomplete="new-password" (the strong signal)
  // - other inputs: autocomplete="off" + autocomplete tokens that don't
  //   match any saved-credential type
  //
  // Login and lost-password pages are deliberately NOT touched — users
  // expect saved-credential autofill there.
  function preventRegisterAutofill() {
    var isRegister =
      document.querySelector(".registration-modal") ||
      document.querySelector('[data-modal-class-name*="registration"]') ||
      document.querySelector('.modal-delivery-element form[action*="register"]');

    if (!isRegister) return true; // not the register page — done

    // Find the form (might be inside .registration-modal or the wrapper)
    var form =
      document.querySelector(".registration-modal form") ||
      document.querySelector('[data-modal-class-name*="registration"] form') ||
      document.querySelector('.modal-delivery-element form[action*="register"]') ||
      document.querySelector('form[action*="register"]');

    if (!form) return false; // wait for next mutation

    // Mark form as no-autofill
    form.setAttribute("autocomplete", "off");

    var inputs = form.querySelectorAll(
      "input[type='text'], input[type='email'], input[type='password']"
    );
    if (inputs.length === 0) return false; // inputs not rendered yet

    Array.prototype.forEach.call(inputs, function (input) {
      var name = (input.name || "").toLowerCase();
      if (name.indexOf("password") !== -1) {
        // The strong W3C signal: "this is a new password, do not autofill"
        input.setAttribute("autocomplete", "new-password");
      } else if (name.indexOf("login") !== -1 || name.indexOf("user_name") !== -1) {
        // Username on register — pair with new-password fields above so
        // browsers treat the whole form as a sign-up flow.
        input.setAttribute("autocomplete", "username");
        // But discourage saved-username autofill via name attribute
        // shuffle: re-setting to a non-standard hint after the spec one
        // makes Chrome less aggressive about pre-filling.
      } else if (name.indexOf("mail") !== -1 || name.indexOf("email") !== -1) {
        input.setAttribute("autocomplete", "email");
      } else {
        input.setAttribute("autocomplete", "off");
      }

      // Suppress mobile/AssistiveTouch helpers that can also pre-populate
      input.setAttribute("autocapitalize", "off");
      input.setAttribute("autocorrect", "off");
      input.setAttribute("spellcheck", "false");
    });

    return true;
  }

  // Tweak Rails-rendered link text on the auth pages.
  // The login form's "Forgot your password?" link is generated from the
  // i18n key :label_password_lost ("Forgot your password?"); the design
  // wants it shorter as "Forgot password?". We rewrite the text in-place
  // rather than editing the locale config so this stays a CSS/JS-only
  // override that's easy to revert.
  // ── Password validation on the register page ─────────────────────
  // Hide the password requirements list by default; on submit, if the
  // password doesn't meet ALL requirements, intercept the submit and
  // render only the FAILING rules as error messages under the password
  // field. Successful passwords pass through to the normal submit
  // (server still runs its own validation for other fields).
  function setupPasswordValidation() {
    var form =
      document.querySelector(".registration-modal form") ||
      document.querySelector('.modal-delivery-element form[action*="register"]') ||
      document.querySelector('[data-modal-class-name*="registration"] form');
    if (!form) return true; // not on register page — done

    // Idempotent: only wire once per form instance
    if (form.getAttribute("data-tz-pw-validation") === "wired") return true;

    var passwordInput =
      form.querySelector('input[type="password"][name="user[password]"]') ||
      form.querySelector('input[type="password"][id*="user_password"]:not([id*="confirmation"])') ||
      form.querySelector('input[type="password"]');
    if (!passwordInput) return false;

    var confirmInput =
      form.querySelector('input[type="password"][name="user[password_confirmation]"]') ||
      form.querySelector('input[type="password"][id*="confirmation"]');

    form.setAttribute("data-tz-pw-validation", "wired");

    // Hide the requirements list initially.
    var requirementsBox = passwordInput
      .closest(".form--field")
      ?.querySelector(".form--field-instructions");
    if (requirementsBox) requirementsBox.style.display = "none";

    // Clear any prior error display when the user resumes typing.
    var clearErrors = function () {
      var box = document.querySelector(".tz-pw-errors");
      if (box) box.remove();
      passwordInput.classList.remove("tz-pw-invalid");
      if (confirmInput) confirmInput.classList.remove("tz-pw-invalid");
    };
    passwordInput.addEventListener("input", clearErrors);
    if (confirmInput) confirmInput.addEventListener("input", clearErrors);

    form.addEventListener("submit", function (ev) {
      var pw = passwordInput.value || "";
      var confirmVal = confirmInput ? (confirmInput.value || "") : null;

      var checks = [
        { ok: pw.length >= 10,             msg: "Must be at least 10 characters long" },
        { ok: /[a-z]/.test(pw),            msg: "Must contain at least one lowercase character" },
        { ok: /[A-Z]/.test(pw),            msg: "Must contain at least one uppercase character" },
        { ok: /\d/.test(pw),               msg: "Must contain at least one numeric character" },
        { ok: /[^a-zA-Z0-9]/.test(pw),     msg: "Must contain at least one special character" }
      ];
      if (confirmInput) {
        checks.push({ ok: pw === confirmVal && pw.length > 0,
                      msg: "Password and confirmation must match" });
      }

      var failed = checks.filter(function (c) { return !c.ok; }).map(function (c) { return c.msg; });
      if (failed.length === 0) return; // all good — let the form submit

      ev.preventDefault();
      ev.stopPropagation();
      renderPasswordErrors(passwordInput, failed);
      passwordInput.classList.add("tz-pw-invalid");
      passwordInput.focus();
    });

    return true;
  }

  // Render password / form errors as a toast notification in the top-right
  // corner of the viewport instead of an inline block under the field.
  // Multiple errors are bundled into a single toast with a bulleted list;
  // the toast auto-dismisses after 6s or can be closed manually.
  function renderPasswordErrors(passwordInput, messages) {
    showAuthToast({
      title: messages.length === 1
        ? "Password requirement not met"
        : "Password doesn't meet the requirements",
      messages: messages,
      type: "error",
      timeoutMs: 20000
    });
  }

  // Server-side errors arrive as a Rails-rendered block inside the form
  // (e.g. <%= error_messages_for :user %> emits #errorExplanation /
  // .errorExplanation with an <h2> + <ul><li>… of validation errors).
  // We extract its content into a toast and hide the inline block so the
  // form layout stays clean. Idempotent via the .tz-error-routed marker.
  function rerouteServerErrorsToToast() {
    var inRegister =
      document.querySelector(".registration-modal") ||
      document.querySelector('[data-modal-class-name*="registration"]') ||
      document.querySelector('.modal-delivery-element form[action*="register"]');
    if (!inRegister) return true;

    // Broad selector covers Rails legacy errorExplanation, Spot flash,
    // op-toast and Spot action-message variants OpenProject has used.
    // The `:not(.tz-toast)` guard prevents us from re-extracting our own
    // toast and entering an infinite loop.
    var blocks = document.querySelectorAll(
      ".registration-modal #errorExplanation, " +
      ".registration-modal .errorExplanation, " +
      ".modal-delivery-element #errorExplanation, " +
      ".modal-delivery-element .errorExplanation, " +
      '[data-modal-class-name*="registration"] #errorExplanation, ' +
      '[data-modal-class-name*="registration"] .errorExplanation, ' +
      ".registration-modal .flash-error, " +
      ".registration-modal .flash.flash--error, " +
      ".registration-modal .flash.error, " +
      ".registration-modal .flash--error, " +
      ".registration-modal .op-toast.-error, " +
      ".registration-modal .op-toast, " +
      ".registration-modal .spot-action-message, " +
      '.registration-modal [role="alert"]:not(.tz-toast), ' +
      ".modal-delivery-element .flash-error, " +
      ".modal-delivery-element .flash.flash--error, " +
      ".modal-delivery-element .flash.error, " +
      ".modal-delivery-element .flash--error, " +
      ".modal-delivery-element .op-toast, " +
      ".modal-delivery-element .spot-action-message, " +
      '.modal-delivery-element [role="alert"]:not(.tz-toast), ' +
      '[data-modal-class-name*="registration"] .flash-error, ' +
      '[data-modal-class-name*="registration"] .flash.flash--error, ' +
      '[data-modal-class-name*="registration"] .op-toast, ' +
      '[data-modal-class-name*="registration"] .spot-action-message'
    );

    if (blocks.length === 0) return true; // no errors to route

    Array.prototype.forEach.call(blocks, function (block) {
      if (block.classList.contains("tz-error-routed")) return;
      block.classList.add("tz-error-routed");

      var title = "";
      var messages = [];

      var heading = block.querySelector("h1, h2, h3, h4");
      if (heading) {
        title = heading.textContent.trim();
      }

      var items = block.querySelectorAll("li");
      Array.prototype.forEach.call(items, function (li) {
        var txt = li.textContent.trim();
        if (txt) messages.push(txt);
      });

      // Fallback: paragraphs other than the title
      if (messages.length === 0) {
        var paragraphs = block.querySelectorAll("p");
        Array.prototype.forEach.call(paragraphs, function (p) {
          var txt = p.textContent.trim();
          if (txt && txt !== title) messages.push(txt);
        });
      }

      // Last resort: the block's whole text minus the title
      if (messages.length === 0) {
        var all = block.textContent.replace(/\s+/g, " ").trim();
        if (all && all !== title) {
          var stripped = title ? all.replace(title, "").trim() : all;
          if (stripped) messages.push(stripped);
        }
      }

      // Hide the inline block so the toast is the only error surface.
      block.style.display = "none";
      block.style.visibility = "hidden";

      if (title || messages.length > 0) {
        showAuthToast({
          title: title || "Account creation failed",
          messages: messages,
          type: "error",
          timeoutMs: 20000
        });
      }
    });

    return true;
  }

  function showAuthToast(opts) {
    var container = document.querySelector(".tz-toast-container");
    if (!container) {
      container = document.createElement("div");
      container.className = "tz-toast-container";
      document.body.appendChild(container);
    }

    var toast = document.createElement("div");
    toast.className = "tz-toast tz-toast-" + (opts.type || "error");

    if (opts.title) {
      var titleEl = document.createElement("div");
      titleEl.className = "tz-toast-title";
      titleEl.textContent = opts.title;
      toast.appendChild(titleEl);
    }

    var msgs = opts.messages || (opts.message ? [opts.message] : []);
    if (msgs.length > 0) {
      if (msgs.length === 1) {
        var single = document.createElement("div");
        single.className = "tz-toast-body";
        single.textContent = msgs[0];
        toast.appendChild(single);
      } else {
        var ul = document.createElement("ul");
        ul.className = "tz-toast-list";
        msgs.forEach(function (m) {
          var li = document.createElement("li");
          li.textContent = m;
          ul.appendChild(li);
        });
        toast.appendChild(ul);
      }
    }

    var close = document.createElement("button");
    close.type = "button";
    close.className = "tz-toast-close";
    close.setAttribute("aria-label", "Dismiss");
    close.innerHTML = "&times;";
    var dismiss = function () {
      toast.classList.add("tz-toast-leaving");
      setTimeout(function () { if (toast.parentNode) toast.remove(); }, 200);
    };
    close.addEventListener("click", dismiss);
    toast.appendChild(close);

    container.appendChild(toast);

    if (opts.timeoutMs !== 0) {
      setTimeout(dismiss, opts.timeoutMs || 20000);
    }
  }

  function rewriteAuthLinkText() {
    var login = document.querySelector("#login-form");
    if (login) {
      var link = login.querySelector('a[href*="lost_password"]');
      if (!link) return false; // retry — form not rendered yet
      if (link.textContent.trim() !== "Forgot password?") {
        link.textContent = "Forgot password?";
      }
    }

    // Register page: rename the "Create" submit button to "Create Account".
    // Rails generates the button via I18n key :button_create ("Create"); we
    // rewrite the text in-place so the change stays in the bind-mounted
    // CSS/JS layer and doesn't require a locale-file edit.
    var registerForm =
      document.querySelector(".registration-modal form") ||
      document.querySelector('.modal-delivery-element form[action*="register"]') ||
      document.querySelector('[data-modal-class-name*="registration"] form');

    if (registerForm) {
      var btn = registerForm.querySelector('button[type="submit"], input[type="submit"]');
      if (btn) {
        var current = (btn.tagName === "INPUT" ? btn.value : btn.textContent || "").trim();
        if (current !== "Create Account" && current.toLowerCase() === "create") {
          if (btn.tagName === "INPUT") {
            btn.value = "Create Account";
          } else {
            // Preserve any icon child elements; replace only text nodes.
            var replaced = false;
            for (var i = 0; i < btn.childNodes.length; i++) {
              var node = btn.childNodes[i];
              if (node.nodeType === 3 /* TEXT_NODE */ && node.textContent.trim()) {
                node.textContent = "Create Account";
                replaced = true;
                break;
              }
            }
            if (!replaced) btn.textContent = "Create Account";
          }
        }
      }
    }
    return true;
  }

  function injectAuthBackLink() {
    // ── Register page detection ───────────────────────────────────
    // `.registration-modal` is the class Stimulus adds AFTER mounting,
    // so it may not exist on the first try. `.modal-delivery-element`
    // is in the initial server-rendered HTML and is always present, so
    // we prefer it as the container. The form[action] match is the
    // ultimate fallback if neither container marker is found.
    var registrationContainer =
      document.querySelector(".registration-modal .modal-delivery-element") ||
      document.querySelector('[data-modal-class-name*="registration"] .modal-delivery-element') ||
      document.querySelector(".modal-delivery-element") ||
      document.querySelector(".registration-modal") ||
      document.querySelector('[data-modal-class-name*="registration"]');

    // ── Lost-password page detection ──────────────────────────────
    // Append to the .form--section (the right-half flex container)
    // so the link sits at the bottom of the column.
    var lostPasswordSection = null;
    var lostPasswordForm = document.querySelector('form[action*="lost_password"]');
    if (lostPasswordForm) {
      lostPasswordSection =
        lostPasswordForm.closest(".form--section") || lostPasswordForm.parentNode;
    }

    // Not on a target page — done.
    if (!registrationContainer && !lostPasswordSection) return true;

    // Already injected — done.
    if (document.querySelector(".tz-back-to-login")) return true;

    var container = registrationContainer || lostPasswordSection;
    if (!container) return false; // wait for next mutation

    // On the register page, show "Have an account? Login" with only
    // "Login" as the clickable link (matches the design pattern of
    // "Don't have an account? Register Now" on the sign-in page).
    // On the lost-password page, keep the simpler "Back to sign in" form.
    var isRegisterPage = !!registrationContainer;

    if (isRegisterPage) {
      var wrap = document.createElement("div");
      wrap.className = "tz-back-to-login";
      var prefix = document.createTextNode("Have an account? ");
      var link = document.createElement("a");
      link.href = "/login";
      link.className = "tz-back-to-login-link";
      link.textContent = "Login";
      wrap.appendChild(prefix);
      wrap.appendChild(link);
      container.appendChild(wrap);
    } else {
      var link = document.createElement("a");
      link.href = "/login";
      link.className = "tz-back-to-login";
      link.innerHTML = '<span aria-hidden="true">&larr;</span> Back to sign in';
      container.appendChild(link);
    }
    return true;
  }

  function bootstrap() {
    init();

    // Tear down any retry watcher left over from the previous page.
    stopWatching();

    // Try the seven injections up-front. The observer below retries each
    // until they report done — the Spot modal that wraps the register
    // form is mounted by Stimulus after DOMContentLoaded, so the
    // .registration-modal element often doesn't exist on the first try.
    var srvErrDone = rerouteServerErrorsToToast();
    var pwValDone = setupPasswordValidation();
    var rewriteDone = rewriteAuthLinkText();
    var noAutofillDone = preventRegisterAutofill();
    var phDone = injectAuthPlaceholders();
    var authDone = injectAuthBackLink();
    var backBtnDone = injectBackButton();
    if (srvErrDone && pwValDone && rewriteDone && noAutofillDone && phDone && authDone && backBtnDone) return;

    pageHeaderObserver = new MutationObserver(function () {
      var s = rerouteServerErrorsToToast();
      var v = setupPasswordValidation();
      var r = rewriteAuthLinkText();
      var n = preventRegisterAutofill();
      var p = injectAuthPlaceholders();
      var a = injectAuthBackLink();
      var b = injectBackButton();
      if (s && v && r && n && p && a && b) stopWatching();
    });
    pageHeaderObserver.observe(document.body, { childList: true, subtree: true });

    // Safety net — stop after 30s even if neither feature ever resolves,
    // so we don't leak a forever-running observer.
    pageHeaderObserverTimer = setTimeout(stopWatching, 30000);
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
