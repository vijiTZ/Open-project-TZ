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

require "rails_helper"

RSpec.describe Backlogs::WorkPackagesController do
  shared_let(:type_feature) { create(:type_feature) }
  shared_let(:type_task) { create(:type_task) }

  current_user { user }

  let(:user) { create(:admin) }
  let(:project) { create(:project) }
  let(:status) { create(:status, name: "status 1", is_default: true) }
  let(:sprint) { create(:sprint, name: "Agile Sprint 1", project:) }
  let(:story) { create(:work_package, status:, sprint:, project:) }

  describe "load_story" do
    subject do
      get :menu,
          params: { project_id: project.id, sprint_id: requested_sprint.id, id: load_story_id },
          format: :html
    end

    let(:load_story_id) { story.id }

    context "when the work package is in the requested sprint" do
      let(:requested_sprint) { sprint }

      it "assigns the visible work package", :aggregate_failures do
        subject
        expect(response).to be_successful
        expect(response).to have_http_status :ok
        expect(assigns(:story)).to eq(story)
      end
    end

    context "when the work package is not in the requested sprint" do
      let(:requested_sprint) { create(:sprint, name: "Other Sprint load_story", project:) }

      it { is_expected.to have_http_status :not_found }
    end
  end

  describe "POST #reorder" do
    it "responds with success", :aggregate_failures do
      post :reorder, params: { project_id: project.id, sprint_id: sprint.id, id: story.id, direction: "highest" },
                     format: :turbo_stream

      expect(response).to be_successful
      expect(response).to have_http_status :ok
      expect(response).to have_turbo_stream action: "replace", target: "backlogs-sprint-component-#{sprint.id}"
      assert_select %(turbo-stream[action="replace"][target="backlogs-sprint-component-#{sprint.id}"][method="morph"])
      expect(assigns(:project)).to eq(project)
      expect(assigns(:sprint)).to eq(sprint)
      expect(assigns(:story)).to eq(story)
    end

    context "when service call fails" do
      let(:service_result) { ServiceResult.failure(message: "Something went wrong") }

      before do
        update_service = instance_double(Stories::UpdateService, call: service_result)

        allow(Stories::UpdateService)
          .to receive(:new)
          .and_return(update_service)
      end

      it "renders an error flash with 422", :aggregate_failures do
        post :reorder, params: { project_id: project.id, sprint_id: sprint.id, id: story.id, direction: "highest" },
                       format: :turbo_stream

        expect(response).to have_http_status :unprocessable_entity
        expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        expect(response).not_to have_turbo_stream action: "replace", target: "backlogs-sprint-component-#{sprint.id}"
      end
    end
  end

  describe "PUT #move" do
    let(:story_in_sprint) { create(:work_package, status:, sprint:, project:) }

    context "with another Sprint as target" do
      let(:other_sprint) { create(:sprint, name: "Agile Sprint 2", project:) }

      it "responds with success and moves story to another Sprint", :aggregate_failures do
        put :move, params: {
                     project_id: project.id,
                     sprint_id: sprint.id,
                     id: story_in_sprint.id,
                     target_id: "sprint:#{other_sprint.id}",
                     prev_id: nil
                   },
                   format: :turbo_stream

        expect(response).to be_successful
        expect(response).to have_http_status :ok
        expect(response).to have_turbo_stream action: "replace", target: "backlogs-sprint-component-#{sprint.id}"
        expect(response).to have_turbo_stream action: "replace", target: "backlogs-sprint-component-#{other_sprint.id}"
        assert_select %(turbo-stream[action="replace"][target="backlogs-sprint-component-#{sprint.id}"])
        assert_select %(turbo-stream[action="replace"][target="backlogs-sprint-component-#{other_sprint.id}"])
        expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        expect(assigns(:project)).to eq(project)
        expect(assigns(:sprint)).to eq(sprint)
        expect(assigns(:story)).to eq(story_in_sprint)
      end
    end

    context "with Inbox as target" do
      let!(:existing_inbox_item) { create(:work_package, project:, status:, position: 1) }

      it "responds with success and moves story to Inbox at the given position", :aggregate_failures do
        put :move, params: {
                     project_id: project.id,
                     sprint_id: sprint.id,
                     id: story_in_sprint.id,
                     target_id: "inbox",
                     prev_id: existing_inbox_item.id
                   },
                   format: :turbo_stream

        expect(response).to be_successful
        expect(response).to have_http_status :ok
        expect(response).to have_turbo_stream action: "replace", target: "backlogs-sprint-component-#{sprint.id}"
        expect(response).to have_turbo_stream action: "replace", target: "backlogs-backlog-component-#{project.id}"
        assert_select %(turbo-stream[action="replace"][target="backlogs-sprint-component-#{sprint.id}"])
        assert_select %(turbo-stream[action="replace"][target="backlogs-backlog-component-#{project.id}"][method="morph"])
        expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        expect(assigns(:project)).to eq(project)
        expect(assigns(:sprint)).to eq(sprint)
        expect(assigns(:story)).to eq(story_in_sprint)
        expect(story_in_sprint.reload.sprint).to be_nil
        expect(story_in_sprint.reload.position).to eq(2)
      end

      context "when all=1 with an inbox over the pagination threshold" do
        before do
          stub_const("Backlogs::InboxComponent::TRUNCATE_MIDDLE", 2)
          create_list(:work_package, 4, project:, status:)
        end

        it "replaces the inbox without a show-more row in the stream" do
          put :move, params: {
                       project_id: project.id,
                       sprint_id: sprint.id,
                       id: story_in_sprint.id,
                       target_id: "inbox",
                       prev_id: existing_inbox_item.id,
                       all: "1"
                     },
                     format: :turbo_stream

          expect(response).to be_successful
          expect(response.body).not_to include("inbox_project_#{project.id}_show_more")
        end
      end
    end

    context "when service call fails" do
      let(:other_sprint) { create(:sprint, name: "Agile Sprint 2", project:) }
      let(:service_result) { ServiceResult.failure(message: "Something went wrong") }

      before do
        update_service = instance_double(Stories::UpdateService, call: service_result)

        allow(Stories::UpdateService)
          .to receive(:new)
          .and_return(update_service)
      end

      it "renders an error flash with 422", :aggregate_failures do
        put :move, params: {
                     project_id: project.id,
                     sprint_id: sprint.id,
                     id: story_in_sprint.id,
                     target_id: "sprint:#{other_sprint.id}",
                     position: 1
                   },
                   format: :turbo_stream

        expect(response).to have_http_status :unprocessable_entity
        expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        expect(response).not_to have_turbo_stream action: "replace", target: "backlogs-sprint-component-#{sprint.id}"
      end
    end
  end

  describe "GET #menu" do
    subject do
      get :menu, params: { project_id: project.id, sprint_id: sprint.id, id: story.id }, format: :html
    end

    it "returns deferred action menu list HTML", :aggregate_failures do
      subject
      expect(response).to have_http_status :ok
      expect(response.body).to include(I18n.t(:"js.button_open_details"))
    end

    context "when all=1 is in params" do
      subject do
        get :menu,
            params: { project_id: project.id, sprint_id: sprint.id, id: story.id, all: "1" },
            format: :html
      end

      it "embeds the all query in deferred action URLs" do
        subject
        expect(response.body).to match(/all=1/)
      end
    end

    context "when another open sprint exists" do
      let!(:other_open_sprint) { create(:sprint, name: "Sprint 2", project:) }

      before { allow(Backlogs::StoryMenuListComponent).to receive(:new).and_call_original }

      it "passes open_sprints_exist: true to the menu component" do
        subject

        expect(Backlogs::StoryMenuListComponent)
          .to have_received(:new)
          .with(hash_including(open_sprints_exist: true))
      end
    end

    context "when no other open sprints exist" do
      before { allow(Backlogs::StoryMenuListComponent).to receive(:new).and_call_original }

      it "passes open_sprints_exist: false to the menu component" do
        subject

        expect(Backlogs::StoryMenuListComponent)
          .to have_received(:new)
          .with(hash_including(open_sprints_exist: false))
      end
    end

    context "with a user lacking project permission" do
      let(:user) { create(:user) }

      it "responds with 404" do
        subject
        expect(response).to have_http_status :not_found
      end
    end
  end

  describe "GET #move_to_sprint_dialog" do
    subject do
      get :move_to_sprint_dialog,
          params: { project_id: project.id, sprint_id: sprint.id, id: story.id },
          format: :turbo_stream
    end

    context "when user has manage_sprint_items permission" do
      it "responds with a dialog turbo stream", :aggregate_failures do
        subject
        expect(response).to be_successful
        expect(response).to have_turbo_stream action: "dialog"
      end
    end

    context "when all=1 is in params" do
      subject do
        get :move_to_sprint_dialog,
            params: { project_id: project.id, sprint_id: sprint.id, id: story.id, all: "1" },
            format: :turbo_stream
      end

      it "embeds the all query in the dialog form action URL" do
        subject
        expect(response.body).to match(/all=1/)
      end
    end

    context "with a user lacking manage_sprint_items permission" do
      let(:user) { create(:user, member_with_permissions: { project => %i[view_sprints view_work_packages] }) }

      it "responds with 403" do
        subject
        expect(response).to have_http_status :forbidden
      end
    end

    context "with a user lacking project permission" do
      let(:user) { create(:user) }

      it "responds with 404" do
        subject
        expect(response).to have_http_status :not_found
      end
    end
  end
end
