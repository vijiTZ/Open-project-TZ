/**
 * TZ GitHub PR Info Enhancement
 *
 * Enhances PR cards in the GitHub tab with:
 * - Conflict warning badge (from TZ: labels)
 * - Collapsible comment preview with arrow toggle
 * - Comment count badge
 * - File name shown for code review comments
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

  // Parse a comment label into structured data
  // Format: "TZ: @user: text|||url|||type|||filepath|||commentId|||replyToId"
  function parseCommentLabel(c) {
    var rawName = (typeof c === "string" ? c : (c.name || "")).replace(/^TZ:\s*/, "");
    var parts = rawName.split("|||");
    return {
      text: parts[0] || "",
      url: parts[1] || "",
      type: parts[2] || "",
      filePath: parts[3] || "",
      commentId: parts[4] || "",
      replyToId: parts[5] || "",
      isReply: (parts[2] || "") === "reply",
      isReview: (parts[2] || "") === "review"
    };
  }

  // Build a single comment row element
  function buildCommentRow(parsed, isNested) {
    var row = document.createElement("div");
    row.style.cssText = "margin-top: 6px; line-height: 1.4; padding: 4px 0; border-bottom: 1px solid #e8eaed;";
    if (isNested) {
      row.style.cssText += " margin-left: 16px; border-left: 2px solid #ddd; padding-left: 8px;";
    }

    // Show type badge + file name for review comments (not for nested replies — they inherit from parent)
    if (parsed.isReview || (parsed.isReply && !isNested)) {
      var badgeLine = document.createElement("div");
      badgeLine.style.cssText = "margin-bottom: 3px;";

      var badge = document.createElement("span");
      badge.textContent = parsed.isReply ? "↳ Reply" : "📝 Code review";
      badge.style.cssText = "font-size: 10px; color: #8b949e; margin-right: 6px;";
      badgeLine.appendChild(badge);

      if (parsed.filePath) {
        var fileEl = document.createElement("code");
        var fileName = parsed.filePath.indexOf("/") >= 0 ? parsed.filePath.split("/").pop() : parsed.filePath;
        fileEl.textContent = fileName;
        fileEl.style.cssText =
          "font-size: 11px; color: #0550ae; background: #ddf4ff; padding: 1px 6px; " +
          "border-radius: 4px; font-family: monospace;";
        badgeLine.appendChild(fileEl);
      }

      row.appendChild(badgeLine);
    } else if (isNested) {
      var replyBadge = document.createElement("span");
      replyBadge.textContent = "↳ Reply";
      replyBadge.style.cssText = "font-size: 10px; color: #8b949e; margin-right: 4px;";
      row.appendChild(replyBadge);
    }

    // Extract @user and comment text
    var atIdx = parsed.text.indexOf(":");
    if (atIdx > 0) {
      var userName = parsed.text.substring(0, atIdx);
      var commentText = parsed.text.substring(atIdx + 1).trim();

      var user = document.createElement("strong");
      user.textContent = userName;
      user.style.color = "#0969da";
      row.appendChild(user);

      if (parsed.url) {
        var link = document.createElement("a");
        link.href = parsed.url;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = " " + commentText;
        link.style.cssText = "color: #57606a; text-decoration: none; cursor: pointer;";
        link.onmouseover = function () { this.style.color = "#0969da"; this.style.textDecoration = "underline"; };
        link.onmouseout = function () { this.style.color = "#57606a"; this.style.textDecoration = "none"; };
        row.appendChild(link);
      } else {
        row.appendChild(document.createTextNode(" " + commentText));
      }
    } else {
      row.textContent = parsed.text;
    }

    return row;
  }

  // Build the collapsible comment section with replies nested under parents
  function createCommentSection(comments) {
    var wrapper = document.createElement("div");
    wrapper.className = "tz-pr-comments-wrapper";
    wrapper.style.cssText = "margin-top: 8px;";

    // Toggle header with arrow
    var toggle = document.createElement("div");
    toggle.className = "tz-pr-comments-toggle";
    toggle.style.cssText =
      "display: inline-flex; align-items: center; gap: 6px; cursor: pointer; " +
      "padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: 600; " +
      "color: #0969da; background: #ddf4ff; user-select: none;";

    var arrow = document.createElement("span");
    arrow.className = "tz-pr-comments-arrow";
    arrow.textContent = "▶";
    arrow.style.cssText = "font-size: 10px; transition: transform 0.2s ease; display: inline-block;";

    var toggleText = document.createElement("span");
    toggleText.textContent = "💬 Comments (" + comments.length + ")";

    toggle.appendChild(arrow);
    toggle.appendChild(toggleText);
    wrapper.appendChild(toggle);

    // Comment list (hidden by default)
    var commentList = document.createElement("div");
    commentList.className = "tz-pr-comments-list";
    commentList.style.cssText =
      "display: none; margin-top: 6px; padding: 8px 12px; background: #f6f8fa; " +
      "border-radius: 6px; border-left: 3px solid #0075ca; font-size: 12px; color: #57606a;";

    // Parse all comments
    var parsed = comments.map(function (c) { return parseCommentLabel(c); });

    // Separate parents (non-reply) and replies
    var parents = [];
    var replies = {};  // keyed by replyToId
    parsed.forEach(function (p) {
      if (p.isReply && p.replyToId) {
        if (!replies[p.replyToId]) replies[p.replyToId] = [];
        replies[p.replyToId].push(p);
      } else {
        parents.push(p);
      }
    });

    // Render parents, then their replies nested underneath
    parents.forEach(function (parent) {
      commentList.appendChild(buildCommentRow(parent, false));

      // Find replies to this parent
      var childReplies = replies[parent.commentId];
      if (childReplies) {
        childReplies.forEach(function (reply) {
          commentList.appendChild(buildCommentRow(reply, true));
        });
        delete replies[parent.commentId];
      }
    });

    // Render any orphan replies (parent not in our list) as standalone
    Object.keys(replies).forEach(function (key) {
      replies[key].forEach(function (reply) {
        commentList.appendChild(buildCommentRow(reply, false));
      });
    });

    wrapper.appendChild(commentList);

    // Toggle click handler
    var isOpen = false;
    toggle.addEventListener("click", function () {
      isOpen = !isOpen;
      commentList.style.display = isOpen ? "block" : "none";
      arrow.style.transform = isOpen ? "rotate(90deg)" : "rotate(0deg)";
    });

    return wrapper;
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

    // Add collapsible comment section below the PR info (only if there are comments)
    if (commentLabels.length > 0) {
      var infoEl = prCard.querySelector(".op-pull-request--info");
      if (infoEl) {
        var section = createCommentSection(commentLabels);
        infoEl.parentNode.insertBefore(section, infoEl.nextSibling);
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
    processAllPRCards();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
