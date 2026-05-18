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

import {Controller} from '@hotwired/stimulus';
import {renderStreamMessage} from '@hotwired/turbo';
import {debounce, DebouncedFunc} from 'lodash';
import {useMeta} from 'stimulus-use';

export default class extends Controller {
    static values = {
        toggleUrl: String,
        filterUrl: String,
        debounce: {type: Number, default: 500},
    };

    static metaNames = ['csrf-token'];

    declare readonly csrfToken:string;
    declare toggleUrlValue:string;
    declare filterUrlValue:string;
    declare debounceValue:number;

    private debouncedFilter:DebouncedFunc<(filter:string) => Promise<void>> | null = null;

    connect():void {
        useMeta(this, {suffix: false});
        this.debouncedFilter = debounce(
            (filter:string) => this.submitFilter(filter),
            this.debounceValue,
        );
    }

    disconnect():void {
        this.debouncedFilter?.cancel();
    }

    async toggleProject(event:Event):Promise<void> {
        const checkbox = event.currentTarget as HTMLInputElement;
        const projectId = checkbox.value;
        const url = this.toggleUrlValue.replace('PROJECT_ID', projectId);

        const response = await fetch(url, {
            headers: {
                Accept: 'text/vnd.turbo-stream.html',
            },
        });

        const html = await response.text();
        renderStreamMessage(html);
    }

    filterProjects(event:Event):void {
        const input = event.currentTarget as HTMLInputElement;
        void this.debouncedFilter?.(input.value);
    }

    private async submitFilter(filter:string):Promise<void> {
        const url = this.filterUrlValue;
        const formData = new FormData();
        formData.append('filter', filter);

        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Accept': 'text/vnd.turbo-stream.html',
                'X-CSRF-Token': this.csrfToken,
            },
            body: formData,
        });

        const html = await response.text();
        renderStreamMessage(html);
    }
}
