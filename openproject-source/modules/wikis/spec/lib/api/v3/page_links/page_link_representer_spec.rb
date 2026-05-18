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

module API
  module V3
    module PageLinks
      RSpec.describe PageLinkRepresenter, :rendering do
        include Utilities::PathHelper

        let(:inline_page_link) { build_stubbed(:inline_wiki_page_link) }
        let(:relation_page_link) { build_stubbed(:relation_wiki_page_link) }
        let(:current_user) { build_stubbed(:user) }

        let(:represented) { relation_page_link }
        let(:project) { represented.linkable.project }

        let(:embed_links) { false }
        let(:representer) { described_class.new(represented, current_user:, embed_links:) }

        subject(:resulting_json) { representer.to_json }

        describe "_links" do
          describe "self" do
            it_behaves_like "has a titled link" do
              let(:link) { "self" }
              let(:href) { "/api/v3/wiki_page_links/#{represented.id}" }
              let(:title) { represented.identifier }
            end
          end

          describe "provider" do
            it_behaves_like "has a titled link" do
              let(:link) { "provider" }
              let(:href) { "/api/v3/wiki_providers/#{represented.provider.universal_identifier}" }
              let(:title) { represented.provider.name }
            end
          end

          describe "delete" do
            let(:permission) { :manage_wiki_page_links }

            let(:link) { "delete" }
            let(:href) { "/api/v3/wiki_page_links/#{represented.id}" }
            let(:method) { :delete }

            it_behaves_like "has an untitled action link"

            context "when there is no associated linkable" do
              before { represented.linkable = nil }

              it_behaves_like "has no link"

              context "and the current user is creator of the file link" do
                let(:current_user) { represented.author }

                it { is_expected.to have_json_path("_links/#{link}") }
              end
            end
          end

          describe "author" do
            context "when the page link is an InlinePageLink" do
              let(:represented) { inline_page_link }

              it "does not render the author link" do
                expect(resulting_json).not_to have_json_path("author")
              end
            end

            it_behaves_like "has a titled link" do
              let(:link) { "author" }
              let(:href) { "/api/v3/users/#{represented.author_id}" }
              let(:title) { represented.author.name }
            end
          end

          describe "linkable" do
            it_behaves_like "has a titled link" do
              let(:link) { "linkable" }
              let(:href) { "/api/v3/work_packages/#{represented.linkable_id}" }
              let(:title) { represented.linkable.name }
            end
          end
        end

        describe "properties" do
          describe "wiki_page_link_type" do
            context "when InlinePageLink" do
              let(:represented) { inline_page_link }

              it_behaves_like "property", :wikiPageLinkType do
                let(:value) { URN_INLINE_PAGE_LINK }
              end
            end

            context "when RelationPageLink" do
              it_behaves_like "property", :wikiPageLinkType do
                let(:value) { URN_RELATION_PAGE_LINK }
              end
            end
          end

          describe "_type" do
            context "when InlinePageLink" do
              let(:represented) { inline_page_link }

              it_behaves_like "property", :_type do
                let(:value) { "WikiPageLink" }
              end
            end

            context "when RelationPageLink" do
              it_behaves_like "property", :_type do
                let(:value) { "WikiPageLink" }
              end
            end
          end

          it_behaves_like "property", :identifier do
            let(:value) { represented.identifier }
          end

          it_behaves_like "datetime property", :createdAt do
            let(:value) { represented.created_at }
          end

          it_behaves_like "datetime property", :updatedAt do
            let(:value) { represented.updated_at }
          end
        end
      end
    end
  end
end
