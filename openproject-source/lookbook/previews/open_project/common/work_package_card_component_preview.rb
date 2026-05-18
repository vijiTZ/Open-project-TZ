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
    class WorkPackageCardComponentPreview < ViewComponent::Preview
      def default
        work_package = WorkPackage.first
        return preview_message("No work packages in the database.") unless work_package

        render OpenProject::Common::WorkPackageCardComponent.new(
          work_package:
        )
      end

      def with_metric
        work_package = WorkPackage.first
        return preview_message("No work packages in the database.") unless work_package

        render OpenProject::Common::WorkPackageCardComponent.new(
          work_package:
        ) do |card|
          card.with_metric_content(10)
        end
      end

      def with_menu
        work_package = WorkPackage.first
        return preview_message("No work packages in the database.") unless work_package

        render OpenProject::Common::WorkPackageCardComponent.new(
          work_package:
        ) do |card|
          card.with_menu do |menu|
            menu.with_item(label: "Open", href: "/work_packages/#{work_package.id}")
          end
        end
      end

      private

      def preview_message(text)
        render(Primer::Beta::Blankslate.new) do |b|
          b.with_heading(tag: :h4).with_content(text)
        end
      end
    end
  end
end
