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

RSpec.describe WorkPackage, "positions" do # rubocop:disable RSpec/SpecFilePathFormat
  def create_work_package(options)
    create(:work_package, options.reverse_merge(project:, type_id: type.id))
  end

  shared_let(:project) { create(:project) }
  shared_let(:type) { create(:type) }
  shared_let(:sprint1) { create(:sprint, project:, name: "Sprint 1") }
  shared_let(:sprint2) { create(:sprint, project:, name: "Sprint 2") }
  shared_let(:bucket1) { create(:backlog_bucket, project:, name: "Bucket 1") }
  shared_let(:bucket2) { create(:backlog_bucket, project:, name: "Bucket 2") }

  let!(:sprint1_wp1) { create_work_package(subject: "Sprint 1 WorkPackage 1", sprint: sprint1) }
  let!(:sprint1_wp2) { create_work_package(subject: "Sprint 1 WorkPackage 2", sprint: sprint1) }
  let!(:sprint1_wp3) { create_work_package(subject: "Sprint 1 WorkPackage 3", sprint: sprint1) }
  let!(:sprint1_wp4) { create_work_package(subject: "Sprint 1 WorkPackage 4", sprint: sprint1) }
  let!(:sprint1_wp5) { create_work_package(subject: "Sprint 1 WorkPackage 5", sprint: sprint1) }

  let!(:sprint2_wp1) { create_work_package(subject: "Sprint 2 WorkPackage 1", sprint: sprint2) }
  let!(:sprint2_wp2) { create_work_package(subject: "Sprint 2 WorkPackage 2", sprint: sprint2) }
  let!(:sprint2_wp3) { create_work_package(subject: "Sprint 2 WorkPackage 3", sprint: sprint2) }

  let!(:inbox_wp1) { create_work_package(subject: "Inbox WorkPackage 1") }
  let!(:inbox_wp2) { create_work_package(subject: "Inbox WorkPackage 2") }
  let!(:inbox_wp3) { create_work_package(subject: "Inbox WorkPackage 3") }

  let!(:bucket1_wp1) { create_work_package(subject: "Bucket 1 WorkPackage 1", backlog_bucket: bucket1) }
  let!(:bucket1_wp2) { create_work_package(subject: "Bucket 1 WorkPackage 2", backlog_bucket: bucket1) }
  let!(:bucket1_wp3) { create_work_package(subject: "Bucket 1 WorkPackage 3", backlog_bucket: bucket1) }
  let!(:bucket1_wp4) { create_work_package(subject: "Bucket 1 WorkPackage 4", backlog_bucket: bucket1) }
  let!(:bucket1_wp5) { create_work_package(subject: "Bucket 1 WorkPackage 5", backlog_bucket: bucket1) }

  let!(:bucket2_wp1) { create_work_package(subject: "Bucket 2 WorkPackage 1", backlog_bucket: bucket2) }
  let!(:bucket2_wp2) { create_work_package(subject: "Bucket 2 WorkPackage 2", backlog_bucket: bucket2) }
  let!(:bucket2_wp3) { create_work_package(subject: "Bucket 2 WorkPackage 3", backlog_bucket: bucket2) }

  def wp_of_sprint_by_id_and_position(sprint)
    WorkPackage.where(sprint:).pluck(:id, :position).to_h
  end

  def wp_of_inbox_by_id_and_position
    WorkPackage.where(sprint: nil, backlog_bucket: nil).pluck(:id, :position).to_h
  end

  def wp_of_bucket_by_id_and_position(bucket)
    WorkPackage.where(backlog_bucket: bucket).pluck(:id, :position).to_h
  end

  context "when creating a work_package in a sprint" do
    it "puts them in order" do
      new_work_package = create_work_package(subject: "Newest WorkPackage", sprint: sprint1)

      expect(wp_of_sprint_by_id_and_position(sprint1))
        .to eq(sprint1_wp1.id => 1,
               sprint1_wp2.id => 2,
               sprint1_wp3.id => 3,
               sprint1_wp4.id => 4,
               sprint1_wp5.id => 5,
               new_work_package.id => 6)
    end
  end

  context "when creating a work_package in the inbox" do
    it "puts them in order" do
      new_work_package = create_work_package(subject: "Newest WorkPackage")

      expect(wp_of_inbox_by_id_and_position)
        .to eq(inbox_wp1.id => 1,
               inbox_wp2.id => 2,
               inbox_wp3.id => 3,
               new_work_package.id => 4)
    end
  end

  context "when creating a work_package in a backlog bucket" do
    it "puts them in order" do
      new_work_package = create_work_package(subject: "Newest WorkPackage", backlog_bucket: bucket1)

      expect(wp_of_bucket_by_id_and_position(bucket1))
        .to eq(bucket1_wp1.id => 1,
               bucket1_wp2.id => 2,
               bucket1_wp3.id => 3,
               bucket1_wp4.id => 4,
               bucket1_wp5.id => 5,
               new_work_package.id => 6)
    end
  end

  context "when moving a work_package to a different sprint" do
    it "reorders the remaining work_packages and the ones in the new sprint" do
      sprint1_wp2.sprint = sprint2
      sprint1_wp2.save!

      expect(wp_of_sprint_by_id_and_position(sprint1))
        .to eq(sprint1_wp1.id => 1,
               sprint1_wp3.id => 2,
               sprint1_wp4.id => 3,
               sprint1_wp5.id => 4)

      expect(wp_of_sprint_by_id_and_position(sprint2))
        .to eq(sprint2_wp1.id => 1,
               sprint2_wp2.id => 2,
               sprint2_wp3.id => 3,
               sprint1_wp2.id => 4)
    end
  end

  context "when removing a work_package from a sprint" do
    it "reorders the remaining work_packages and the ones in the inbox" do
      sprint1_wp2.sprint = nil
      sprint1_wp2.save!

      expect(wp_of_sprint_by_id_and_position(sprint1))
        .to eq(sprint1_wp1.id => 1,
               sprint1_wp3.id => 2,
               sprint1_wp4.id => 3,
               sprint1_wp5.id => 4)

      expect(wp_of_inbox_by_id_and_position)
        .to eq(inbox_wp1.id => 1,
               inbox_wp2.id => 2,
               inbox_wp3.id => 3,
               sprint1_wp2.id => 4)
    end
  end

  context "when moving a work_package from the inbox into a sprint" do
    it "reorders the remaining inbox work_packages and the ones in the new sprint" do
      inbox_wp2.sprint = sprint1
      inbox_wp2.save!

      expect(wp_of_inbox_by_id_and_position)
        .to eq(inbox_wp1.id => 1,
               inbox_wp3.id => 2)

      expect(wp_of_sprint_by_id_and_position(sprint1))
        .to eq(sprint1_wp1.id => 1,
               sprint1_wp2.id => 2,
               sprint1_wp3.id => 3,
               sprint1_wp4.id => 4,
               sprint1_wp5.id => 5,
               inbox_wp2.id => 6)
    end
  end

  context "when deleting a work_package in a sprint" do
    it "reorders the existing work_packages" do
      sprint1_wp3.destroy!

      expect(wp_of_sprint_by_id_and_position(sprint1))
        .to eq(sprint1_wp1.id => 1,
               sprint1_wp2.id => 2,
               sprint1_wp4.id => 3,
               sprint1_wp5.id => 4)
    end
  end

  context "when deleting a work_package in the inbox" do
    it "reorders the existing work_packages" do
      inbox_wp1.destroy!

      expect(wp_of_inbox_by_id_and_position)
        .to eq(inbox_wp2.id => 1,
               inbox_wp3.id => 2)
    end
  end

  context "when moving a work_package to a different backlog bucket" do
    it "reorders the remaining work_packages and the ones in the new bucket" do
      bucket1_wp2.backlog_bucket = bucket2
      bucket1_wp2.save!

      expect(wp_of_bucket_by_id_and_position(bucket1))
        .to eq(bucket1_wp1.id => 1,
               bucket1_wp3.id => 2,
               bucket1_wp4.id => 3,
               bucket1_wp5.id => 4)

      expect(wp_of_bucket_by_id_and_position(bucket2))
        .to eq(bucket2_wp1.id => 1,
               bucket2_wp2.id => 2,
               bucket2_wp3.id => 3,
               bucket1_wp2.id => 4)
    end
  end

  context "when removing a work_package from a backlog bucket" do
    it "reorders the remaining work_packages and the ones in the inbox" do
      bucket1_wp2.backlog_bucket = nil
      bucket1_wp2.save!

      expect(wp_of_bucket_by_id_and_position(bucket1))
        .to eq(bucket1_wp1.id => 1,
               bucket1_wp3.id => 2,
               bucket1_wp4.id => 3,
               bucket1_wp5.id => 4)

      expect(wp_of_inbox_by_id_and_position)
        .to eq(inbox_wp1.id => 1,
               inbox_wp2.id => 2,
               inbox_wp3.id => 3,
               bucket1_wp2.id => 4)
    end
  end

  context "when moving a work_package from the inbox into a backlog bucket" do
    it "reorders the remaining inbox work_packages and the ones in the bucket" do
      inbox_wp2.backlog_bucket = bucket1
      inbox_wp2.save!

      expect(wp_of_inbox_by_id_and_position)
        .to eq(inbox_wp1.id => 1,
               inbox_wp3.id => 2)

      expect(wp_of_bucket_by_id_and_position(bucket1))
        .to eq(bucket1_wp1.id => 1,
               bucket1_wp2.id => 2,
               bucket1_wp3.id => 3,
               bucket1_wp4.id => 4,
               bucket1_wp5.id => 5,
               inbox_wp2.id => 6)
    end
  end

  context "when deleting a work_package in a backlog bucket" do
    it "reorders the existing work_packages" do
      bucket1_wp3.destroy!

      expect(wp_of_bucket_by_id_and_position(bucket1))
        .to eq(bucket1_wp1.id => 1,
               bucket1_wp2.id => 2,
               bucket1_wp4.id => 3,
               bucket1_wp5.id => 4)
    end
  end

  context "when moving a work_package from a sprint into a backlog bucket" do
    it "reorders the remaining sprint work_packages and the ones in the bucket" do
      sprint1_wp4.backlog_bucket = bucket1
      sprint1_wp4.sprint = nil
      sprint1_wp4.save!

      expect(wp_of_sprint_by_id_and_position(sprint1))
        .to eq(sprint1_wp1.id => 1,
               sprint1_wp2.id => 2,
               sprint1_wp3.id => 3,
               sprint1_wp5.id => 4)

      expect(wp_of_bucket_by_id_and_position(bucket1))
        .to eq(bucket1_wp1.id => 1,
               bucket1_wp2.id => 2,
               bucket1_wp3.id => 3,
               bucket1_wp4.id => 4,
               bucket1_wp5.id => 5,
               sprint1_wp4.id => 6)
    end
  end

  context "when moving a work_package from a backlog into a sprint bucket" do
    it "reorders the remaining sprint work_packages and the ones in the bucket" do
      bucket1_wp3.update(backlog_bucket: nil, sprint: sprint1)

      expect(wp_of_bucket_by_id_and_position(bucket1))
        .to eq(bucket1_wp1.id => 1,
               bucket1_wp2.id => 2,
               bucket1_wp4.id => 3,
               bucket1_wp5.id => 4)

      expect(wp_of_sprint_by_id_and_position(sprint1))
        .to eq(sprint1_wp1.id => 1,
               sprint1_wp2.id => 2,
               sprint1_wp3.id => 3,
               sprint1_wp4.id => 4,
               sprint1_wp5.id => 5,
               bucket1_wp3.id => 6)
    end
  end

  describe "#move_after" do
    context "when moving inside a sprint with a position of 1" do
      it "moves the work_package to the beginning of the sprint" do
        sprint1_wp4.move_after(position: 1)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp4.id => 1,
                 sprint1_wp1.id => 2,
                 sprint1_wp2.id => 3,
                 sprint1_wp3.id => 4,
                 sprint1_wp5.id => 5)
      end
    end

    context "when moving down inside a sprint with a position in the middle of the sprint" do
      it "moves the work_package to the middle of the sprint" do
        sprint1_wp1.move_after(position: 3)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp2.id => 1,
                 sprint1_wp3.id => 2,
                 sprint1_wp1.id => 3,
                 sprint1_wp4.id => 4,
                 sprint1_wp5.id => 5)
      end
    end

    context "when moving up inside a sprint with a position in the middle of the sprint" do
      it "moves the work_package to the middle of the sprint" do
        sprint1_wp5.move_after(position: 3)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp1.id => 1,
                 sprint1_wp2.id => 2,
                 sprint1_wp5.id => 3,
                 sprint1_wp3.id => 4,
                 sprint1_wp4.id => 5)
      end
    end

    context "when moving inside a sprint with a position at the end of the sprint" do
      it "moves the work_package to the end of the sprint" do
        sprint1_wp2.move_after(position: 5)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp1.id => 1,
                 sprint1_wp3.id => 2,
                 sprint1_wp4.id => 3,
                 sprint1_wp5.id => 4,
                 sprint1_wp2.id => 5)
      end
    end

    context "when moving inside a sprint with a position that is larger than the positions present in the sprint" do
      it "moves the work_package to the top of the sprint" do
        sprint1_wp2.move_after(position: 6)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp2.id => 1,
                 sprint1_wp1.id => 2,
                 sprint1_wp3.id => 3,
                 sprint1_wp4.id => 4,
                 sprint1_wp5.id => 5)
      end
    end

    context "when moving inside a sprint with a previous that is the first element" do
      it "moves the work_package to the second position" do
        sprint1_wp4.move_after(prev_id: sprint1_wp1.id)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp1.id => 1,
                 sprint1_wp4.id => 2,
                 sprint1_wp2.id => 3,
                 sprint1_wp3.id => 4,
                 sprint1_wp5.id => 5)
      end
    end

    context "when moving down inside a sprint with a previous in the middle" do
      it "moves the work_package after the previous" do
        sprint1_wp1.move_after(prev_id: sprint1_wp3.id)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp2.id => 1,
                 sprint1_wp3.id => 2,
                 sprint1_wp1.id => 3,
                 sprint1_wp4.id => 4,
                 sprint1_wp5.id => 5)
      end
    end

    context "when moving up inside a sprint with a previous in the middle" do
      it "moves the work_package after the previous" do
        sprint1_wp5.move_after(prev_id: sprint1_wp3.id)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp1.id => 1,
                 sprint1_wp2.id => 2,
                 sprint1_wp3.id => 3,
                 sprint1_wp5.id => 4,
                 sprint1_wp4.id => 5)
      end
    end

    context "when inside a sprint with a previous at the bottom" do
      it "moves the work_package after the previous" do
        sprint1_wp1.move_after(prev_id: sprint1_wp5.id)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp2.id => 1,
                 sprint1_wp3.id => 2,
                 sprint1_wp4.id => 3,
                 sprint1_wp5.id => 4,
                 sprint1_wp1.id => 5)
      end
    end

    context "when inside a sprint with a previous that does not exist in that sprint" do
      it "moves the work_package to the top of the sprint" do
        sprint1_wp4.move_after(prev_id: sprint2_wp2.id)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp4.id => 1,
                 sprint1_wp1.id => 2,
                 sprint1_wp2.id => 3,
                 sprint1_wp3.id => 4,
                 sprint1_wp5.id => 5)
      end
    end

    context "when inside a sprint with a previous that is nil" do
      it "moves the work_package to the top of the sprint" do
        sprint1_wp4.move_after(prev_id: nil)

        expect(wp_of_sprint_by_id_and_position(sprint1))
          .to eq(sprint1_wp4.id => 1,
                 sprint1_wp1.id => 2,
                 sprint1_wp2.id => 3,
                 sprint1_wp3.id => 4,
                 sprint1_wp5.id => 5)
      end
    end

    context "when moving in the inbox with a position of 1" do
      it "moves the work_package to the beginning of the sprint" do
        inbox_wp3.move_after(position: 1)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp3.id => 1,
                 inbox_wp1.id => 2,
                 inbox_wp2.id => 3)
      end
    end

    context "when moving down in the inbox with a position in the middle of the sprint" do
      it "moves the work_package to the middle of the sprint" do
        inbox_wp1.move_after(position: 2)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp2.id => 1,
                 inbox_wp1.id => 2,
                 inbox_wp3.id => 3)
      end
    end

    context "when moving up in the inbox with a position in the middle of the sprint" do
      it "moves the work_package to the middle of the sprint" do
        inbox_wp3.move_after(position: 2)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp1.id => 1,
                 inbox_wp3.id => 2,
                 inbox_wp2.id => 3)
      end
    end

    context "when moving in the inbox with a position at the end of the sprint" do
      it "moves the work_package to the end of the sprint" do
        inbox_wp1.move_after(position: 3)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp2.id => 1,
                 inbox_wp3.id => 2,
                 inbox_wp1.id => 3)
      end
    end

    context "when moving in the inbox with a position that is larger than the positions present in the sprint" do
      it "moves the work_package to the top of the sprint" do
        inbox_wp2.move_after(position: 4)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp2.id => 1,
                 inbox_wp1.id => 2,
                 inbox_wp3.id => 3)
      end
    end

    context "when moving in the inbox with a previous that is nil" do
      it "moves the work_package to the top of the sprint" do
        inbox_wp3.move_after(prev_id: nil)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp3.id => 1,
                 inbox_wp1.id => 2,
                 inbox_wp2.id => 3)
      end
    end

    context "when moving in the inbox with a previous that is the first element" do
      it "moves the work_package to the second position" do
        inbox_wp3.move_after(prev_id: inbox_wp1.id)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp1.id => 1,
                 inbox_wp3.id => 2,
                 inbox_wp2.id => 3)
      end
    end

    context "when moving down in the inbox with a previous in the middle" do
      it "moves the work_package after the previous" do
        inbox_wp1.move_after(prev_id: inbox_wp2.id)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp2.id => 1,
                 inbox_wp1.id => 2,
                 inbox_wp3.id => 3)
      end
    end

    context "when moving up in the inbox with a previous in the middle" do
      it "moves the work_package after the previous" do
        inbox_wp3.move_after(prev_id: inbox_wp1.id)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp1.id => 1,
                 inbox_wp3.id => 2,
                 inbox_wp2.id => 3)
      end
    end

    context "when in the inbox with a previous at the bottom" do
      it "moves the work_package after the previous" do
        inbox_wp1.move_after(prev_id: inbox_wp3.id)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp2.id => 1,
                 inbox_wp3.id => 2,
                 inbox_wp1.id => 3)
      end
    end

    context "when in the inbox with a previous referencing a work package not in it" do
      it "moves the work_package to the top position" do
        inbox_wp3.move_after(prev_id: sprint2_wp2.id)

        expect(wp_of_inbox_by_id_and_position)
          .to eq(inbox_wp3.id => 1,
                 inbox_wp1.id => 2,
                 inbox_wp2.id => 3)
      end
    end

    context "when moving inside a bucket with a position of 1" do
      it "moves the work_package to the beginning of the bucket" do
        bucket1_wp4.move_after(position: 1)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp4.id => 1,
                 bucket1_wp1.id => 2,
                 bucket1_wp2.id => 3,
                 bucket1_wp3.id => 4,
                 bucket1_wp5.id => 5)
      end
    end

    context "when moving down inside a bucket with a position in the middle" do
      it "moves the work_package to the middle of the bucket" do
        bucket1_wp1.move_after(position: 3)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp2.id => 1,
                 bucket1_wp3.id => 2,
                 bucket1_wp1.id => 3,
                 bucket1_wp4.id => 4,
                 bucket1_wp5.id => 5)
      end
    end

    context "when moving up inside a bucket with a position in the middle" do
      it "moves the work_package to the middle of the bucket" do
        bucket1_wp5.move_after(position: 3)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp1.id => 1,
                 bucket1_wp2.id => 2,
                 bucket1_wp5.id => 3,
                 bucket1_wp3.id => 4,
                 bucket1_wp4.id => 5)
      end
    end

    context "when moving inside a bucket with a position at the end" do
      it "moves the work_package to the end of the bucket" do
        bucket1_wp2.move_after(position: 5)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp1.id => 1,
                 bucket1_wp3.id => 2,
                 bucket1_wp4.id => 3,
                 bucket1_wp5.id => 4,
                 bucket1_wp2.id => 5)
      end
    end

    context "when moving inside a bucket with a previous that is the first element" do
      it "moves the work_package to the second position" do
        bucket1_wp4.move_after(prev_id: bucket1_wp1.id)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp1.id => 1,
                 bucket1_wp4.id => 2,
                 bucket1_wp2.id => 3,
                 bucket1_wp3.id => 4,
                 bucket1_wp5.id => 5)
      end
    end

    context "when moving inside a bucket with a previous in the middle" do
      it "moves the work_package after the previous" do
        bucket1_wp1.move_after(prev_id: bucket1_wp3.id)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp2.id => 1,
                 bucket1_wp3.id => 2,
                 bucket1_wp1.id => 3,
                 bucket1_wp4.id => 4,
                 bucket1_wp5.id => 5)
      end
    end

    context "when moving inside a bucket with a previous at the bottom" do
      it "moves the work_package to the last position" do
        bucket1_wp1.move_after(prev_id: bucket1_wp5.id)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp2.id => 1,
                 bucket1_wp3.id => 2,
                 bucket1_wp4.id => 3,
                 bucket1_wp5.id => 4,
                 bucket1_wp1.id => 5)
      end
    end

    context "when moving inside a bucket with a previous that is nil" do
      it "moves the work_package to the top of the bucket" do
        bucket1_wp4.move_after(prev_id: nil)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp4.id => 1,
                 bucket1_wp1.id => 2,
                 bucket1_wp2.id => 3,
                 bucket1_wp3.id => 4,
                 bucket1_wp5.id => 5)
      end
    end

    context "when moving inside a bucket with a previous that does not exist in that bucket" do
      it "moves the work_package to the top of the bucket" do
        bucket1_wp4.move_after(prev_id: bucket2_wp2.id)

        expect(wp_of_bucket_by_id_and_position(bucket1))
          .to eq(bucket1_wp4.id => 1,
                 bucket1_wp1.id => 2,
                 bucket1_wp2.id => 3,
                 bucket1_wp3.id => 4,
                 bucket1_wp5.id => 5)
      end
    end
  end
end
