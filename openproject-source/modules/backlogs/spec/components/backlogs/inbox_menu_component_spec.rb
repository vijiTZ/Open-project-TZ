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

RSpec.describe Backlogs::InboxMenuComponent, type: :component do
  shared_let(:default_status) { create(:default_status) }
  shared_let(:default_priority) { create(:default_priority) }
  shared_let(:user) { create(:user) }
  current_user { user }

  let(:permissions) { [] }
  let(:project) { create(:project) }
  let(:position) { 2 }
  let(:max_position) { 3 }
  let(:work_package) do
    create(:work_package,
           subject: "Inbox Work Package",
           project:,
           status: default_status,
           priority: default_priority,
           position:)
  end

  before do
    create(:member,
           project:,
           principal: user,
           roles: [create(:project_role, permissions:)])
  end

  def render_component(position: 2, max_position: 3, open_sprints_exist: true, show_all_backlog: false)
    work_package.update!(position:)
    vc_test_controller.params[:all] = "1" if show_all_backlog
    render_inline described_class.new(
      work_package:,
      project:,
      max_position:,
      open_sprints_exist:,
      current_user: user
    )
  end

  describe "standard items" do
    it "renders stable ids for the list and primary actions" do
      render_component

      expect(page).to have_element(:ul, id: /\Awork_package_#{work_package.id}_menu-list\z/)
      expect(page).to have_element(:a, id: /\Awork_package_#{work_package.id}_menu_open_details\z/)
      expect(page).to have_element(:a, id: /\Awork_package_#{work_package.id}_menu_open_fullscreen\z/)
      expect(page).to have_element(:"clipboard-copy", id: /\Awork_package_#{work_package.id}_menu_copy_url_to_clipboard\z/)
      expect(page).to have_element(:"clipboard-copy", id: /\Awork_package_#{work_package.id}_menu_copy_work_package_id\z/)
    end

    it "shows Open details link (split view)" do
      render_component

      expect(page).to have_text(I18n.t(:"js.button_open_details"))
      expect(page).to have_octicon(:"op-view-split")
      expect(page).to have_css(
        "a[data-turbo-frame='content-bodyRight'][data-turbo-action='advance']",
        text: I18n.t(:"js.button_open_details")
      )
    end

    context "when the show_all_backlog is true" do
      it "adds the all param to the open details link" do
        render_component(show_all_backlog: true)

        expect(page).to have_css(%(#work_package_#{work_package.id}_menu_open_details[href*="all=1"]))
      end
    end

    it "shows Open fullscreen link (full page)" do
      render_component

      expect(page).to have_text(I18n.t(:"js.button_open_fullscreen"))
      expect(page).to have_octicon(:"screen-full")
      expect(page).to have_css(
        "a[data-turbo-frame='_top']",
        text: I18n.t(:"js.button_open_fullscreen")
      )
    end

    it "shows Copy URL to clipboard action" do
      render_component

      expect(page).to have_octicon(:copy)
      expect(page).to have_element(
        :"clipboard-copy",
        id: "work_package_#{work_package.id}_menu_copy_url_to_clipboard",
        value: /\/work_packages\/#{work_package.id}\z/,
        text: I18n.t("backlogs.inbox_menu_component.action_menu.copy_url_to_clipboard")
      )
    end

    it "shows Copy work package ID action" do
      render_component

      expect(page).to have_octicon(:hash)
      expect(page).to have_element(
        :"clipboard-copy",
        id: "work_package_#{work_package.id}_menu_copy_work_package_id",
        value: work_package.id.to_s,
        text: I18n.t("backlogs.inbox_menu_component.action_menu.copy_work_package_id")
      )
    end

    context "in semantic mode",
            with_flag: { semantic_work_package_ids: true },
            with_settings: { work_packages_identifier: "semantic" } do
      let(:project) { create(:project, identifier: "INBOX") }

      it "uses the semantic displayId in the open details, fullscreen, and clipboard URLs" do
        render_component

        semantic_id = work_package.reload.identifier
        expect(semantic_id).to start_with("INBOX-")

        details = page.find_by_id("work_package_#{work_package.id}_menu_open_details")
        expect(details[:href]).to include("/details/#{semantic_id}")
        expect(details[:href]).not_to include("/details/#{work_package.id}")

        fullscreen = page.find_by_id("work_package_#{work_package.id}_menu_open_fullscreen")
        expect(fullscreen[:href]).to end_with("/work_packages/#{semantic_id}")
        expect(fullscreen[:href]).not_to include("/work_packages/#{work_package.id}")

        clipboard = page.find("clipboard-copy##{"work_package_#{work_package.id}_menu_copy_url_to_clipboard"}")
        expect(clipboard[:value]).to end_with("/work_packages/#{semantic_id}")
        expect(clipboard[:value]).not_to include("/work_packages/#{work_package.id}")
      end

      it "still copies the numeric primary key for the 'Copy work package ID' action" do
        render_component

        clipboard_id = page.find("clipboard-copy##{"work_package_#{work_package.id}_menu_copy_work_package_id"}")
        expect(clipboard_id[:value]).to eq(work_package.id.to_s)
      end
    end
  end

  describe "move menu" do
    context "with :manage_sprint_items permission" do
      let(:permissions) { [:manage_sprint_items] }

      it "shows a divider before the Move submenu" do
        render_component

        expect(page).to have_css(".ActionList-sectionDivider")
      end

      it "shows the Move submenu with incoming-arrow icon" do
        render_component

        expect(page).to have_selector(:menuitem, text: I18n.t("backlogs.inbox_menu_component.action_menu.move_menu"))
        expect(page).to have_octicon(:"op-arrow-in")
      end

      it "shows all move options when item is in the middle" do
        render_component(position: 2, max_position: 3)

        expect(page).to have_text(I18n.t(:label_sort_highest))
        expect(page).to have_text(I18n.t(:label_sort_higher))
        expect(page).to have_text(I18n.t(:label_sort_lower))
        expect(page).to have_text(I18n.t(:label_sort_lowest))
      end

      it "shows only downward move options when item is first" do
        render_component(position: 1, max_position: 3)

        expect(page).to have_no_text(I18n.t(:label_sort_highest))
        expect(page).to have_no_text(I18n.t(:label_sort_higher))
        expect(page).to have_text(I18n.t(:label_sort_lower))
        expect(page).to have_text(I18n.t(:label_sort_lowest))
      end

      it "shows only upward move options when item is last" do
        render_component(position: 3, max_position: 3)

        expect(page).to have_text(I18n.t(:label_sort_highest))
        expect(page).to have_text(I18n.t(:label_sort_higher))
        expect(page).to have_no_text(I18n.t(:label_sort_lower))
        expect(page).to have_no_text(I18n.t(:label_sort_lowest))
      end

      it "hides the Move submenu when there is only one item and no open sprints" do
        render_component(position: 1, max_position: 1, open_sprints_exist: false)

        expect(page).to have_no_selector(
          :menuitem,
          text: I18n.t("backlogs.inbox_menu_component.action_menu.move_menu")
        )
      end

      context "when open_sprints_exist is true" do
        it "shows Move to sprint in the Move submenu" do
          render_component(open_sprints_exist: true)

          expect(page).to have_link(I18n.t("backlogs.inbox_menu_component.label_move_to_sprint"))
        end
      end

      context "when open_sprints_exist is false" do
        it "hides Move to sprint but keeps reorder actions in the Move submenu" do
          render_component(open_sprints_exist: false)

          expect(page).to have_no_link(I18n.t("backlogs.inbox_menu_component.label_move_to_sprint"))
          expect(page).to have_text(I18n.t(:label_sort_higher))
          expect(page).to have_text(I18n.t(:label_sort_lower))
        end
      end
    end

    context "without :manage_sprint_items permission" do
      it "hides the Move submenu" do
        render_component

        expect(page).to have_no_selector(
          :menuitem,
          text: I18n.t("backlogs.inbox_menu_component.action_menu.move_menu")
        )
      end
    end
  end
end
