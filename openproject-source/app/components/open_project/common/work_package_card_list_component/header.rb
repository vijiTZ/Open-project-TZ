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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module OpenProject
  module Common
    class WorkPackageCardListComponent
      class Header < ApplicationComponent
        include OpPrimer::ComponentHelpers

        renders_one :description

        renders_many :actions, types: {
          button: ->(**system_arguments) do
            Primer::Beta::Button.new(**system_arguments)
          end
        }

        renders_one :menu, ->(menu_id: nil, button_aria_label: nil, **system_arguments) do
          system_arguments[:classes] = class_names(
            system_arguments[:classes],
            "hide-when-print"
          )

          menu = Primer::Alpha::ActionMenu.new(
            menu_id: menu_id || dom_target(container, :menu),
            anchor_align: :end,
            **system_arguments
          )
          menu.with_show_button(
            scheme: :invisible,
            icon: :"kebab-horizontal",
            "aria-label": button_aria_label || t(".label_actions"),
            tooltip_direction: :se
          )
          menu
        end

        attr_reader :title, :container, :list_id, :collapsed, :count

        def initialize(title:, container:, list_id:, collapsed: false, count: nil)
          super()

          @title = title
          @container = container
          @list_id = list_id
          @collapsed = collapsed
          @count = count
        end
      end
    end
  end
end
