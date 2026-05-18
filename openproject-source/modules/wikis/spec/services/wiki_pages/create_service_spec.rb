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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe WikiPages::CreateService do
  let(:instance) { described_class.new(user:) }
  let(:user) { create(:admin) }
  let(:wiki) { create(:wiki) }
  let(:internal_provider) { create(:internal_wiki_provider, enabled: true) }

  let(:work_package) { create(:work_package) }

  let(:reverse_link_finder) do
    Wikis::ReverseInlinePageLink.where(linkable: work_package, provider: internal_provider)
  end

  let(:attributes) do
    {
      wiki:,
      text:,
      title: "The test page"
    }
  end

  let(:text) do
    <<~TXT
      The Wiki page references work package ##{work_package.id}.
    TXT
  end

  subject { instance.call(**attributes) }

  before do
    wiki
    internal_provider
  end

  it "succeeds" do
    expect(subject).to be_success
  end

  it "creates a reverse page link" do
    subject

    expect(reverse_link_finder.count).to eq(1)
  end

  it "references the created wiki page" do
    subject

    expect(Wikis::ReverseInlinePageLink.first.identifier).to eq(WikiPage.first.id.to_s)
  end

  context "when the same reference is made twice" do
    let(:text) do
      <<~TXT
        The Wiki page references work package ##{work_package.id} + ##{work_package.id}.
      TXT
    end

    it "creates the link once" do
      subject

      expect(reverse_link_finder.count).to eq(1)
    end
  end

  context "when the reference is the only content (no suffix or prefix)" do
    let(:text) { "##{work_package.id}" }

    it "creates a reverse page link" do
      subject

      expect(reverse_link_finder.count).to eq(1)
    end
  end

  context "when the reference is parenthesized" do
    let(:text) { "(##{work_package.id})" }

    it "creates a reverse page link" do
      subject

      expect(reverse_link_finder.count).to eq(1)
    end
  end

  context "when the reference is escaped" do
    let(:text) { "!##{work_package.id}" }

    it "does not create a link" do
      subject

      expect(Wikis::ReverseInlinePageLink.count).to eq(0)
    end
  end

  context "when the reference is made using ## syntax" do
    let(:text) do
      <<~TXT
        The Wiki page references work package ###{work_package.id}.
      TXT
    end

    it "creates a reverse page link" do
      subject

      expect(reverse_link_finder.count).to eq(1)
    end
  end

  context "when the reference is made using ### syntax" do
    let(:text) do
      <<~TXT
        The Wiki page references work package ####{work_package.id}.
      TXT
    end

    it "creates a reverse page link" do
      subject

      expect(reverse_link_finder.count).to eq(1)
    end
  end

  context "when the reference is made inside a <mention> element" do
    let(:text) do
      <<~TXT
        The Wiki page references work package <mention class="mention" data-id="#{work_package.id}" data-type="work_package" data-text="##{work_package.id}">##{work_package.id}</mention>.
      TXT
    end

    it "creates a reverse page link" do
      subject

      expect(reverse_link_finder.count).to eq(1)
    end
  end

  context "when there is a link with a fragment" do
    let(:text) do
      <<~TXT
        And a weird [link](https://example.com/##{work_package.id}-blubb).
      TXT
    end

    it "does not create a link" do
      subject

      expect(Wikis::ReverseInlinePageLink.count).to eq(0)
    end
  end

  context "when the internal provider is disabled" do
    let(:internal_provider) { create(:internal_wiki_provider, enabled: false) }

    it "does not create a link" do
      subject

      expect(Wikis::ReverseInlinePageLink.count).to eq(0)
    end
  end

  context "when a work package with the given ID does not exist" do
    let(:text) do
      <<~TXT
        The Wiki page references work package ##{work_package.id + 10}.
      TXT
    end

    it "does not create a link" do
      subject

      expect(Wikis::ReverseInlinePageLink.count).to eq(0)
    end
  end
end
