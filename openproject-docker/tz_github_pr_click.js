/**
 * Tamil Zorous: Make the GitHub PR state badge ("Open", "Merged", "Closed")
 * clickable — clicking it opens the PR on GitHub in a new tab.
 *
 * The stock OpenProject UI only makes the "repo#number" text a link.
 * This script watches for PR state badges and attaches click handlers
 * that navigate to the same URL as the sibling repo link.
 */
(function () {
  'use strict';

  function attachClickHandlers() {
    // Find all PR state badges
    var badges = document.querySelectorAll('.op-pull-request-state');
    badges.forEach(function (badge) {
      if (badge.dataset.tzClickAttached) return;
      badge.dataset.tzClickAttached = '1';

      // Walk up to the op-pull-request container and find the repo link
      var container = badge.closest('.op-pull-request, op-github-pull-request');
      if (!container) return;

      var repoLink = container.querySelector('a.op-pull-request--link');
      if (!repoLink || !repoLink.href) return;

      badge.style.cursor = 'pointer';
      badge.title = 'Open PR on GitHub';
      badge.addEventListener('click', function () {
        window.open(repoLink.href, '_blank');
      });
    });
  }

  // Run on DOM changes (Angular renders dynamically)
  var observer = new MutationObserver(function () {
    attachClickHandlers();
  });

  function init() {
    attachClickHandlers();
    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
