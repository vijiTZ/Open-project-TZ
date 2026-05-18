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

RSpec.describe Backlogs::InboxController do
  current_user { user }

  let(:user) { create(:admin) }
  let(:project) { create(:project) }
  let!(:work_packages) { create_list(:work_package, 5, project:) }
  let(:work_package) { create(:work_package, project:) }
  let(:setup_service_result) do
    allow(Stories::UpdateService)
      .to receive(:new)
      .and_return(instance_double(Stories::UpdateService, call: service_result))
  end

  before do
    setup_service_result if defined?(service_result)
    subject
  end

  shared_examples_for "checks permissions for private projects" do
    context "with a private project" do
      let(:project) { create(:private_project) }

      context "when the user is not a member" do
        let(:user) { create(:user) }

        it "responds with 404" do
          expect(response).to have_http_status :not_found
        end
      end

      context "when the user is a member with required permissions" do
        let(:user) do
          create(:user, member_with_permissions: { project => %i[manage_sprint_items view_sprints view_work_packages] })
        end

        it "responds successfully" do
          expect(response).to be_successful
        end
      end
    end
  end

  describe "POST #reorder" do
    subject do
      post :reorder,
           params: { project_id: project.id, id: work_package.id, direction: "highest" },
           format: :turbo_stream
    end

    context "when service call succeeds" do
      it "replaces the backlog component and responds with turbo streams", :aggregate_failures do
        expect(response).to be_successful
        expect(response).to have_turbo_stream action: "replace", target: "backlogs-backlog-component-#{project.id}"
        expect(assigns(:project)).to eq(project)
        expect(assigns(:work_package)).to eq(work_package)
      end

      it "moves the work package to the first place" do
        expect { work_package.reload }
          .to change(work_package, :position).from(6).to(1)
        expect { work_packages.each(&:reload) }
          .to change { work_packages.map(&:position) }
          .from([1, 2, 3, 4, 5])
          .to([2, 3, 4, 5, 6])
      end
    end

    context "when all=1 with an inbox over the pagination threshold" do
      before do
        stub_const("Backlogs::InboxComponent::TRUNCATE_MIDDLE", 2)
      end

      let!(:work_packages) { create_list(:work_package, 5, project:) }
      let(:work_package) { work_packages.first }

      subject do
        post :reorder,
             params: { project_id: project.id, id: work_package.id, direction: "lower", all: "1" },
             format: :turbo_stream
      end

      it "replaces the inbox without a show-more row in the stream" do
        expect(response).to be_successful
        expect(response.body).not_to include("inbox_project_#{project.id}_show_more")
      end
    end

    context "when service call fails" do
      let(:service_result) { ServiceResult.failure(message: "Something went wrong") }

      it "renders an error flash with 422", :aggregate_failures do
        expect(response).to have_http_status :unprocessable_entity
        expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        expect(response).not_to have_turbo_stream action: "replace",
                                                  target: "backlogs-backlog-component-#{project.id}"
      end
    end

    context "with a user lacking project permission" do
      let(:user) { create(:user) }

      it "responds with 404" do
        expect(response).to have_http_status :not_found
      end
    end

    it_behaves_like "checks permissions for private projects"
  end

  describe "PUT #move" do
    let(:sprint) { create(:sprint, name: "Sprint 1", project:) }
    let(:target_id) { "sprint:#{sprint.id}" }
    let(:prev_id) { 1 }

    subject do
      put :move,
          params: {
            project_id: project.id,
            id: work_package.id,
            target_id:,
            prev_id:
          },
          format: :turbo_stream
    end

    context "when moving to an Sprint" do
      it "replaces both the inbox and target sprint components", :aggregate_failures do
        expect(response).to be_successful
        expect(response).to have_turbo_stream action: "replace",
                                              target: "backlogs-backlog-component-#{project.id}"
        expect(response).to have_turbo_stream action: "replace",
                                              target: "backlogs-sprint-component-#{sprint.id}"

        # Flash message is omitted here on purpose (#73600)
        expect(response).not_to have_turbo_stream action: "flash", target: "op-primer-flash-component"
      end
    end

    context "when reordering within the Inbox" do
      let(:target_id) { "inbox" }
      let(:prev_id) { work_packages.first.id }

      it "replaces only the inbox component without a flash", :aggregate_failures do
        expect(response).to be_successful
        expect(response).to have_turbo_stream action: "replace",
                                              target: "backlogs-backlog-component-#{project.id}"
        expect(response).not_to have_turbo_stream action: "flash", target: "op-primer-flash-component"
      end

      it "moves the work package to position 2" do
        expect { work_package.reload }
          .to change(work_package, :position).from(6).to(2)
        expect { work_packages.each(&:reload) }
          .to change { work_packages.map(&:position) }
          .from([1, 2, 3, 4, 5])
          .to([1, 3, 4, 5, 6])
      end
    end

    context "when no prev_id is provided" do
      let!(:work_packages) { create_list(:work_package, 5, project:, sprint:) }
      let(:prev_id) { nil }

      it "places the work package at the top of the sprint" do
        expect { work_package.reload }
          .to not_change(work_package, :position)
        expect { work_packages.each(&:reload) }
          .to change { work_packages.map(&:position) }
                .from([1, 2, 3, 4, 5])
                .to([2, 3, 4, 5, 6])
      end
    end

    context "when all=1 with an inbox over the pagination threshold" do
      before do
        stub_const("Backlogs::InboxComponent::TRUNCATE_MIDDLE", 2)
      end

      let!(:work_packages) { create_list(:work_package, 5, project:) }
      let(:target_id) { "inbox" }
      let(:prev_id) { work_packages.first.id }

      subject do
        put :move,
            params: {
              project_id: project.id,
              id: work_package.id,
              target_id:,
              prev_id:,
              all: "1"
            },
            format: :turbo_stream
      end

      it "replaces the inbox without a show-more row in the stream" do
        expect(response).to be_successful
        expect(response.body).not_to include("inbox_project_#{project.id}_show_more")
      end
    end

    context "when service call fails" do
      let(:service_result) { ServiceResult.failure(message: "Move failed") }

      it "renders an error flash with 422 and does not replace components", :aggregate_failures do
        expect(response).to have_http_status :unprocessable_entity
        expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        expect(response).not_to have_turbo_stream action: "replace",
                                                  target: "backlogs-backlog-component-#{project.id}"
      end
    end

    context "with a user lacking project permission" do
      let(:user) { create(:user) }

      it "responds with 404" do
        expect(response).to have_http_status :not_found
      end
    end

    it_behaves_like "checks permissions for private projects"
  end

  describe "GET #menu" do
    subject do
      get :menu, params: { project_id: project.id, id: work_package.id }, format: :html
    end

    shared_examples "it renders the menu" do
      it "returns deferred action menu list HTML", :aggregate_failures do
        subject
        expect(response).to have_http_status :ok
        expect(response.body).to include(I18n.t(:"js.button_open_details"))
      end

      context "when all=1 is in params" do
        subject do
          get :menu, params: { project_id: project.id, id: work_package.id, all: "1" }, format: :html
        end

        it "embeds the all query in deferred action URLs" do
          subject
          expect(response.body).to match(/all=1/)
        end
      end

      context "when the work package belongs to another project" do
        let(:other_project) { create(:project) }
        let(:work_package) { create(:work_package, project: other_project) }

        it "responds with 404" do
          expect(response).to have_http_status :not_found
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

    shared_examples "renders actions to move in both directions" do
      it "renders actions to move in both directions", :aggregate_failures do
        expect(response.body).to include(I18n.t(:label_sort_highest))
        expect(response.body).to include(I18n.t(:label_sort_higher))
        expect(response.body).to include(I18n.t(:label_sort_lower))
        expect(response.body).to include(I18n.t(:label_sort_lowest))
      end
    end

    shared_examples "renders only actions to move to bottom" do
      it "renders only actions to move to bottom", :aggregate_failures do
        expect(response.body).not_to include(I18n.t(:label_sort_highest))
        expect(response.body).not_to include(I18n.t(:label_sort_higher))
        expect(response.body).to include(I18n.t(:label_sort_lower))
        expect(response.body).to include(I18n.t(:label_sort_lowest))
      end
    end

    shared_examples "renders only actions to move to top" do
      it "renders only actions to move to top", :aggregate_failures do
        expect(response.body).to include(I18n.t(:label_sort_highest))
        expect(response.body).to include(I18n.t(:label_sort_higher))
        expect(response.body).not_to include(I18n.t(:label_sort_lower))
        expect(response.body).not_to include(I18n.t(:label_sort_lowest))
      end
    end

    shared_examples "renders no actions to move" do
      it "renders no actions to move", :aggregate_failures do
        expect(response.body).not_to include(I18n.t(:label_sort_highest))
        expect(response.body).not_to include(I18n.t(:label_sort_higher))
        expect(response.body).not_to include(I18n.t(:label_sort_lower))
        expect(response.body).not_to include(I18n.t(:label_sort_lowest))
      end
    end

    let!(:bucket1) { create(:backlog_bucket, project:) }
    let!(:bucket2) { create(:backlog_bucket, project:) }

    let!(:bucket1_lone_work_package) { create(:work_package, project:, backlog_bucket: bucket1) }
    let!(:bucket2_work_packages) { create_list(:work_package, 5, project:, backlog_bucket: bucket2) }

    it_behaves_like "checks permissions for private projects"

    it_behaves_like "it renders the menu"

    context "for work package at the top of inbox" do
      let(:work_package) { work_packages.first }

      it_behaves_like "renders only actions to move to bottom"
    end

    context "for work package at the bottom of inbox" do
      let(:work_package) { work_packages.last }

      it_behaves_like "renders only actions to move to top"
    end

    context "for work package in the middle of inbox" do
      let(:work_package) { work_packages.third }

      it_behaves_like "renders actions to move in both directions"
    end

    context "for a work package alone in the bucket" do
      let(:work_package) { bucket1_lone_work_package }

      it_behaves_like "renders no actions to move"
    end

    context "for work package at the top of bucket with multiple" do
      let(:work_package) { bucket2_work_packages.first }

      it_behaves_like "renders only actions to move to bottom"
    end

    context "for work package in the middle of bucket with multiple" do
      let(:work_package) { bucket2_work_packages.third }

      it_behaves_like "renders actions to move in both directions"
    end

    context "for work package at the bottom of bucket with multiple" do
      let(:work_package) { bucket2_work_packages.last }

      it_behaves_like "renders only actions to move to top"
    end
  end

  describe "GET #move_to_sprint_dialog" do
    let!(:sprint) { create(:sprint, name: "Sprint 1", project:) }

    subject do
      get :move_to_sprint_dialog,
          params: { project_id: project.id, id: work_package.id },
          format: :turbo_stream
    end

    context "when user has manage_sprint_items permission" do
      it "responds with a dialog turbo stream", :aggregate_failures do
        expect(response).to be_successful
        expect(response).to have_turbo_stream action: "dialog"
      end
    end

    context "when all=1 is in params" do
      subject do
        get :move_to_sprint_dialog,
            params: { project_id: project.id, id: work_package.id, all: "1" },
            format: :turbo_stream
      end

      it "embeds the all query in the dialog form action URL" do
        subject
        expect(response.body).to match(/all=1/)
      end
    end

    context "with a user lacking manage_sprint_items permission" do
      let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }

      it "responds with 403" do
        expect(response).to have_http_status :forbidden
      end
    end

    context "with a user lacking project permission" do
      let(:user) { create(:user) }

      it "responds with 404" do
        expect(response).to have_http_status :not_found
      end
    end

    it_behaves_like "checks permissions for private projects"
  end
end
