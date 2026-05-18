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

module Meetings
  class EmailUpdatesBannerComponent < ApplicationComponent
    def initialize(meeting, override: nil, type: nil)
      super
      @meeting = meeting
      @override = override
      @type = type
    end

    def call
      render(Primer::Alpha::Banner.new(description:, scheme:, icon:, data: { "test-selector": "notifications-banner" }))
    end

    private

    def type
      if @type == :participants
        "participants"
      elsif @meeting.is_a?(RecurringMeeting) || (@meeting.recurring? && @meeting.templated?)
        "template"
      elsif @meeting.recurring?
        "occurrence"
      else
        "onetime"
      end
    end

    def status
      if @override.present?
        @override.to_s
      elsif @meeting.notify?
        "enabled"
      else
        "disabled"
      end
    end

    def description
      I18n.t("meeting.notifications.banner.#{type}.#{banner_status}")
    end

    def scheme
      banner_status == "disabled" ? :warning : :default
    end

    def icon
      banner_status == "disabled" ? nil : :info
    end

    def banner_status
      return "draft_disabled" if type == "participants" && status == "disabled" && @meeting.draft?

      status
    end
  end
end
