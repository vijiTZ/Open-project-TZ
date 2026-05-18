# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserCardView do
  subject(:view) { described_class.new(name: "Team") }

  describe "defaults" do
    it "exposes typed defaults for every option" do
      expect(view.secondary_info).to eq("role")
      expect(view.show_status_badge).to be(true)
      expect(view.show_email).to be(false)
      expect(view.tag_source).to eq("groups")
      expect(view.tag_limit).to eq(3)
      expect(view.card_size).to eq("default")
      expect(view.columns_per_row).to eq(3)
    end

    it "is valid with defaults" do
      expect(view).to be_valid
    end
  end

  describe "round-tripping through JSONB" do
    it "persists and reloads options with their declared types" do
      view.secondary_info = "email"
      view.show_status_badge = false
      view.show_email = true
      view.tag_source = "roles"
      view.tag_limit = 5
      view.card_size = "compact"
      view.columns_per_row = 4
      view.save!

      reloaded = described_class.find(view.id)
      expect(reloaded.secondary_info).to eq("email")
      expect(reloaded.show_status_badge).to be(false)
      expect(reloaded.show_email).to be(true)
      expect(reloaded.tag_source).to eq("roles")
      expect(reloaded.tag_limit).to eq(5)
      expect(reloaded.card_size).to eq("compact")
      expect(reloaded.columns_per_row).to eq(4)
    end

    it "coerces booleans stored as strings" do
      view.show_status_badge = "false"
      expect(view.show_status_badge).to be(false)
    end
  end

  describe "validations" do
    it "rejects an unknown secondary_info" do
      view.secondary_info = "bogus"
      expect(view).not_to be_valid
      expect(view.errors[:secondary_info]).to be_present
    end

    it "rejects an unknown tag_source" do
      view.tag_source = "bogus"
      expect(view).not_to be_valid
      expect(view.errors[:tag_source]).to be_present
    end

    it "rejects an unknown card_size" do
      view.card_size = "huge"
      expect(view).not_to be_valid
      expect(view.errors[:card_size]).to be_present
    end

    it "rejects tag_limit outside 0..10" do
      view.tag_limit = 11
      expect(view).not_to be_valid
      expect(view.errors[:tag_limit]).to be_present
    end

    it "rejects columns_per_row outside 1..4" do
      view.columns_per_row = 0
      expect(view).not_to be_valid
      expect(view.errors[:columns_per_row]).to be_present
    end
  end

  describe "query compatibility" do
    let(:user_query) { UserQuery.create!(name: "UQ") }
    let(:other_query) { PersistedQuery.create!(name: "PQ") }

    it "accepts a UserQuery" do
      view.query = user_query
      expect(view).to be_valid
    end

    it "rejects a non-UserQuery" do
      view.query = other_query
      expect(view).not_to be_valid
      expect(view.errors[:query]).to be_present
    end
  end

  describe "#results" do
    # UserQuery scopes to users visible to the current user. Granting alice
    # :view_all_principals lets her see every user without introducing an
    # extra admin record that would pollute `contain_exactly` expectations.
    let!(:alice)  { create(:user, firstname: "Alice", lastname: "Anderson", global_permissions: %i[view_all_principals]) }
    let!(:bob)    { create(:user, firstname: "Bob",   lastname: "Brown") }
    let!(:locked) { create(:locked_user, firstname: "Carol", lastname: "Clark") }

    before { login_as(alice) }

    it "returns nil when there is no query" do
      expect(view.results).to be_nil
    end

    it "delegates to the effective query and respects its filters" do
      query = UserQuery.new(name: "Active only")
      query.where("status", "=", ["active"])
      query.save!

      view.query = query
      expect(view.results).to contain_exactly(alice, bob)
      expect(view.results).not_to include(locked)
    end

    it "applies a name filter and sort defined on the query" do
      query = UserQuery.new(name: "By name")
      query.where("name", "~", ["Brown"])
      query.save!

      view.query = query
      expect(view.results).to contain_exactly(bob)
    end

    it "bypasses filters and returns manually-added users in their stored order" do
      query = UserQuery.new(name: "Manual")
      query.where("status", "=", ["active"])
      query.save!

      OrderedPersistedQueryEntity.create!(persisted_query: query, entity: bob,    position: 1)
      OrderedPersistedQueryEntity.create!(persisted_query: query, entity: locked, position: 2)
      OrderedPersistedQueryEntity.create!(persisted_query: query, entity: alice,  position: 3)

      view.query = query
      expect(view.results.to_a).to eq([bob, locked, alice])
    end
  end
end
