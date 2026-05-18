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

require "spec_helper"
require "rack/test"

RSpec.describe "API v3 Meeting Sections sub-resource", content_type: :json do
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:project) { create(:project, enabled_module_names: %w[meetings]) }

  let(:permissions) { %i[view_meetings manage_agendas] }
  let(:current_user) do
    create(:user, member_with_permissions: { project => permissions })
  end
  let(:meeting) { create(:meeting, project:, author: current_user) }
  let!(:section) { create(:meeting_section, meeting:, title: "First Section") }

  before do
    login_as current_user
  end

  describe "GET /api/v3/meetings/:meeting_id/sections" do
    let(:path) { api_v3_paths.meeting_sections(meeting.id) }

    before { get path }

    it "returns 200 and lists sections" do
      expect(last_response).to have_http_status(:ok)

      expect(last_response.body)
        .to be_json_eql("Collection".to_json)
        .at_path("_type")
    end

    context "without view_meetings permission" do
      let(:permissions) { [] }

      it "returns 404" do
        expect(last_response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v3/meetings/:meeting_id/sections" do
    let(:path) { api_v3_paths.meeting_sections(meeting.id) }
    let(:body) do
      {
        title: "New Section"
      }.to_json
    end

    subject(:response) { post path, body }

    it "responds with 201" do
      expect(response).to have_http_status(:created)
    end

    it "creates the section" do
      response
      expect(meeting.sections.find_by(title: "New Section")).to be_present
    end

    it "returns the created section" do
      expect(response.body)
        .to be_json_eql("MeetingSection".to_json)
        .at_path("_type")

      expect(response.body)
        .to be_json_eql("New Section".to_json)
        .at_path("title")
    end

    context "without manage_agendas permission" do
      let(:permissions) { %i[view_meetings] }

      it "returns 403" do
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v3/meetings/:meeting_id/sections/:id" do
    let(:path) { api_v3_paths.meeting_section(meeting.id, section.id) }

    before { get path }

    it "returns 200 and the section" do
      expect(last_response).to have_http_status(:ok)

      expect(last_response.body)
        .to be_json_eql("MeetingSection".to_json)
        .at_path("_type")

      expect(last_response.body)
        .to be_json_eql(section.id.to_json)
        .at_path("id")
    end

    context "with a section from another meeting" do
      let(:other_meeting) { create(:meeting, project:, author: current_user) }
      let(:path) { api_v3_paths.meeting_section(other_meeting.id, section.id) }

      it "returns 404" do
        expect(last_response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /api/v3/meetings/:meeting_id/sections/:id" do
    let(:path) { api_v3_paths.meeting_section(meeting.id, section.id) }
    let(:body) do
      {
        title: "Updated Section Title"
      }.to_json
    end

    subject(:response) { patch path, body }

    it "responds with 200" do
      expect(response).to have_http_status(:ok)
    end

    it "updates the section" do
      response
      expect(section.reload.title).to eq("Updated Section Title")
    end

    context "without manage_agendas permission" do
      let(:permissions) { %i[view_meetings] }

      it "returns 403" do
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /api/v3/meetings/:meeting_id/sections/:id" do
    let(:path) { api_v3_paths.meeting_section(meeting.id, section.id) }

    before { delete path }

    subject { last_response }

    context "with required permissions" do
      it "responds with 204" do
        expect(subject.status).to eq 204
      end

      it "deletes the section" do
        expect(MeetingSection).not_to exist(section.id)
      end
    end

    context "without manage_agendas permission" do
      let(:permissions) { %i[view_meetings] }

      it_behaves_like "unauthorized access"
    end
  end
end
