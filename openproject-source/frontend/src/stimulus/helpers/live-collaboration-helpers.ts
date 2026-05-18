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
 */

import { HocuspocusProvider } from '@hocuspocus/provider';
import type { Doc } from 'yjs';

type Listener = (provider:HocuspocusProvider) => void;

class LiveCollaborationManagerClass {
  yjsProviderInstance:HocuspocusProvider|null = null;
  yjsDocInstance:Doc|null = null;

  private listeners:Listener[] = [];

  /**
   * Initializes the YJS Provider
   * @param provider The provider to use
   * @param doc The Y.Doc instance to use
   * @returns void
   */
  initializeYjsProvider(provider:HocuspocusProvider, doc:Doc) {
    this.destroyYjsProvider();
    this.destroyYjsDoc();

    this.yjsProviderInstance = provider;
    this.yjsDocInstance = doc;
    this.listeners.forEach((listener) => listener(this.yjsProviderInstance!));
  }

  /**
   * Conditionally destroys the current collaboration provider if the given provider
   * instance still owns the shared state.
   *
   * During Turbo navigation, the old Stimulus controller's disconnect() fires after the new
   * controller's connect(). Without an ownership check, the old controller would destroy the
   * new provider, causing a spurious "connection error" banner.
   *
   * @param provider The provider instance requesting destruction; treated as the
   *                 candidate owner of the current collaboration session.
   * @returns `true` if the given provider was the current owner and the internal
   *          provider/doc instances were destroyed; `false` otherwise.
   */
  destroyIfOwner(provider:HocuspocusProvider):boolean {
    if (this.yjsProviderInstance === provider) {
      this.destroy();
      return true;
    }
    return false;
  }

  /**
   * Cleans up the collaboration provider and Y.Doc instance.
   * This method should be called when a collaboration session is ended
   */
  private destroy():void {
    this.destroyYjsProvider();
    this.destroyYjsDoc();

    this.listeners = [];
  }

  private destroyYjsProvider():void {
    if (this.yjsProviderInstance) {
      this.yjsProviderInstance.destroy();
      this.yjsProviderInstance = null;
    }
  }

  private destroyYjsDoc():void {
    if (this.yjsDocInstance) {
      this.yjsDocInstance.destroy();
      this.yjsDocInstance = null;
    }
  }

  /**
   * Gets a shared YJS Provider
   * @throws Error if no provider is configured
   */
  get yjsProvider():HocuspocusProvider {
    if (!this.yjsProviderInstance) {
      throw new Error('No YJS Provider configured');
    }
    return this.yjsProviderInstance;
  }

  /**
   * Registers a listener to be called when the shared YJS provider is ready.
   *
   * If a provider is already initialized, the listener is invoked immediately
   * with the current {@link HocuspocusProvider} instance. Otherwise, the
   * listener is stored and invoked later once {@link initializeYjsProvider} is called.
   *
   * @param listener Callback that receives the ready { @link HocuspocusProvider }
   *
   */
  onReady(listener:Listener) {
    this.listeners.push(listener);
    if (this.yjsProviderInstance) {
      listener(this.yjsProviderInstance);
    }
  }

  /**
   * Unregisters a previously registered ready listener.
   * @param listener The listener function to remove
   */
  offReady(listener:Listener):void {
    const index = this.listeners.indexOf(listener);
    if (index !== -1) {
      this.listeners.splice(index, 1);
    }
  }
}

export const LiveCollaborationManager = new LiveCollaborationManagerClass();
