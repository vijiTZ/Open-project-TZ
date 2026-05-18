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

RSpec.describe OpenProject::Common::WorkPackageCardListComponent::Header, type: :component do
  shared_let(:user) { create(:admin) }
  current_user { user }

  shared_let(:project) { create(:project) }
  shared_let(:sprint) do
    create(:sprint, project:, name: "Sprint 1",
                    start_date: Date.yesterday, finish_date: Date.tomorrow)
  end

  let(:title) { "Sprint 1" }
  let(:container) { sprint }
  let(:list_id) { "sprint_1_list" }
  let(:count) { 4 }
  let(:menu_button_id) { "sprint_#{sprint.id}_menu-button" }

  subject(:rendered_component) do
    render_component
  end

  def render_component(&)
    render_inline(described_class.new(title:, container:, list_id:, count:), &)
  end

  describe "kwargs-only render" do
    it "renders the title in the collapsible header" do
      expect(rendered_component).to have_heading "Sprint 1", level: 4
    end

    it "renders the count badge" do
      expect(rendered_component).to have_css ".Counter", text: "4"
    end

    it "passes the provided list id to the collapsible trigger" do
      expect(rendered_component).to have_css ".CollapsibleHeader-triggerArea", aria: { controls: "sprint_1_list" }
    end

    it "uses the work-package-count aria label on the count badge" do
      expect(rendered_component).to have_css ".Counter", text: "4", aria: { label: "4 work packages" }
    end
  end

  describe ":description slot" do
    subject(:rendered_component) do
      render_component do |header|
        header.with_description { "extra-bit" }
      end
    end

    it "renders inside the description region" do
      expect(rendered_component).to have_text("extra-bit")
    end
  end

  describe ":actions slots" do
    subject(:rendered_component) do
      render_component do |header|
        header.with_action_button(id: "start-btn", scheme: :primary) { "Start" }
        header.with_action_button(id: "finish-btn", scheme: :invisible) { "Finish" }
      end
    end

    it "renders buttons into the actions grid area" do
      expect(rendered_component).to have_button "Start"
      expect(rendered_component).to have_button "Finish"
    end
  end

  describe ":menu slot" do
    subject(:rendered_component) do
      render_component do |header|
        header.with_menu(**menu_arguments) { |menu| menu.with_item(label: "Edit", href: "/x") }
      end
    end

    let(:count) { 1 }
    let(:menu_arguments) { {} }

    it "renders an action-menu" do
      expect(rendered_component).to have_element :"action-menu"
    end

    it "uses the standard kebab accessible label" do
      expect(rendered_component).to have_button menu_button_id, accessible_name: "Open menu"
    end

    it "defaults menu_id to dom_target(container, :menu)" do
      expect(rendered_component).to have_button menu_button_id
    end

    it "applies the hide-when-print class" do
      expect(rendered_component).to have_element :"action-menu", class: "hide-when-print"
    end

    context "when a custom aria label is provided" do
      let(:menu_arguments) { { button_aria_label: "Sprint actions" } }

      it "uses the custom label" do
        expect(rendered_component).to have_button menu_button_id, accessible_name: "Sprint actions"
      end
    end
  end
end
