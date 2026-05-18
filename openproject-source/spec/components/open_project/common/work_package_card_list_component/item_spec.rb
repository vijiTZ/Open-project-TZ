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

RSpec.describe OpenProject::Common::WorkPackageCardListComponent::Item, type: :component do
  shared_let(:type_feature) { create(:type_feature) }
  shared_let(:default_status) { create(:default_status) }
  shared_let(:default_priority) { create(:default_priority) }
  shared_let(:user) { create(:admin) }
  current_user { user }

  shared_let(:project) { create(:project, types: [type_feature]) }

  let(:container) { project }
  let(:params) { {} }
  let(:work_package) do
    create(:work_package,
           project:,
           type: type_feature,
           status: default_status,
           priority: default_priority,
           subject: "Card subject",
           story_points: 5,
           position: 1)
  end
  let(:item) do
    described_class.new(work_package:, project:, container:, params:, current_user: user)
  end
  let(:draggable_item_class) do
    stub_const(
      "DraggableWorkPackageCardListItem",
      Class.new(described_class) do
        private

        def draggable?
          true
        end

        def draggable_data
          {
            draggable_id: work_package.id,
            draggable_type: "work_package",
            drop_url: "/drop"
          }
        end
      end
    )
  end

  describe "#row_args" do
    it "can be passed to a BorderBox row" do
      rendered = render_inline(Primer::Beta::BorderBox.new) do |box|
        box.with_row(**item.row_args) do
          "row body"
        end
      end

      expect(rendered).to have_css(
        ".Box-row#work_package_#{work_package.id}",
        text: "row body"
      )
    end

    it "supplies the work-package row attributes" do
      expect(item.row_args).to include(
        id: "work_package_#{work_package.id}",
        tabindex: 0
      )
      expect(item.row_args[:classes]).to include(
        "Box-row--hover-blue",
        "Box-row--focus-gray",
        "Box-row--clickable"
      )
      expect(item.row_args[:data][:test_selector]).to eq("work-package-#{work_package.id}")
    end

    it "lets caller-supplied data override default row data" do
      item = described_class.new(
        work_package:,
        project:,
        container:,
        params:,
        current_user: user,
        data: {
          story: false,
          test_selector: "custom-work-package-row"
        }
      )

      expect(item.row_args[:data]).to include(
        story: false,
        test_selector: "custom-work-package-row"
      )
    end

    it "does not include Backlogs row wiring" do
      expect(item.row_args[:classes]).not_to include("Box-row--draggable")
      expect(item.row_args[:data]).not_to include(
        :controller,
        :draggable_id,
        :drop_url,
        :backlogs__story_split_url_value
      )
    end

    it "supports generic draggable row data from subclasses" do
      item = draggable_item_class.new(work_package:, project:, container:, params:, current_user: user)

      expect(item.row_args[:classes]).to include("Box-row--draggable")
      expect(item.row_args[:data]).to include(
        draggable_id: work_package.id,
        draggable_type: "work_package",
        drop_url: "/drop"
      )
    end
  end

  describe "#card" do
    subject(:rendered_card) { render_inline(item.card) }

    it "builds the visual card without deriving a menu src" do
      expect(rendered_card).to have_no_element "include-fragment"
    end

    it "returns the same card instance across calls" do
      expect(item.card).to equal(item.card)
    end

    it "forwards metric content to the visual card" do
      item.with_metric { "Forwarded metric" }

      expect(rendered_card).to have_text("Forwarded metric")
    end
  end
end
