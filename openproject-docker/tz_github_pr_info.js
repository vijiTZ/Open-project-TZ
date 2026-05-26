/**
 * TZ GitHub PR Info Enhancement
 *
 * Enhances PR cards in the GitHub tab with:
 * - Conflict warning badge (from TZ: labels)
 * - Latest comment preview (from TZ: labels)
 * - Comment count badge
 *
 * Data is fetched from the OpenProject API and injected into the DOM.
 */
(function () {
  "use strict";

  var TZ_PR_ATTR = "data-tz-pr-enhanced";

  // Fetch PR data for a work package from the OpenProject API
  function fetchPRsForWorkPackage(wpId, callback) {
    var url = "/api/v3/work_packages/" + wpId + "/github_pull_requests";
    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.onreadystatechange = function () {
      if (xhr.readyState === 4 && xhr.status === 200) {
        try {
          var data = JSON.parse(xhr.responseText);
          callback(data._embedded ? data._embedded.elements : []);
        } catch (e) {
          callback([]);
        }
      }
    };
    xhr.send();
  }

  // Extract WP ID from the current URL
  function getWorkPackageId() {
    var match = window.location.href.match(/work_packages\/(\d+)/);
    return match ? match[1] : null;
  }

  // Build a badge element
  function createBadge(text, bgColor, textColor) {
    var badge = document.createElement("span");
    badge.className = "tz-pr-badge";
    badge.textContent = text;
    badge.style.cssText =
      "display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; " +
      "margin-left: 6px; vertical-align: middle; line-height: 18px; " +
      "background: " + bgColor + "; color: " + textColor + ";";
    return badge;
  }

  // Build a comment preview element
  function createCommentPreview(comments) {
    var container = document.createElement("div");
    container.className = "tz-pr-comments-section";
    container.style.cssText =
      "margin-top: 8px; padding: 8px 12px; background: #f6f8fa; border-radius: 6px; " +
      "border-left: 3px solid #0075ca; font-size: 12px; color: #57606a;";

    var header = document.createElement("div");
    header.style.cssText = "font-weight: 600; margin-bottom: 4px; color: #24292f;";
    header.textContent = "Latest Comments";
    container.appendChild(header);

    comments.forEach(function (c) {
      var row = document.createElement("div");
      row.style.cssText = "margin-top: 4px; line-height: 1.4;";

      // Extract @user and comment from "TZ: @user: comment text..."
      var text = c.name.replace(/^TZ:\s*/, "");
      var atIdx = text.indexOf(":");
      if (atIdx > 0) {
        var user = document.createElement("strong");
        user.textContent = text.substring(0, atIdx);
        user.style.color = "#0969da";
        row.appendChild(user);
        row.appendChild(document.createTextNode(" " + text.substring(atIdx + 1).trim()));
      } else {
        row.textContent = text;
      }
      container.appendChild(row);
    });

    return container;
  }

  // Enhance a single PR card with data from API
  function enhancePRCard(prCard, prData) {
    if (!prData) return;

    // Find the state badge area
    var stateEl = prCard.querySelector(".op-pull-request--state, op-github-pull-request-state");
    if (!stateEl) return;

    // Extract TZ labels
    var labels = prData.labels || [];
    var conflictLabel = null;
    var commentLabels = [];

    var reopenedLabel = null;

    labels.forEach(function (label) {
      var name = typeof label === "string" ? label : (label.name || "");
      if (name === "TZ: Conflicts") {
        conflictLabel = label;
      } else if (name.indexOf("TZ: Reopened by @") === 0) {
        reopenedLabel = label;
      } else if (name.indexOf("TZ: @") === 0) {
        commentLabels.push(typeof label === "string" ? { name: label } : label);
      }
    });

    // Add reopened badge
    if (reopenedLabel) {
      var reopenedText = (typeof reopenedLabel === "string" ? reopenedLabel : reopenedLabel.name || "").replace("TZ: ", "");
      var reopenedBadge = createBadge("🔄 " + reopenedText, "#e3b341", "#24292f");
      stateEl.parentNode.insertBefore(reopenedBadge, stateEl.nextSibling);
    }

    // Add conflict badge
    if (conflictLabel) {
      var conflictBadge = createBadge("⚠ Conflicts", "#d73a49", "#ffffff");
      stateEl.parentNode.insertBefore(conflictBadge, stateEl.nextSibling);
    }

    // Add comment count badge
    var totalComments = (prData.commentsCount || 0) + (prData.reviewCommentsCount || 0);
    if (totalComments > 0) {
      var commentBadge = createBadge("💬 " + totalComments, "#ddf4ff", "#0969da");
      stateEl.parentNode.insertBefore(commentBadge, stateEl.nextSibling);
    }

    // Add comment previews below the PR info
    if (commentLabels.length > 0) {
      var infoEl = prCard.querySelector(".op-pull-request--info");
      if (infoEl) {
        var preview = createCommentPreview(commentLabels);
        infoEl.parentNode.insertBefore(preview, infoEl.nextSibling);
      }
    }
  }

  // Main: watch for PR cards and enhance them
  function processAllPRCards() {
    var cards = document.querySelectorAll("op-github-pull-request, .op-pull-request");
    if (cards.length === 0) return;

    // Check if already enhanced
    var needsEnhance = false;
    cards.forEach(function (card) {
      if (!card.getAttribute(TZ_PR_ATTR)) needsEnhance = true;
    });
    if (!needsEnhance) return;

    var wpId = getWorkPackageId();
    if (!wpId) return;

    fetchPRsForWorkPackage(wpId, function (prs) {
      cards.forEach(function (card) {
        if (card.getAttribute(TZ_PR_ATTR)) return;
        card.setAttribute(TZ_PR_ATTR, "1");

        // Match by PR number from the link text (e.g., "repo#42")
        var linkEl = card.querySelector(".op-pull-request--link");
        if (!linkEl) return;

        var linkText = linkEl.textContent || "";
        var hashIdx = linkText.lastIndexOf("#");
        if (hashIdx < 0) return;

        var prNumber = parseInt(linkText.substring(hashIdx + 1), 10);
        if (isNaN(prNumber)) return;

        // Find matching PR data
        var matchedPR = null;
        for (var i = 0; i < prs.length; i++) {
          if (prs[i].number === prNumber) {
            matchedPR = prs[i];
            break;
          }
        }

        enhancePRCard(card, matchedPR);
      });
    });
  }

  // Use MutationObserver to catch dynamically rendered PR cards
  var observer = new MutationObserver(function () {
    processAllPRCards();
  });

  function init() {
    observer.observe(document.body, { childList: true, subtree: true });
    // Also run once on load
    processAllPRCards();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
