# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Wikis::Concerns
  module UpdateReverseInlineWikiPageLinks
    extend ActiveSupport::Concern

    def update_reverse_inline_wiki_page_links(wiki_page)
      provider = Wikis::InternalProvider.enabled.first
      return if provider.nil?

      Wikis::ReverseInlinePageLink.where(provider:, identifier: wiki_page.id).delete_all

      find_wp_links(wiki_page.text).uniq.each do |wp_id|
        wp = WorkPackage.find_by(id: wp_id)
        next if wp.nil?

        Wikis::ReverseInlinePageLink.create!(linkable: wp, provider:, identifier: wiki_page.id)
      end
    end

    private

    def find_wp_links(text)
      return [] if text.blank?

      # extracted prefix from lib/open_project/text_formatting/matchers/resource_links_matcher.rb
      # adding # as additional prefix
      text.scan(/(?:[[:space:],~>#\(\[\-]|^)#([0-9]+)/) # rubocop:disable Style/RedundantRegexpEscape
    end
  end
end
