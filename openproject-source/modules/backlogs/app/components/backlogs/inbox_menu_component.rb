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

module Backlogs
  # Renders Primer::Alpha::ActionMenu::List for the deferred menu (Backlogs::InboxController#menu).
  # +menu_id+ must match the row ActionMenu in InboxItemComponent.
  class InboxMenuComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers
    include CommonHelper

    attr_reader :work_package, :project, :max_position, :current_user, :open_sprints_exist

    def initialize(work_package:, project:, max_position:, open_sprints_exist:, current_user: User.current)
      super()

      @work_package = work_package
      @project = project
      @current_user = current_user
      @max_position = max_position
      @open_sprints_exist = open_sprints_exist
    end

    def menu_id
      dom_target(work_package, :menu)
    end

    private

    def show_move_submenu?
      show_move_items? || show_move_to_sprint?
    end

    def show_move_items?
      allowed_to_manage_sprint_items? &&
        !(first_item? && last_item?)
    end

    def show_move_to_sprint?
      allowed_to_manage_sprint_items? && open_sprints_exist
    end

    def allowed_to_manage_sprint_items?
      current_user.allowed_in_project?(:manage_sprint_items, project)
    end

    def build_move_menu(menu)
      unless first_item?
        build_move_item(menu, label: I18n.t(:label_sort_highest), direction: "highest", icon: :"move-to-top")
        build_move_item(menu, label: I18n.t(:label_sort_higher), direction: "higher", icon: :"chevron-up")
      end
      unless last_item?
        build_move_item(menu, label: I18n.t(:label_sort_lower), direction: "lower", icon: :"chevron-down")
        build_move_item(menu, label: I18n.t(:label_sort_lowest), direction: "lowest", icon: :"move-to-bottom")
      end
    end

    def build_move_item(menu, label:, direction:, icon:)
      menu.with_item(
        id: dom_target(work_package, :menu, direction),
        label:,
        tag: :button,
        href: reorder_project_backlogs_inbox_path(project, work_package, all_backlogs_params),
        form_arguments: { method: :post, inputs: [{ name: "direction", value: direction }] }
      ) do |item|
        item.with_leading_visual_icon(icon:)
      end
    end

    def first_item?
      work_package.position == 1
    end

    def last_item?
      work_package.position == max_position
    end
  end
end
