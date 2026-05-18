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
    class WorkPackageCardComponent < ApplicationComponent
      include Primer::ClassNameHelper
      include OpPrimer::ComponentHelpers

      renders_one :metric, Primer::Content
      renders_one :menu, ->(src: nil, button_aria_label: nil, **system_arguments) {
        Menu.new(
          work_package:,
          src:,
          button_aria_label:,
          **system_arguments
        )
      }

      attr_reader :work_package, :menu_src

      # @param work_package [WorkPackage] the work package this card represents.
      # @param menu_src [String, NilClass] optional lazy menu source. Prefer the
      #   `with_menu(src:)` slot for new call sites.
      def initialize(work_package:, menu_src: nil)
        super()

        @work_package = work_package
        @menu_src = menu_src
      end
    end
  end
end
