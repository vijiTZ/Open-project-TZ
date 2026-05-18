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

require "spec_helper"

RSpec.describe API::Decorators::LinkedResource do
  let(:representer) do
    Class.new(API::Decorators::Single) do
      include API::Decorators::LinkedResource

      resource_link :foo,
                    getter: -> { represented["foo"] },
                    setter: ->(fragment:, **) { represented["foo"] = fragment["href"] }
    end
  end
  let(:represented) { {} }
  let(:current_user) { create(:user) }

  describe "#from_hash" do
    subject { representer.new(represented, current_user:).from_hash(input_hash) }

    let(:input_hash) do
      {
        "_links" => {
          "foo" => { "href" => "https://example.com" }
        }
      }
    end

    it "parses the link" do
      expect { subject }.to change { represented["foo"] }.from(nil).to("https://example.com")
    end

    context "when passing link as string" do
      let(:input_hash) do
        {
          "_links" => {
            "foo" => "https://example.com"
          }
        }
      end

      it "raises an error" do
        expect { subject }.to raise_error(API::Errors::BadRequest)
      end
    end

    context "when passing _links as array" do
      let(:input_hash) do
        {
          "_links" => [
            { "foo" => { "href" => "https://example.com" } }
          ]
        }
      end

      it "raises an error" do
        expect { subject }.to raise_error(API::Errors::BadRequest)
      end
    end
  end
end
