/*
 * -- copyright
 * OpenProject is an open source project management software.
 * Copyright (C) 2023 the OpenProject GmbH
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version 3.
 *
 * OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
 * Copyright (C) 2006-2013 Jean-Philippe Lang
 * Copyright (C) 2010-2013 the ChiliProject Team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * See COPYRIGHT and LICENSE files for more details.
 * ++
 */

import BaseController from './base.controller';

export default class StemsController extends BaseController {
  connect() {
    super.connect();

    this.handleStemVisibility();
  }

  // NOTE FROM JONAS:
  // Towards the code below:
  // Ideally the stem rendering would be correctly rendered for all UI states from the server
  // but as we push single elements into the DOM via turbo-streams, the server-side rendered collection state gets stale quickly
  // I've decided to go with a client-side rendering-correction approach for now
  // as I don't want to introduce more complexity and queries (n+1 for position checks etc.) to the server-side rendering
  handleStemVisibility() {
    this.handleStemVisibilityForMobile();
    this.handleLastStemPartVisibility();
  }

  private handleStemVisibilityForMobile() {
    if (this.isMobile()) {
      if (this.indexOutlet.sortingAscending) return;

      const initialJournalContainer = (this.element).querySelector('.work-packages-activities-tab-journals-item-component-details--journal-details-container[data-initial="true"]');

      if (initialJournalContainer) {
        initialJournalContainer.classList.add('work-packages-activities-tab-journals-item-component-details--journal-details-container--border-removed');
      }
    }
  }

  private handleLastStemPartVisibility() {
    const emptyLines = (this.element).querySelectorAll('.empty-line');

    // make sure all are visible first
    emptyLines.forEach((container) => {
      container.classList.remove('work-packages-activities-tab-journals-item-component-details--journal-details-container--hidden');
    });

    if (this.indexOutlet.sortingAscending || this.indexOutlet.filterValue === 'only_changes') return;

    // then hide the last one again
    if (emptyLines.length > 0) {
      // take the parent container of the last empty line
      const lastEmptyLineContainer = emptyLines[emptyLines.length - 1].parentElement;
      if (lastEmptyLineContainer) {
        lastEmptyLineContainer.classList.add('work-packages-activities-tab-journals-item-component-details--journal-details-container--hidden');
      }
    }
  }
}
