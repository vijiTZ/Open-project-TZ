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
  class WorkPackagesController < BaseController
    include OpTurbo::ComponentStream
    include Backlogs::Move

    before_action :load_story

    # Deferred ActionMenu items (Primer include-fragment).
    def menu
      max_position = @allowed_stories.maximum(:position) || 0
      open_sprints_exist = Sprint.for_project(@project).visible.not_completed.where.not(id: @sprint.id).exists?

      render(Backlogs::StoryMenuListComponent.new(
               story: @story,
               sprint: @sprint,
               project: @project,
               max_position:,
               open_sprints_exist:,
               current_user:
             ),
             layout: false)
    end

    # Move a story from an Sprint to another Sprint, or the Inbox.
    def move
      # The update service reloads the story internally (via #move_after),
      # so we memoize the previous sprint_id before the call.
      sprint_id_was = @story.sprint_id

      move_attributes = move_attributes_from_target
      unless move_work_package(move_attributes).success?
        return respond_with_turbo_streams(status: :unprocessable_entity)
      end

      if target_inbox?(move_attributes)
        moved_to_inbox
      elsif target_sprint?(move_attributes) && @story.sprint_id != sprint_id_was
        moved_to_sprint
      end

      respond_with_turbo_streams
    end

    def move_to_sprint_dialog
      respond_with_dialog Backlogs::MoveToSprintDialogComponent.new(
        work_package: @story,
        project: @project,
        move_action: move_project_backlogs_work_package_path(
          @project, @sprint, @story, helpers.all_backlogs_params
        )
      )
    end

    def reorder
      call = Stories::UpdateService
        .new(user: current_user, story: @story)
        .call(attributes: { move_to: reorder_param })

      unless call.success?
        render_error_flash_message_via_turbo_stream(
          message: I18n.t(:notice_unsuccessful_update_with_reason, reason: call.message)
        )
        return respond_with_turbo_streams(status: :unprocessable_entity)
      end

      replace_sprint_component_via_turbo_stream(sprint: @sprint)

      respond_with_turbo_streams
    end

    private

    def move_work_package(move_attributes)
      call = update_story_with_target_and_position(attributes: move_attributes)

      if call.success?
        # Update source component so that the moved story disappears
        replace_sprint_component_via_turbo_stream(sprint: @sprint)
      else
        render_error_flash_message_via_turbo_stream(
          message: I18n.t(:notice_unsuccessful_update_with_reason, reason: call.message)
        )
      end

      call
    end

    def update_story_with_target_and_position(attributes:)
      Stories::UpdateService
        .new(user: current_user, story: @story)
        .call(attributes:, **position_attributes)
    end

    def moved_to_inbox
      render_success_flash_message_via_turbo_stream(
        message: I18n.t(:notice_successful_move, from: @sprint.name, to: I18n.t(:label_inbox))
      )
      inbox_work_packages = WorkPackage.backlogs_inbox_for(project: @project)
      buckets = BacklogBucket.for_project(@project)

      replace_via_turbo_stream(
        component: Backlogs::BacklogComponent.new(inbox_work_packages:,
                                                  buckets:,
                                                  project: @project),
        method: :morph
      )
    end

    def moved_to_sprint
      moved_to(new_sprint: @story.sprint)
    end

    def moved_to(new_sprint:)
      render_success_flash_message_via_turbo_stream(
        message: I18n.t(:notice_successful_move, from: @sprint.name, to: new_sprint.name)
      )

      # Update the target component so that the moved story shows up
      replace_sprint_component_via_turbo_stream(sprint: new_sprint)
    end

    def target_sprint?(move_attributes)
      move_attributes[:sprint_id].present?
    end

    def target_inbox?(move_attributes)
      move_attributes.key?(:sprint_id) && move_attributes[:sprint_id].nil?
    end

    def replace_sprint_component_via_turbo_stream(sprint:)
      replace_via_turbo_stream(
        component: Backlogs::SprintComponent.new(sprint:, project: @project),
        method: :morph
      )
    end

    def load_story
      @allowed_stories = WorkPackage.visible.where(sprint: @sprint, project: @project)
      @story = @allowed_stories.find(params[:id])
    end

    def move_params
      params.require(%i[target_id])
      params.permit(:position, :prev_id, :target_id)
    end

    def position_attributes
      if move_params.has_key?(:prev_id)
        { prev_id: move_params[:prev_id].to_i }
      elsif move_params.has_key?(:position)
        { position: move_params[:position].to_i }
      else
        {}
      end
    end

    def reorder_param
      params.expect(:direction)
    end
  end
end
