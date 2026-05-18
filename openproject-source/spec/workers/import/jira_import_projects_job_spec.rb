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

RSpec.describe Import::JiraImportProjectsJob, :webmock do
  let(:jira) { create(:jira) }
  let(:author) { create(:user) }
  let(:jira_import) do
    create(:jira_import, jira:, author:, projects: [{ "id" => "10242", "key" => "DYX", "name" => "Zombie Engine" }])
  end

  let(:jira_project_payload) { JSON.parse(Rails.root.join("spec/fixtures/import/jira/project.json").read) }
  let(:jira_issue_payload) { JSON.parse(Rails.root.join("spec/fixtures/import/jira/issue.json").read) }
  let(:jira_user_payload) { JSON.parse(Rails.root.join("spec/fixtures/import/jira/user.json").read) }

  let!(:jira_project) do
    create(:jira_project,
           jira:,
           jira_import:,
           jira_project_id: "10242",
           payload: jira_project_payload)
  end

  let!(:default_status) { create(:default_status) }

  describe "#perform" do
    context "when a project with the same identifier already exists" do
      let!(:existing_project) { create(:project, identifier: "dyx", name: "Existing Project") }

      it "raises an error with the taken identifier and existing project info" do
        expect { described_class.new.perform(jira_import.id) }
          .to raise_error("You are trying to import a project with an already used identifier: dyx. " \
                          "Please update the project identifier in Jira then click on Retry.")
      end
    end

    context "when importing a full project with issues, comments, and attachments" do
      let!(:jira_issue) do
        create(:jira_issue,
               jira:,
               jira_import:,
               jira_issue_id: "10100",
               jira_project_id: jira_project.id,
               payload: jira_issue_payload)
      end

      let!(:jira_issue_type) do
        create(:jira_issue_type,
               jira:,
               jira_import:,
               jira_issue_type_id: "10100",
               payload: { "id" => "10100", "name" => "Task" })
      end

      let!(:jira_status) do
        create(:jira_status,
               jira:,
               jira_import:,
               jira_status_id: "3",
               payload: { "id" => "3", "name" => "In Progress" })
      end

      let!(:jira_priority) do
        create(:jira_priority,
               jira:,
               jira_import:,
               jira_priority_id: "1",
               payload: { "id" => "1", "name" => "Highest" })
      end

      let!(:jira_user) do
        create(:jira_user,
               jira:,
               jira_import:,
               jira_user_key: "JIRAUSER10000",
               payload: jira_user_payload)
      end

      let!(:op_user) { create(:user, login: "p.balashou", mail: "p.balashou@openproject.com") }

      let!(:jira_user_reference) do
        create(:jira_open_project_reference,
               jira:,
               jira_import:,
               jira_entity_class: "Import::JiraUser",
               jira_entity_id: jira_user.id.to_s,
               op_entity_class: "User",
               op_entity_id: op_user.id.to_s)
      end

      let(:attachment_content) { Rails.root.join("spec/fixtures/files/image.png").binread }

      include_context "with ssrf stubs"

      before do
        stub_request(:get, "https://jira-software.local/secure/attachment/10000/solid-color-image.png")
          .to_return(status: 200, body: attachment_content, headers: { "Content-Type" => "image/png" })
      end

      it "creates the project in OpenProject" do
        expect { described_class.new.perform(jira_import.id) }
          .to change(Project, :count).by(1)

        project = Project.find_by(identifier: "dyx")
        expect(project).to be_present
        expect(project.name).to eq("Zombie Engine")
      end

      it "creates the work package with correct attributes" do
        described_class.new.perform(jira_import.id)

        work_package = WorkPackage.find_by(subject: "Kanban cards represent work items")
        expect(work_package).to be_present
        expect(work_package.type.name).to eq("Task")
        expect(work_package.status.name).to eq("In Progress")
        expect(work_package.priority.name).to eq("Highest")
        expect(work_package.assigned_to).to eq(op_user)
      end

      it "creates a comment on the work package" do
        described_class.new.perform(jira_import.id)

        work_package = WorkPackage.find_by(subject: "Kanban cards represent work items")
        expect(work_package.journals.where(notes: "Created 2 hours 36 minutes ago").count).to be 1
      end

      it "creates an attachment on the work package" do
        described_class.new.perform(jira_import.id)

        work_package = WorkPackage.find_by(subject: "Kanban cards represent work items")
        expect(work_package.attachments.count).to eq(1)
        expect(work_package.attachments.first.filename).to eq("solid-color-image.png")
      end

      it "creates references for imported entities" do
        expect { described_class.new.perform(jira_import.id) }
          .to change(Import::JiraOpenProjectReference, :count).by_at_least(4)
      end
    end

    context "when project creation fails with a general error" do
      before do
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Projects::CreateService).to receive(:call).and_return(
          ServiceResult.failure(message: "Something went wrong during project creation")
        )
        # rubocop:enable RSpec/AnyInstance
      end

      it "raises the error message" do
        expect { described_class.new.perform(jira_import.id) }
          .to raise_error("Something went wrong during project creation")
      end
    end
  end
end
