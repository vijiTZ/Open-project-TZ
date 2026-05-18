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

module ::ResourceManagement
  class ResourcePlannersController < BaseController
    include OpTurbo::ComponentStream

    menu_item :resource_management

    before_action :find_project_by_project_id
    before_action :authorize
    before_action :find_resource_planner, only: %i[show edit update destroy toggle_public]
    before_action :build_resource_planner, only: %i[new]

    def index
      @resource_planners = ResourcePlanner
                             .visible(current_user)
                             .where(project: @project)
                             .order(:name)
    end

    def show; end

    def overview; end

    def new
      respond_with_dialog ResourcePlanners::NewDialogComponent.new(
        resource_planner: @resource_planner,
        project: @project
      )
    end

    def edit; end

    def create
      call = ResourcePlanners::CreateService
               .new(user: current_user)
               .call(create_params)

      @resource_planner = call.result

      call.success? ? render_create_success : render_create_failure(call)
    end

    def update
      call = ResourcePlanners::UpdateService
               .new(user: current_user, model: @resource_planner)
               .call(update_params)

      if call.success?
        flash[:notice] = I18n.t(:notice_successful_update)
        redirect_to project_resource_planner_path(@project, @resource_planner)
      else
        @resource_planner = call.result
        render action: :edit, status: :unprocessable_entity
      end
    end

    def destroy
      ResourcePlanners::DeleteService
        .new(user: current_user, model: @resource_planner)
        .call
        .on_success { flash[:notice] = I18n.t(:notice_successful_delete) }
        .on_failure { |call| flash[:error] = call.message }

      redirect_to project_resource_planners_path(@project), status: :see_other
    end

    def toggle_public
      call = ResourcePlanners::TogglePublicService
               .new(user: current_user, model: @resource_planner)
               .call

      if call.success?
        flash[:notice] = I18n.t(:notice_successful_update)
      else
        flash[:error] = call.message
      end

      redirect_back_or_to(
        project_resource_planner_path(@project, @resource_planner), status: :see_other
      )
    end

    private

    def find_resource_planner
      @resource_planner = ResourcePlanner
                            .visible(current_user)
                            .where(project: @project)
                            .find(params[:id])
    end

    def build_resource_planner
      @resource_planner = ResourcePlanner.new(project: @project, principal: current_user)
    end

    def create_params
      extra = %i[default_view_class_name favorite]
      extra << :public if can_manage_public?
      permitted = resource_planner_params(extra:).to_h
      permitted[:favorite] = ActiveModel::Type::Boolean.new.cast(permitted[:favorite]) if permitted.key?(:favorite)
      permitted[:public] = ActiveModel::Type::Boolean.new.cast(permitted[:public]) if permitted.key?(:public)
      permitted.merge(project: @project)
    end

    def update_params
      resource_planner_params
    end

    def resource_planner_params(extra: [])
      params.expect(resource_planner: %i[name start_date end_date] + extra)
    end

    def can_manage_public?
      current_user.allowed_in_project?(:manage_public_resource_planners, @project)
    end

    def render_create_success
      flash[:notice] = I18n.t(:notice_successful_create)
      # TODO: Let's check if we can do a proper turbo update here
      redirect_to project_resource_planners_path(@project)
    end

    def render_create_failure(call)
      update_via_turbo_stream(
        component: ResourcePlanners::FormComponent.new(
          resource_planner: @resource_planner,
          project: @project,
          base_errors: call.errors[:base]
        ),
        status: :unprocessable_entity
      )
      respond_with_turbo_streams
    end
  end
end
