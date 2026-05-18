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

RSpec.describe WorkPackages::Admin::Settings::IdentifierSettingsFormComponent, type: :component do
  subject(:component) { described_class.new(state:) }

  let(:empty_result) do
    ProjectIdentifiers::IdentifierAutofix::PreviewQuery::Result.new(projects_data: [], total_count: 0)
  end

  def render_component(component)
    with_controller_class(Admin::Settings::WorkPackagesIdentifierController) do
      with_request_url("/admin/settings/work_packages_identifier") do
        render_inline(component)
      end
    end
  end

  before do
    preview_stub = instance_double(ProjectIdentifiers::IdentifierAutofix::PreviewQuery, call: empty_result)
    allow(ProjectIdentifiers::IdentifierAutofix::PreviewQuery).to receive(:new).and_return(preview_stub)
  end

  context "when state is :change_in_progress" do
    let(:state) { :change_in_progress }

    it "renders the in-progress spinner message" do
      render_component(component)
      expect(page).to have_text("Project identifiers are currently being converted to semantic format.")
    end

    it "does not render the success banner" do
      render_component(component)
      expect(page).to have_no_text("Successfully updated work package identifier format.")
    end

    it "renders the radio buttons as disabled" do
      render_component(component)
      expect(page).to have_field("Instance-wide numerical sequence (default)", disabled: true)
      expect(page).to have_field("Project-based semantic identifiers", disabled: true)
    end

    it "does not render the save or autofix buttons" do
      render_component(component)
      expect(page).to have_no_button("Save")
      expect(page).to have_no_link("Autofix and save")
    end

    it "does not call PreviewQuery" do
      render_component(component)
      expect(ProjectIdentifiers::IdentifierAutofix::PreviewQuery).not_to have_received(:new)
    end
  end

  context "when state is :completed" do
    let(:state) { :completed }

    it "renders the success banner" do
      render_component(component)
      expect(page).to have_text("Successfully updated work package identifier format.")
    end

    it "does not render the in-progress spinner message" do
      render_component(component)
      expect(page).to have_no_text("Project identifiers are currently being converted to semantic format.")
    end

    it "renders the radio buttons as enabled" do
      render_component(component)
      expect(page).to have_field("Instance-wide numerical sequence (default)", disabled: false)
      expect(page).to have_field("Project-based semantic identifiers", disabled: false)
    end

    it "does not call PreviewQuery" do
      render_component(component)
      expect(ProjectIdentifiers::IdentifierAutofix::PreviewQuery).not_to have_received(:new)
    end

    context "with semantic setting", with_settings: { work_packages_identifier: "semantic" } do
      it "shows semantic as selected" do
        render_component(component)
        expect(page).to have_field("Project-based semantic identifiers", checked: true)
        expect(page).to have_field("Instance-wide numerical sequence (default)", checked: false)
      end
    end

    context "with classic setting", with_settings: { work_packages_identifier: "classic" } do
      it "shows classic as selected" do
        render_component(component)
        expect(page).to have_field("Instance-wide numerical sequence (default)", checked: true)
        expect(page).to have_field("Project-based semantic identifiers", checked: false)
      end
    end
  end

  context "when state is :edit" do
    let(:state) { :edit }

    it "calls PreviewQuery" do
      render_component(component)
      expect(ProjectIdentifiers::IdentifierAutofix::PreviewQuery).to have_received(:new).once
    end

    it "renders the save button (hidden until a change is made)" do
      render_component(component)
      expect(page).to have_button("Save", visible: :all)
    end

    it "does not render in-progress or success content" do
      render_component(component)
      expect(page).to have_no_text("Project identifiers are currently being converted to semantic format.")
      expect(page).to have_no_text("Successfully updated work package identifier format.")
    end

    context "with problematic projects and semantic setting",
            with_settings: { work_packages_identifier: "semantic" } do
      let(:project) { instance_double(Project, name: "Bad Project", id: 1, to_param: "bad-proj") }
      let(:problematic_result) do
        ProjectIdentifiers::IdentifierAutofix::PreviewQuery::Result.new(
          projects_data: [
            { project:, current_identifier: "bad-proj", suggested_identifier: "BP", error_reason: :special_characters }
          ],
          total_count: 1
        )
      end

      before do
        stub = instance_double(ProjectIdentifiers::IdentifierAutofix::PreviewQuery, call: problematic_result)
        allow(ProjectIdentifiers::IdentifierAutofix::PreviewQuery).to receive(:new).and_return(stub)
      end

      it "hides the plain save button" do
        render_component(component)
        expect(page).to have_no_button("Save")
      end

      it "renders the autofix button" do
        render_component(component)
        expect(page).to have_link("Autofix and save")
      end
    end
  end

  context "when an unknown state is given" do
    it "raises ArgumentError" do
      expect { described_class.new(state: :bogus) }.to raise_error(ArgumentError, /Unknown state/)
    end
  end
end
