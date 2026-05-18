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
  # TODO: remove this very temporary concern
  module Move
    extend ActiveSupport::Concern

    private

    def move_attributes_from_target
      target_type, target_id = move_params[:target_id].split(":", 2)

      case target_type
      when "sprint"
        { backlog_bucket_id: nil, sprint_id: target_id }
      when "backlog_bucket"
        { backlog_bucket_id: target_id, sprint_id: nil }
      when "inbox"
        { backlog_bucket_id: nil, sprint_id: nil }
      else
        raise ArgumentError, "target_type must be one of: backlog_bucket, sprint, inbox."
      end
    end
  end
end
