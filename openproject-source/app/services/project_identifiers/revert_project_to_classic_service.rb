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
  # Reverts a single project back to classic identifier mode by restoring its
  # project identifier to the most-recent classic-format slug from FriendlyId
  # history. If no classic slug exists (e.g. the project was created in semantic
  # mode), a new classic identifier is generated via Project.suggest_identifier.
  #
  # WP sequence_number/identifier, WorkPackageSemanticAlias rows, and
  # wp_sequence_counter are intentionally left intact so that a back-switch to
  # semantic mode can resume without data loss.
  class RevertProjectToClassicService
    def initialize(project)
      @project = project
    end

    def call
      restore_classic_identifier
    end

    private

    attr_reader :project

    def restore_classic_identifier
      generator = ProjectIdentifiers::ClassicIdentifierSuggestionGenerator.new
      classic = generator.restore_identifier(project) || generator.suggest_identifier(project.name)
      # Suppress notifications: this is a background system operation, not a user edit.
      Journal::NotificationConfiguration.with(false) do
        project.update!(identifier: classic)
      end
    end
  end
end
