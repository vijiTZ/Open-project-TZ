/*
 * -- copyright
 * OpenProject is an open source project management software.
 * Copyright (C) the OpenProject GmbH
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
 *
 */

import { Controller } from '@hotwired/stimulus';
import { renderStreamMessage } from '@hotwired/turbo';

export default class extends Controller {
  static values = {
    url: String,
    dialogUrl: String,
  };

  declare urlValue:string;
  declare dialogUrlValue:string;
  declare hasDialogUrlValue:boolean;

  private boundFormDataHandler:((e:FormDataEvent) => void) | null = null;

  connect() {
    const form = this.element.closest('form');
    if (form) {
      this.boundFormDataHandler = (e:FormDataEvent) => this.appendStableKeySystemArguments(e);
      form.addEventListener('formdata', this.boundFormDataHandler);
    }
  }

  disconnect() {
    const form = this.element.closest('form');
    if (form && this.boundFormDataHandler) {
      form.removeEventListener('formdata', this.boundFormDataHandler);
      this.boundFormDataHandler = null;
    }
  }

  async request(e:Event):Promise<void> {
    // Don't trigger edit mode if the user is selecting text or just finished a selection
    if (window.getSelection()?.toString()) {
      return;
    }

    // Don't trigger edit mode if clicking on a link
    const target = e.target as HTMLElement;
    if (target.tagName === 'a' || target.closest('a')) {
      return;
    }

    const response = await fetch(this.urlValue, {
      method: 'GET',
      headers: { Accept: 'text/vnd.turbo-stream.html' },
      credentials: 'same-origin',
    });

    if (response.ok) {
      renderStreamMessage(await response.text());
    } else {
      throw new Error(response.statusText);
    }
  }

  openDialog(event:Event) {
    // Don't trigger edit mode if the user is selecting text or just finished a selection
    if (window.getSelection()?.toString()) {
      return;
    }

    const target = event.target as HTMLElement;

    // Check if the event is on an interactive element that should be ignored
    if (this.isInteractiveElement(target)) {
      // Don't handle this event, let the child element handle it
      return;
    }

    // Prevent default and dispatch custom event for async-dialog to handle
    event.preventDefault();
    this.dispatch('open-dialog', { detail: { url: this.dialogUrlValue } });
  }

  submitForm() {
    const form = this.element.closest('form');
    if (form) {
      form.requestSubmit();
    }
  }

  private appendStableKeySystemArguments(e:FormDataEvent):void {
    const result:Record<string, unknown> = {};
    document.querySelectorAll<HTMLElement>('[data-inplace-edit-stable-key][data-inplace-edit-system-arguments]').forEach((el) => {
      const key = el.dataset.inplaceEditStableKey;
      const raw = el.dataset.inplaceEditSystemArguments;
      if (key && raw) {
        try {
          result[key] = JSON.parse(raw);
        } catch {
          // ignore malformed JSON
        }
      }
    });
    e.formData.set('stable_key_system_arguments', JSON.stringify(result));
  }

  private isInteractiveElement(element:HTMLElement):boolean {
    // Check if the element is or is inside an interactive element.
    let current = element;
    while (current && current !== this.element) {
      if (current.matches('button, a, dialog')) {
        return true;
      }
      current = current.parentElement!;
    }
    return false;
  }
}
