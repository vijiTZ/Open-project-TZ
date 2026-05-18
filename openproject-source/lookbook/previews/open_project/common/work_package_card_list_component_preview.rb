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
    # @logical_path OpenProject/Common
    class WorkPackageCardListComponentPreview < ViewComponent::Preview
      include ActionView::RecordIdentifier

      def sprint_with_cards
        sprint = Sprint.first
        project = sprint&.project
        return preview_message("No sprints in the database.") unless sprint && project

        work_packages = sprint.work_packages_for(project).limit(3)
        render OpenProject::Common::WorkPackageCardListComponent.new(
          work_packages:,
          project:,
          container: sprint
        ) do |list|
          list.with_header(title: sprint.name, count: work_packages.size) do |header|
            points = work_packages.sum { |w| w.story_points || 0 }
            header.with_description { "#{points} points" }
          end
          list.with_empty_state(title: "Sprint is empty", description: "Drag work packages here")
        end
      end

      def empty_sprint
        sprint = Sprint.first
        project = sprint&.project
        return preview_message("No sprints in the database.") unless sprint && project

        render OpenProject::Common::WorkPackageCardListComponent.new(
          work_packages: [], project:, container: sprint
        ) do |list|
          list.with_header(title: sprint.name, count: 0) do |header|
            header.with_description { "0 points" }
          end
          list.with_empty_state(title: "Sprint is empty", description: "Drag work packages here")
        end
      end

      def inbox
        project = Project.first
        return preview_message("No project in the database.") unless project

        render OpenProject::Common::WorkPackageCardListComponent.new(
          work_packages: [],
          project:,
          container: dom_target(:inbox, project)
        ) do |list|
          list.with_empty_state(title: "Inbox is empty", description: "All caught up",
                               icon: :"op-backlogs")
        end
      end

      def manual_item
        work_package = WorkPackage.first
        project = work_package&.project
        return preview_message("No work packages in the database.") unless work_package && project

        render OpenProject::Common::WorkPackageCardListComponent.new(
          project:,
          container: :manual_item_demo
        ) do |list|
          list.with_empty_state(title: "No items", description: "Manual items can be added by callers")
          list.with_work_package_item(work_package:)
          list.with_item(scheme: :neutral) { "Caller-provided item" }
        end
      end

      private

      # ViewComponent's `Preview.render_args` expects each preview method to
      # return a Hash (it does `result[:template] = …`), so plain string
      # returns fail with "no implicit conversion of Symbol into Integer".
      # Wrap fallback messages in a Blankslate render so they go through the
      # standard hash path.
      def preview_message(text)
        render(Primer::Beta::Blankslate.new) do |b|
          b.with_heading(tag: :h4).with_content(text)
        end
      end
    end
  end
end
