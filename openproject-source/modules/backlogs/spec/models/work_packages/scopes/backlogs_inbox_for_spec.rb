# frozen_string_literal: true

# -- copyright
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
# ++

require "spec_helper"

RSpec.describe WorkPackages::Scopes::BacklogsInboxFor do
  let(:project) { create(:project) }
  let(:open_status) { create(:status, is_closed: false) }
  let(:closed_status) { create(:status, is_closed: true) }
  let(:sprint) { create(:sprint, project:) }

  before { login_as create(:admin) }

  subject(:inbox) { WorkPackage.backlogs_inbox_for(project:) }

  describe ".backlogs_inbox_for" do
    it "returns work packages with no sprint assigned and open status" do
      inbox_wp = create(:work_package, project:, status: open_status)
      create(:work_package, project:, status: closed_status)
      create(:work_package, project:, status: open_status, sprint:)

      expect(inbox).to contain_exactly(inbox_wp)
    end

    it "excludes work packages from other projects" do
      create(:work_package, status: open_status)
      own_wp = create(:work_package, project:, status: open_status)

      expect(inbox).to contain_exactly(own_wp)
    end

    it "orders by position ascending, falling back to id for unpositioned items" do
      wp1 = create(:work_package, project:, status: open_status, position: 2)
      wp2 = create(:work_package, project:, status: open_status, position: 1)
      wp3 = create(:work_package, project:, status: open_status, position: nil)
      wp4 = create(:work_package, project:, status: open_status, position: nil)

      wp3.update_column(:position, nil)
      wp4.update_column(:position, nil)

      expect(inbox).to eq([wp2, wp1, wp3, wp4])
    end
  end
end
