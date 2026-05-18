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

RSpec.describe ProjectIdentifiers::RevertProjectToClassicService do
  describe "#call" do
    context "when the project has a classic identifier in FriendlyId history" do
      let!(:project) do
        create(:project).tap do |p|
          p.update_columns(identifier: "MYAPP", wp_sequence_counter: 0)
          FriendlyId::Slug.create!(sluggable: p, slug: "my-app")
        end
      end

      before { described_class.new(project).call }

      it "restores the classic identifier" do
        expect(project.reload.identifier).to eq("my-app")
      end

      it "does not enqueue Notifications::WorkflowJob for the identifier change" do
        project2 = create(:project).tap do |p|
          p.update_columns(identifier: "OTHER", wp_sequence_counter: 0)
          FriendlyId::Slug.create!(sluggable: p, slug: "other-name")
        end
        expect { described_class.new(project2).call }
          .not_to have_enqueued_job(Notifications::WorkflowJob)
      end
    end

    context "when the project has multiple slugs in FriendlyId history" do
      let!(:project) do
        create(:project).tap do |p|
          p.update_columns(identifier: "MYAPP", wp_sequence_counter: 0)
          FriendlyId::Slug.create!(sluggable: p, slug: "old-name", created_at: 2.hours.ago)
          FriendlyId::Slug.create!(sluggable: p, slug: "newer-name", created_at: 1.hour.ago)
        end
      end

      before { described_class.new(project).call }

      it "restores the most recent classic slug" do
        expect(project.reload.identifier).to eq("newer-name")
      end
    end

    context "when the project has only semantic identifiers in FriendlyId history" do
      let!(:project) do
        create(:project).tap do |p|
          p.update_columns(identifier: "MYAPP", wp_sequence_counter: 3)
          FriendlyId::Slug.where(sluggable: p).delete_all
          FriendlyId::Slug.create!(sluggable: p, slug: "MYAPP")
        end
      end

      before do
        allow(Setting::WorkPackageIdentifier).to receive_messages(classic?: true, semantic?: false)
        described_class.new(project).call
      end

      it "generates a classic identifier from the project name" do
        expect(project.reload.identifier).to eq(project.name.to_url.first(Projects::Identifier::CLASSIC_IDENTIFIER_MAX_LENGTH))
      end
    end

    context "when the project name produces no URL-safe slug" do
      let!(:project) do
        create(:project).tap do |p|
          p.update_columns(name: "!!!", identifier: "MYAPP", wp_sequence_counter: 0)
          FriendlyId::Slug.where(sluggable: p).delete_all
          FriendlyId::Slug.create!(sluggable: p, slug: "MYAPP")
        end
      end

      before do
        allow(Setting::WorkPackageIdentifier).to receive_messages(classic?: true, semantic?: false)
        described_class.new(project).call
      end

      it "assigns a project-NNNNN fallback identifier" do
        expect(project.reload.identifier).to match(/\Aproject-[a-z0-9]{5}\z/)
      end
    end

    context "when the classic identifier from history is taken by another project" do
      let!(:other_project) { create(:project, identifier: "my-app") }
      let!(:project) do
        create(:project).tap do |p|
          p.update_columns(identifier: "MYAPP", wp_sequence_counter: 0)
          FriendlyId::Slug.create!(sluggable: p, slug: "my-app")
        end
      end

      before { allow(Setting::WorkPackageIdentifier).to receive_messages(classic?: true, semantic?: false) }

      it "raises ActiveRecord::RecordInvalid" do
        expect { described_class.new(project).call }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "when the classic identifier from history is historically reserved by another project" do
      let!(:other_project) do
        create(:project).tap do |p|
          FriendlyId::Slug.create!(sluggable: p, slug: "my-app")
        end
      end
      let!(:project) do
        create(:project).tap do |p|
          p.update_columns(identifier: "MYAPP", wp_sequence_counter: 0)
          FriendlyId::Slug.create!(sluggable: p, slug: "my-app")
        end
      end

      before { allow(Setting::WorkPackageIdentifier).to receive_messages(classic?: true, semantic?: false) }

      it "raises ActiveRecord::RecordInvalid" do
        expect { described_class.new(project).call }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end
