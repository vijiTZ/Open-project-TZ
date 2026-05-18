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

module Wikis
  module Adapters
    module Providers
      module XWiki
        module Queries
          class PageInfo < BaseQuery
            def call(input_data:, **)
              titles = [
                "What makes XWiki special?",
                "API documentation",
                "A brief introduction on configuring your own XWiki instance and connect it to OpenProject.",
                "Security considerations for API design",
                "Syntax overview",
                "Getting help",
                "Enterprise support"
              ]
              title = titles[Random.new(input_data.identifier.hash).rand(titles.size)]

              success(
                Results::PageInfo.new(
                  identifier: input_data.identifier,
                  provider:,
                  title:,
                  href: "#"
                )
              )
            end
          end
        end
      end
    end
  end
end
