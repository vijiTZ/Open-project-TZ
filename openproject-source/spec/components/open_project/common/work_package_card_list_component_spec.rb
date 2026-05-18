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

RSpec.describe OpenProject::Common::WorkPackageCardListComponent, type: :component do
  shared_let(:type_feature) { create(:type_feature) }
  shared_let(:default_status) { create(:default_status) }
  shared_let(:default_priority) { create(:default_priority) }
  shared_let(:user) { create(:admin) }
  current_user { user }

  shared_let(:project) { create(:project, types: [type_feature]) }
  shared_let(:sprint) do
    create(:sprint, project:, name: "Sprint 1",
                    start_date: Date.yesterday, finish_date: Date.tomorrow)
  end
  shared_let(:backlog_bucket) { create(:backlog_bucket, project:, name: "Bucket A") }

  let(:container) { sprint }
  let(:drag_and_drop) { nil }
  let(:item_component_klass) { described_class::Item }
  let(:params) { {} }
  let(:work_packages) { [] }
  let(:system_arguments) { {} }
  let(:header_arguments) { nil }
  let(:footer_content) { nil }

  let(:custom_item_component_class) do
    stub_const(
      "CustomWorkPackageCardListItem",
      Class.new(ApplicationComponent) do
        def initialize(
          work_package:,
          project:,
          container:,
          params:,
          current_user: User.current,
          **system_arguments
        )
          super()

          @work_package = work_package
          @params = params
          @context = [project, container, current_user]
          @system_arguments = system_arguments
        end

        def row_args
          data = @system_arguments.fetch(:data, {}).merge(
            params: @params.to_query,
            context_size: @context.size
          )

          @system_arguments.merge(
            id: "custom_work_package_#{@work_package.id}",
            data:
          )
        end

        def card
          CustomWorkPackageCardListItemCard.new(subject: @work_package.subject)
        end

        def render? = false
      end
    )
  end

  subject(:rendered_component) do
    render_component(work_packages:, container:, drag_and_drop:, system_arguments:)
  end

  def render_component(work_packages:, container:, drag_and_drop:, system_arguments:)
    component_arguments = {
      work_packages:,
      project:,
      container:,
      drag_and_drop:,
      item_component_klass:,
      params:,
      current_user: user,
      **system_arguments
    }
    render_inline(
      described_class.new(**component_arguments)
    ) do |box|
      box.with_header(**header_arguments) if header_arguments
      box.with_empty_state(title: "Sprint 1 is empty", description: "Drag work packages here")
      box.with_footer { footer_content } if footer_content
    end
  end

  before do
    stub_const(
      "CustomWorkPackageCardListItemCard",
      Class.new(ApplicationComponent) do
        def initialize(subject:)
          super()

          @subject = subject
        end

        def call
          tag.span("custom #{@subject}")
        end
      end
    )
  end

  describe "Box shell" do
    it_behaves_like "rendering Box", row_count: 1, header: false, footer: false
    it_behaves_like "rendering Blank Slate", heading: "Sprint 1 is empty"
  end

  describe "container-derived attributes" do
    context "when container is a Sprint" do
      let(:container) { sprint }

      it "uses dom_target(sprint) as the box id" do
        expect(rendered_component).to have_css(".Box#sprint_#{sprint.id}")
      end

      it "uses dom_target(sprint, :list) for the collapsible BorderBox body" do
        expect(rendered_component).to have_css("ul#sprint_#{sprint.id}_list")
      end

      it "does not emit drag-and-drop data by default" do
        expect(rendered_component).to have_no_css(".Box[data-generic-drag-and-drop-target]")
        expect(rendered_component).to have_no_css(".Box[data-target-id]")
        expect(rendered_component).to have_no_css(".Box[data-target-allowed-drag-type]")
      end

      context "with drag_and_drop configured" do
        let(:drag_and_drop) do
          { target_id: "sprint:#{sprint.id}", allowed_drag_type: "story" }
        end

        it "uses the configured drag-and-drop data" do
          expect(rendered_component).to have_css(".Box") do |box|
            expect(box["data-generic-drag-and-drop-target"]).to eq("container")
            expect(box["data-target-container-accessor"]).to eq(":scope > ul")
            expect(box["data-target-id"]).to eq("sprint:#{sprint.id}")
            expect(box["data-target-allowed-drag-type"]).to eq("story")
          end
        end
      end

      it "does not emit a default test selector" do
        expect(rendered_component).to have_no_css(".Box[data-test-selector]")
      end
    end

    context "when container is a BacklogBucket" do
      let(:container) { backlog_bucket }

      it "uses dom_target(backlog_bucket) as the box id" do
        expect(rendered_component).to have_css(".Box#backlog_bucket_#{backlog_bucket.id}")
      end

      it "uses dom_target(backlog_bucket, :list) for the collapsible BorderBox body" do
        expect(rendered_component).to have_css("ul#backlog_bucket_#{backlog_bucket.id}_list")
      end

      it "does not emit a default test selector" do
        expect(rendered_component).to have_no_css(".Box[data-test-selector]")
      end
    end

    context "when container is a Symbol" do
      let(:container) { :inbox }

      it "uses dom_target(container) as the box id" do
        expect(rendered_component).to have_css(".Box#inbox")
      end

      it "uses dom_target(container, :list) for the list id" do
        expect(rendered_component).to have_css("ul#inbox_list")
      end
    end

    context "when container is a String" do
      let(:container) { "custom_box" }

      it "uses dom_target(container) as the box id" do
        expect(rendered_component).to have_css(".Box#custom_box")
      end

      it "uses dom_target(container, :list) for the list id" do
        expect(rendered_component).to have_css("ul#custom_box_list")
      end
    end

    context "when container is a model class" do
      let(:container) { Project }

      it "uses dom_target(container) as the box id" do
        expect(rendered_component).to have_css(".Box#project")
      end

      it "uses dom_target(container, :list) for the list id" do
        expect(rendered_component).to have_css("ul#project_list")
      end
    end

    context "when data[:test_selector] is provided by the caller" do
      let(:system_arguments) { { data: { test_selector: "custom-sprint-box" } } }

      it "passes the custom test selector through" do
        expect(rendered_component).to have_css(".Box[data-test-selector='custom-sprint-box']")
      end
    end
  end

  describe ":header slot" do
    context "when no header is supplied" do
      it "renders no Box-header" do
        expect(rendered_component).to have_no_css(".Box-header")
      end
    end

    context "when a header is supplied" do
      let(:header_arguments) { { title: "Sprint 1", count: 0 } }

      it_behaves_like "rendering Box", row_count: 1, header: true, footer: false

      it "renders the provided title" do
        expect(rendered_component).to have_heading "Sprint 1", level: 4
      end

      it "uses dom_target(container, :header) as the header row id" do
        expect(rendered_component).to have_css(".Box-header#sprint_#{sprint.id}_header")
      end
    end
  end

  describe "fold state in the rendered header" do
    let(:header_arguments) { { title: "Sprint 1", count: 0 } }

    context "when the user prefers closed folds" do
      before do
        user.pref[:backlogs_versions_default_fold_state] = "closed"
      end

      it "renders the header as collapsed" do
        expect(rendered_component).to have_css ".CollapsibleHeader-triggerArea", aria: { expanded: "false" }
      end
    end

    context "when the user prefers open folds" do
      before do
        user.pref[:backlogs_versions_default_fold_state] = "open"
      end

      it "renders the header as expanded" do
        expect(rendered_component).to have_css ".CollapsibleHeader-triggerArea", aria: { expanded: "true" }
      end
    end
  end

  describe ":empty_state slot" do
    it "requires the empty_state slot" do
      expect do
        render_inline(described_class.new(work_packages: [], project:, container: sprint, current_user: user)) do |box|
          box.with_footer { "" }
        end
      end.to raise_error(ArgumentError, /empty_state slot is required when no work package items are rendered/)
    end

    it "renders the blankslate when work_packages is empty" do
      expect(rendered_component).to have_text("Sprint 1 is empty")
      expect(rendered_component).to have_text("Drag work packages here")
    end

    context "when there are work packages" do
      let(:work_packages) do
        [
          create(:work_package, project:, type: type_feature, status: default_status,
                                priority: default_priority, sprint:, position: 1)
        ]
      end

      it "does not render the blankslate" do
        expect(rendered_component).to have_no_css(".blankslate")
      end
    end
  end

  describe ":footer slot" do
    let(:footer_content) { "footer-content" }

    it "renders the footer row when supplied" do
      expect(rendered_component).to have_text("footer-content")
    end
  end

  describe "items collection" do
    let(:work_packages) do
      [
        create(:work_package, subject: "WP A", project:, type: type_feature, status: default_status,
                              priority: default_priority, sprint:, position: 1),
        create(:work_package, subject: "WP B", project:, type: type_feature, status: default_status,
                              priority: default_priority, sprint:, position: 2)
      ]
    end

    it_behaves_like "rendering Box", row_count: 2, header: false, footer: false

    it "renders one row per work package" do
      expect(rendered_component).to have_text("WP A")
      expect(rendered_component).to have_text("WP B")
    end

    it "applies the card row attributes in the rendered HTML" do
      work_package = work_packages.first

      expect(rendered_component).to have_css(
        ".Box-row#work_package_#{work_package.id}.Box-row--clickable[data-test-selector='work-package-#{work_package.id}']"
      )
    end

    it "does not include Backlogs row wiring by default" do
      expect(rendered_component).to have_css(".Box-row", count: 2)
      expect(rendered_component).to have_no_css(".Box-row[data-controller='backlogs--story']")
      expect(rendered_component).to have_no_css(".Box-row[data-drop-url]")
      expect(rendered_component).to have_no_css(".Box-row[data-backlogs--story-split-url-value]")
    end

    context "with an item_component_klass" do
      let(:item_component_klass) { custom_item_component_class }

      it "uses the configured item class for automatically built items" do
        expect(rendered_component).to have_css(
          ".Box-row#custom_work_package_#{work_packages.first.id}",
          text: "custom WP A"
        )
        expect(rendered_component).to have_css(
          ".Box-row#custom_work_package_#{work_packages.second.id}",
          text: "custom WP B"
        )
      end
    end
  end

  describe ":work_package_item slot" do
    let(:work_packages) do
      [
        create(:work_package, subject: "WP A", project:, type: type_feature, status: default_status,
                              priority: default_priority, sprint:, position: 1),
        create(:work_package, subject: "WP B", project:, type: type_feature, status: default_status,
                              priority: default_priority, sprint:, position: 2)
      ]
    end
    let(:params) { { all: 1 } }
    let(:slot_work_package) { work_packages.first }

    def render_with_manual_item
      render_inline(
        described_class.new(work_packages: [], project:, container:, params:, current_user: user)
      ) do |box|
        box.with_empty_state(title: "empty", description: "drag here")
        box.with_work_package_item(
          work_package: slot_work_package,
          component_klass: custom_item_component_class,
          data: { source: "slot" }
        )
      end
    end

    it "builds rows with the configured item component class" do
      rendered = render_with_manual_item

      expect(rendered).to have_css(".Box-row#custom_work_package_#{work_packages.first.id}", text: "custom WP A")
      expect(rendered).to have_css(".Box-row[data-source='slot']")
      expect(rendered).to have_css(".Box-row[data-params='all=1']")
    end

    it "does not also build automatic work package rows" do
      rendered = render_inline(
        described_class.new(work_packages:, project:, container:, params:, current_user: user)
      ) do |box|
        box.with_empty_state(title: "empty", description: "drag here")
        box.with_work_package_item(work_package: slot_work_package)
      end

      expect(rendered).to have_css(".Box-row", count: 1)
      expect(rendered).to have_text("WP A")
      expect(rendered).to have_no_text("WP B")
    end

    it "uses caller-provided metric content for manual work package items" do
      rendered = render_inline(
        described_class.new(project:, container:, params:, current_user: user)
      ) do |box|
        box.with_empty_state(title: "empty", description: "drag here")
        box.with_work_package_item(work_package: slot_work_package) do |item|
          item.with_metric { "manual metric" }
        end
      end

      expect(rendered).to have_text("manual metric")
    end

    it "exposes build_item for building an item without adding it to the box" do
      component = described_class.new(work_packages: [], project:, container:, params:, current_user: user)

      item = component.build_item(
        work_package: slot_work_package,
        component_klass: custom_item_component_class,
        data: { source: "builder" }
      )

      expect(item.row_args).to include(
        id: "custom_work_package_#{slot_work_package.id}",
        data: { params: "all=1", context_size: 3, source: "builder" }
      )
    end
  end

  describe ":empty_item slot" do
    it "renders a caller-provided empty item row" do
      rendered = render_inline(described_class.new(project:, container:, current_user: user)) do |box|
        box.with_empty_item(data: { test_selector: "manual-empty-item" }) do
          "Nothing to show"
        end
      end

      expect(rendered).to have_css(
        ".Box-row[data-empty-list-item='true'][data-test-selector='manual-empty-item']",
        text: "Nothing to show"
      )
    end

    it "raises when combined with automatic work packages" do
      work_package = create(:work_package, project:, type: type_feature, status: default_status,
                                           priority: default_priority, sprint:, position: 1)

      expect do
        render_inline(
          described_class.new(work_packages: [work_package], project:, container:, current_user: user)
        ) do |box|
          box.with_empty_state(title: "empty", description: "drag here")
          box.with_empty_item { "Nothing to show" }
        end
      end.to raise_error(ArgumentError, /empty_item cannot be combined with work_packages/)
    end

    it "raises when combined with manual work package items" do
      work_package = create(:work_package, project:, type: type_feature, status: default_status,
                                           priority: default_priority, sprint:, position: 1)

      expect do
        render_inline(described_class.new(project:, container:, current_user: user)) do |box|
          box.with_empty_state(title: "empty", description: "drag here")
          box.with_work_package_item(work_package:)
          box.with_empty_item { "Nothing to show" }
        end
      end.to raise_error(ArgumentError, /empty_item cannot be combined with other items/)
    end

    it "raises when combined with generic items" do
      expect do
        render_inline(described_class.new(project:, container:, current_user: user)) do |box|
          box.with_empty_state(title: "empty", description: "drag here")
          box.with_item { "Manual item" }
          box.with_empty_item { "Nothing to show" }
        end
      end.to raise_error(ArgumentError, /empty_item cannot be combined with other items/)
    end
  end

  describe ":item slot" do
    let(:work_packages) do
      [
        create(:work_package, subject: "WP A", project:, type: type_feature, status: default_status,
                              priority: default_priority, sprint:, position: 1),
        create(:work_package, subject: "WP B", project:, type: type_feature, status: default_status,
                              priority: default_priority, sprint:, position: 2)
      ]
    end

    it "renders caller-provided content with caller-provided item arguments" do
      rendered = render_inline(described_class.new(project:, container:, current_user: user)) do |box|
        box.with_empty_state(title: "empty", description: "drag here")
        box.with_item(
          id: "manual-item",
          scheme: :neutral,
          data: { test_selector: "manual-item" }
        ) do
          "Manual item"
        end
      end

      expect(rendered).to have_css(
        ".Box-row#manual-item[data-test-selector='manual-item']",
        text: "Manual item"
      )
    end

    it "can be interleaved with work package item rows" do
      rendered = render_inline(described_class.new(project:, container:, current_user: user)) do |box|
        box.with_empty_state(title: "empty", description: "drag here")
        box.with_work_package_item(work_package: work_packages.first)
        box.with_item(id: "manual-item") { "Manual item" }
        box.with_work_package_item(work_package: work_packages.second)
      end

      expect(rendered).to have_css(".Box-row", count: 3)
      expect(rendered).to have_css("li.Box-row:nth-child(1)", text: "WP A")
      expect(rendered).to have_css("li.Box-row:nth-child(2)#manual-item", text: "Manual item")
      expect(rendered).to have_css("li.Box-row:nth-child(3)", text: "WP B")
    end

    it "does not build automatic work package rows when manual rows are supplied" do
      rendered = render_inline(
        described_class.new(work_packages:, project:, container:, current_user: user)
      ) do |box|
        box.with_empty_state(title: "empty", description: "drag here")
        box.with_item(id: "manual-item") { "Manual item" }
      end

      expect(rendered).to have_css(".Box-row", count: 1)
      expect(rendered).to have_text("Manual item")
      expect(rendered).to have_no_text("WP A")
      expect(rendered).to have_no_text("WP B")
    end
  end
end
