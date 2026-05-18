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

module ProjectIdentifiers
  # Returns the set of project IDs that still need backfilling before the
  # instance can be switched to semantic identifier mode. Three buckets:
  #
  # * projects whose identifier is not in valid semantic format
  # * projects that have work packages with no sequence_number yet
  # * projects that have work packages whose identifier doesn't match
  #   the current project prefix (stale due to renames or cross-project moves)
  module PendingProjectsFinder
    def self.project_ids
      projects_with_bad_identifier | projects_with_unsequenced_wps | projects_with_stale_wps
    end

    class << self
      private

      def projects_with_bad_identifier
        ProjectIdentifiers::IdentifierAutofix::ProblematicIdentifiers.new.scope.ids.to_set
      end

      def projects_with_unsequenced_wps
        WorkPackage.unsequenced.distinct.pluck(:project_id).to_set
      end

      def projects_with_stale_wps
        WorkPackage.non_semantic.distinct.pluck(:project_id).to_set
      end
    end
  end
end
