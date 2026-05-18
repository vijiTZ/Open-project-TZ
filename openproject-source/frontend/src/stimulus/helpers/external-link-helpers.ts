//-- copyright
// OpenProject is an open source project management software.
// Copyright (C) the OpenProject GmbH
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License version 3.
//
// OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
// Copyright (C) 2006-2013 Jean-Philippe Lang
// Copyright (C) 2010-2013 the ChiliProject Team
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//
// See COPYRIGHT and LICENSE files for more details.
//++

/**
 * Shared utilities for external link handling. Used by both
 * ExternalLinksController (DOM rewriting for server-rendered pages) and
 * ProseMirrorExternalLinksController (click interception for BlockNote editors).
 */

/**
 * Returns true when the link has `target="_blank"`, meaning it opens in a new
 * tab or window. Used by the ExternalLinksController to decide whether to add
 * an `aria-describedby` accessibility hint.
 */
export function isLinkBlank(link:HTMLAnchorElement) {
  return link.target === '_blank';
}

/**
 * Returns true when the link points to a different origin than the current page.
 * External links receive special treatment for security (noopener/noreferrer)
 * and, when capture is enabled, are routed through `/external_redirect` for
 * phishing prevention.
 *
 * Only considers http/https URLs — non-web protocols (mailto:, tel:,
 * javascript:, etc.) return false because they don't navigate to an
 * external origin.
 */
export function isLinkExternal(link:HTMLAnchorElement) {
  try {
    const linkUrl = new URL(link.href, window.location.origin);
    if (!linkUrl.protocol.startsWith('http')) return false;
    return linkUrl.origin !== window.location.origin;
  } catch {
    return false;
  }
}

/**
 * Returns true when the link is eligible for external-link processing.
 * Links with empty hrefs (e.g. anchor-only), download links, and non-web
 * protocols (mailto:, tel:, javascript:, etc.) are never rewritten or intercepted.
 */
export function isExternalLinkCandidate(link:HTMLAnchorElement) {
  const href = link.href || '';
  if (href === '' || link.hasAttribute('download')) return false;
  if (!link.protocol.startsWith('http')) return false;
  return true;
}

/**
 * Builds the `/external_redirect` URL that the server uses for external link
 * capture. The ExternalLinksController rewrites hrefs directly; the
 * ProseMirrorExternalLinksController passes this URL to `window.open` on click
 * to avoid corrupting the ProseMirror document model.
 */
export function buildExternalRedirectUrl(href:string):string {
  const basePath = window.appBasePath ?? '';
  return `${basePath}/external_redirect?url=${encodeURIComponent(href)}`;
}
