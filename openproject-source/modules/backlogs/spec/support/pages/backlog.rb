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

require "support/pages/page"

module Pages
  class Backlog < Page
    attr_reader :project

    def initialize(project)
      super()
      @project = project
    end

    def alter_attributes_in_details_view(story, **attributes)
      within_details_view(story) do |details_view|
        attributes.each do |key, value|
          details_view
            .edit_field(key.to_s.camelize(:lower))
            .update(value)

          details_view.expect_and_dismiss_toaster message: "Successful update."
        end
      end
    end

    def edit_story_in_details_view(story, **attributes)
      click_in_story_menu(story, "Open details view")

      alter_attributes_in_details_view(story, **attributes)
    end

    def click_in_sprint_menu(sprint, item_name)
      within_sprint_menu(sprint) do |menu|
        menu.find(:menuitem, text: item_name).click
      end
    end

    def click_in_story_menu(story, item_name)
      within_story_menu(story) do |menu|
        menu.find(:menuitem, text: item_name).click
      end
    end

    def drag_in_sprint(moved, target, before: true)
      moved_element = find(story_selector(moved))
      target_element = find(story_selector(target))

      drag_n_drop_element from: moved_element, to: target_element, offset_x: 0, offset_y: before ? -5 : +10
    end

    def sprint_names_in_order
      page.find_all("#sprint_backlogs_container > section .CollapsibleHeader-title").map(&:text)
    end

    def expect_work_packages_in_sprint_in_order(sprint,
                                                work_packages: [])
      within_sprint(sprint) do
        expect_work_packages_in_order work_packages:
      end
    end

    def expect_work_packages_in_inbox_in_order(work_packages: [])
      within_inbox do
        expect_work_packages_in_order work_packages:
      end
    end

    def expect_work_packages_in_order(work_packages: [])
      raise ArgumentError, "work_packages should not be empty" if work_packages.empty?

      selectors = work_packages.map { |wp| work_package_selector(wp) }
      expect(page)
        .to have_css(selectors.join(" + "))
      wait_for_network_idle
    end

    def sprint_items_in_visual_order(sprint, *work_packages)
      tops = within_sprint(sprint) do
        work_packages.index_with do |wp|
          page.evaluate_script(
            "document.querySelector('#{work_package_selector(wp)}').getBoundingClientRect().top"
          )
        end
      end

      work_packages.sort_by { |wp| tops.fetch(wp) }
    end

    def drag_work_package(moved, before: nil, into: nil)
      raise ArgumentError, "You must specify either before or into" unless before.present? ^ into.present?

      moved_element = find(draggable_work_package_selector(moved))
      target_element = if before
                         find(work_package_selector(before))
                       else
                         find(sprint_selector(into))
                       end

      wait_for_turbo_stream do
        moved_element.native.drag_to(target_element.native, delay: 0.1)
      end
    rescue Capybara::Cuprite::ObsoleteNode
      retry
    end

    def expect_work_package_not_draggable(work_package)
      expect(page)
        .to have_no_css(draggable_work_package_selector(work_package))
    end

    def expect_inbox_blankslate
      within_inbox do
        expect(page).to have_css("h4", text: "Backlog inbox is empty")
      end
    end

    def expect_no_inbox_blankslate
      within_inbox do
        expect(page).to have_no_css("h4", text: "Backlog inbox is empty")
      end
    end

    def expect_backlog_blankslate
      within_sprint_backlogs do
        expect(page).to have_css("h4", text: "No sprints present yet")
      end
    end

    def expect_backlog_blankslate_description(text)
      within_sprint_backlogs do
        expect(page).to have_text(text)
      end
    end

    def expect_no_backlog_blankslate
      within_sprint_backlogs do
        expect(page).to have_no_css("h4", text: "No sprints present yet")
      end
    end

    def expect_backlog_settings_link
      within_sprint_backlogs do
        expect(page).to have_link(
          "project settings",
          href: project_settings_backlog_sharing_path(project)
        )
      end
    end

    def expect_no_backlog_settings_link
      within_sprint_backlogs do
        expect(page).to have_no_link(
          "project settings",
          href: project_settings_backlog_sharing_path(project)
        )
      end
    end

    def expect_new_sprint_button
      within_sprint_backlogs do
        expect(page).to have_css(
          test_selector("op-sprints--new-sprint-button"),
          text: Sprint.human_model_name
        )
      end
    end

    def expect_no_new_sprint_button
      within_sprint_backlogs do
        expect(page).to have_no_css(
          test_selector("op-sprints--new-sprint-button"),
          text: Sprint.human_model_name
        )
      end
    end

    def expect_inbox_item(work_package)
      within_inbox do
        expect(page).to have_css(work_package_selector(work_package))
      end
    end

    def expect_no_inbox_item(work_package)
      within_inbox do
        expect(page).to have_no_css(work_package_selector(work_package))
      end
    end

    def expect_inbox_show_more
      within_inbox do
        expect(page).to have_css("#inbox_project_#{project.id}_show_more")
      end
    end

    def expect_no_inbox_show_more
      wait_for_network_idle
      within_inbox do
        expect(page).to have_no_css("#inbox_project_#{project.id}_show_more")
      end
    end

    def click_inbox_show_more
      within_inbox do
        find("#inbox_project_#{project.id}_show_more").click
      end
      wait_for_network_idle
    end

    def open_sprint_story_details(story)
      within(work_package_selector(story)) do
        button = find(:button, accessible_name: "Work package actions")
        open_controlled_menu(button).find(:menuitem, text: I18n.t(:"js.button_open_details")).click
      end
      expect_details_view(story)
    end

    def expect_inbox_items_in_order(*work_packages)
      within_inbox do
        selectors = work_packages.map { |wp| work_package_selector(wp) }
        expect(page).to have_css(selectors.join(" + "))
      end

      wait_for_network_idle
    end

    def within_inbox_menu(work_package, &)
      within(work_package_selector(work_package)) do
        button = find(:button, accessible_name: "Work package actions")
        within(open_controlled_menu(button), &)
      end

      dismiss_menu(work_package)
    end

    def click_in_inbox_menu(work_package, item_name)
      within_inbox_menu(work_package) do |menu|
        menu.find(:menuitem, text: item_name).click
      end
    end

    def click_in_inbox_move_menu(work_package, item_name)
      button = within(work_package_selector(work_package)) do
        find(:button, accessible_name: "Work package actions")
      end
      menu = open_controlled_menu(button)
      submenu = open_move_submenu(menu)
      submenu.find(:menuitem, text: item_name).click
    end

    def within_sprint_story_menu(story, &)
      within(work_package_selector(story)) do
        button = find(:button, accessible_name: "Work package actions")
        within(open_controlled_menu(button), &)
      end

      dismiss_menu(story)
    end

    def click_in_sprint_story_menu(story, item_name)
      within_sprint_story_menu(story) do |menu|
        menu.find(:menuitem, text: item_name).click
      end
    end

    def click_in_sprint_story_move_menu(story, item_name)
      button = within(work_package_selector(story)) do
        find(:button, accessible_name: "Work package actions")
      end
      menu = open_controlled_menu(button)
      submenu = open_move_submenu(menu)
      submenu.find(:menuitem, text: item_name).click
    end

    def drag_inbox_item_to_sprint(work_package, sprint)
      moved_element = find(draggable_work_package_selector(work_package))
      target_element = find(sprint_selector(sprint))
      wait_for_turbo_stream do
        moved_element.native.drag_to(target_element.native, delay: 0.1)
      end
    rescue Capybara::Cuprite::ObsoleteNode
      retry
    end

    def drag_sprint_item_to_inbox(work_package)
      moved_element = find(draggable_work_package_selector(work_package))
      target_element = find("#inbox_project_#{project.id}")
      moved_element.native.drag_to(target_element.native, delay: 0.1)
    rescue Capybara::Cuprite::ObsoleteNode
      retry
    end

    def expect_no_sprint_menu(sprint)
      within_sprint(sprint) do
        expect(page).to have_no_button(accessible_name: "Sprint actions")
      end
    end

    def expect_no_sprint_menu_item(sprint, item_name)
      within_sprint_menu(sprint) do |_menu|
        expect(page)
          .to have_no_selector(:menuitem, text: item_name)
      end
    end

    def expect_sprint_names_in_order(*sprint_names)
      expect(sprint_names_in_order).to eq(sprint_names)
    end

    def bucket_names_in_order
      page.find_all("#owner_backlogs_container section .CollapsibleHeader-title").map(&:text)
    end

    def expect_bucket_names_in_order(*bucket_names)
      expect(bucket_names_in_order).to eq(bucket_names)
    end

    def expect_no_backlog_bucket(bucket)
      expect(page).to have_no_css(bucket_selector(bucket))
    end

    def expect_backlog_bucket_work_package_count(bucket, count)
      within_backlog_bucket(bucket) do
        expect(page).to have_css(
          ".Counter",
          accessible_name: I18n.t(
            "open_project.common.work_package_card_list_component.header.label_work_package_count",
            count:
          )
        )
      end
    end

    def expect_work_packages_in_backlog_bucket_in_order(bucket, work_packages: [])
      within_backlog_bucket(bucket) do
        expect_work_packages_in_order(work_packages:)
      end
    end

    def expect_work_packages_in_backlog_inbox_in_order(work_packages: [])
      within_backlog_inbox do
        expect_work_packages_in_order(work_packages:)
      end
    end

    def open_create_backlog_bucket_dialog
      within_owner_backlogs do
        click_on accessible_name: BacklogBucket.human_model_name
      end
    end

    def expect_new_backlog_bucket_button
      within_owner_backlogs do
        expect(page).to have_link(BacklogBucket.human_model_name, exact: true)
      end
    end

    def expect_no_new_backlog_bucket_button
      within_owner_backlogs do
        expect(page).to have_no_link(BacklogBucket.human_model_name, exact: true)
      end
    end

    def expect_backlog_bucket_dialog
      expect(page).to have_dialog(I18n.t(:label_backlog_bucket_new))
    end

    def within_backlog_bucket_menu(bucket, &)
      within_backlog_bucket(bucket) do
        button = find(:button, accessible_name: "Backlog bucket actions")
        within(open_controlled_menu(button), &)
      end
      dismiss_menu(bucket)
    end

    def click_in_backlog_bucket_menu(bucket, item_name)
      within_backlog_bucket_menu(bucket) do |menu|
        menu.find(:menuitem, text: item_name).click
      end
    end

    def expect_no_backlog_bucket_menu(bucket)
      within_backlog_bucket(bucket) do
        expect(page).to have_no_button(accessible_name: "Backlog bucket actions")
      end
    end

    def expect_backlog_bucket_blankslate(bucket)
      within_backlog_bucket(bucket) do
        expect(page).to have_selector(:heading, level: 4, text: "Backlog bucket is empty")
      end
    end

    def expect_no_backlog_bucket_blankslate(bucket)
      within_backlog_bucket(bucket) do
        expect(page).to have_no_selector(:heading, level: 4, text: "Backlog bucket is empty")
      end
    end

    def drag_work_package_to_backlog_bucket(work_package, bucket)
      moved_element = find(draggable_work_package_selector(work_package))
      target_element = find(bucket_selector(bucket))

      wait_for_turbo_stream do
        moved_element.native.drag_to(target_element.native, delay: 0.1)
      end
    rescue Capybara::Cuprite::ObsoleteNode
      retry
    end

    def drag_work_package_to_backlog_inbox(work_package)
      moved_element = find(draggable_work_package_selector(work_package))
      target_element = find(backlog_inbox_selector)

      wait_for_turbo_stream do
        moved_element.native.drag_to(target_element.native, delay: 0.1)
      end
    rescue Capybara::Cuprite::ObsoleteNode
      retry
    end

    def expect_story_in_sprint(story, sprint)
      within_sprint(sprint) do
        expect(page)
          .to have_selector(work_package_selector(story).to_s)
      end
    end

    def expect_story_not_in_sprint(story, sprint)
      within_sprint(sprint) do
        expect(page)
          .to have_no_selector(work_package_selector(story).to_s)
      end
    end

    def expect_sprint_story_points(sprint, points)
      within(sprint_selector(sprint)) do
        expect(page).to have_css(".velocity", text: points.to_s)
      end
    end

    def expect_sprint_story_count(sprint, count)
      within(sprint_selector(sprint)) do
        expect(page).to have_css(
          ".Counter",
          accessible_name: I18n.t(
            "open_project.common.work_package_card_list_component.header.label_work_package_count",
            count:
          )
        )
      end
    end

    def expect_and_dismiss_error(message)
      expect(page).to have_content message

      click_on "Cancel"
    end

    def visit!
      super

      expect(page).to have_css("turbo-frame#backlogs_container", wait: 10)
      expect(page).to have_css("#owner_backlogs_container", wait: 10)
      expect(page).to have_css("#sprint_backlogs_container", wait: 10)
      wait_for_network_idle
    end

    def path
      project_backlogs_backlog_path(project)
    end

    def within_story_menu(story, &)
      within_story(story) do
        button = find(:button, accessible_name: "Work package actions")
        within(open_controlled_menu(button), &)
      end
    end

    def within_details_view(story, &)
      details_view = expect_details_view(story)

      yield details_view
    end

    def expect_details_view(story)
      details_view = Pages::PrimerizedSplitWorkPackage.new(story)
      details_view.expect_tab :overview
      details_view.expect_subject

      expect(page).to have_current_path project_backlogs_backlog_details_path(story.project, story),
                                        ignore_query: true
      wait_for_network_idle

      details_view
    end

    def open_create_sprint_dialog
      find_test_selector("op-sprints--new-sprint-button", text: "Sprint").click
    end

    def expect_sprint_dialog
      expect(page).to have_css("#sprint-dialog")
    end

    def expect_create_work_package_dialog
      expect(page).to have_css("#create-work-package-dialog")
    end

    def expect_sprint_completing_modal
      expect(page).to have_css sprint_complete_modal_selector
    end

    def expect_sprints_to_choose_for_moving_unfinished_work_packages_to(*sprints)
      within sprint_complete_modal_selector do
        expect(page).to have_select("Select sprint", options: sprints.map(&:name))
      end
    end

    def expect_and_confirm_backlog_bucket_delete_modal
      expect(page).to have_selector backlog_bucket_destroy_modal_selector

      within backlog_bucket_destroy_modal_selector do
        click_button "Delete"
      end
    end

    def within_sprint_menu(sprint, &)
      within_sprint(sprint) do
        button = find(:button, accessible_name: "Sprint actions")
        within(open_controlled_menu(button), &)
      end

      dismiss_menu(sprint)
    end

    def within_work_package_row(work_package, &)
      within(work_package_selector(work_package), &)
    end

    def click_start_sprint_button(sprint)
      within_sprint(sprint) do
        click_on("Start")
      end
    end

    def click_complete_sprint_button(sprint)
      within_sprint(sprint) do
        click_on("Complete")
      end
    end

    def click_to_complete_sprint(sprint)
      click_complete_sprint_button(sprint)
    end

    def choose_to_move_unfinished_work_packages_to_sprint(sprint_name)
      within sprint_complete_modal_selector do
        choose I18n.t("backlogs.finish_sprint_dialog_component.actions.move_to_sprint")
        select sprint_name, from: "Select sprint"

        click_button "Complete sprint"
      end
    end

    def choose_to_move_unfinished_work_packages_to_top_of_backlog
      within sprint_complete_modal_selector do
        choose I18n.t("backlogs.finish_sprint_dialog_component.actions.move_to_top_of_backlog")

        click_button "Complete sprint"
      end
    end

    def choose_to_move_unfinished_work_packages_to_bottom_of_backlog
      within sprint_complete_modal_selector do
        choose I18n.t("backlogs.finish_sprint_dialog_component.actions.move_to_bottom_of_backlog")

        click_button "Complete sprint"
      end
    end

    def within_move_submenu(menu, &)
      within(open_move_submenu(menu), &)
    end

    private

    def within_story(story, &)
      within(story_selector(story), &)
    end

    def within_sprint(sprint, &)
      within(sprint_selector(sprint), &)
    end

    def within_inbox(&)
      within("#inbox_project_#{project.id}", &)
    end

    def within_backlog_bucket(bucket, &)
      within(bucket_selector(bucket), &)
    end

    def within_backlog_inbox(&)
      within(backlog_inbox_selector, &)
    end

    def within_owner_backlogs(&)
      within("#owner_backlogs_container", &)
    end

    def within_sprint_backlogs(&)
      within("#sprint_backlogs_container", &)
    end

    def sprint_selector(sprint)
      test_selector("sprint-#{sprint.id}")
    end

    def bucket_selector(bucket)
      raise ArgumentError, "bucket must be persisted" unless bucket.persisted?

      test_selector("backlog-bucket-#{bucket.id}")
    end

    def backlog_inbox_selector
      test_selector("backlog-inbox")
    end

    def story_selector(story)
      "#story_#{story.id}"
    end

    def work_package_selector(work_package)
      test_selector("work-package-#{work_package.id}")
    end

    def draggable_work_package_selector(work_package)
      "#{work_package_selector(work_package)}[data-draggable-id]"
    end

    def sprint_complete_modal_selector
      "##{::Backlogs::FinishSprintDialogComponent::DIALOG_ID}"
    end

    def backlog_bucket_destroy_modal_selector
      test_selector(Backlogs::BacklogBucketDestroyModalComponent::TEST_SELECTOR)
    end

    def open_controlled_menu(button)
      button.click
      page.find(:menu, id: button[:controls] || button["aria-controls"])
    end

    def open_move_submenu(menu)
      move_item = menu.find(:menuitem, text: "Move")
      move_item.click
      page.find(:menu, id: move_item["aria-controls"])
    end

    def dismiss_menu(menu_owner)
      overlay_id = "#{ActionView::RecordIdentifier.dom_target(menu_owner, :menu)}-overlay"
      selector = "##{overlay_id}"

      return unless page.has_css?(selector, visible: true, wait: 0)

      find(selector).click
    end
  end
end
