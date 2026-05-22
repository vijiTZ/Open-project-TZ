# frozen_string_literal: true

# Custom override of OpenProject's homescreen initializer.
# Bind-mounted over /app/config/initializers/homescreen.rb to:
#   - hide the welcome/new_features/meetings/community blocks
#   - hide the forums (Community forum) footer link

require "open_project/static/homescreen"
require "open_project/static/links"

OpenProject::Static::Homescreen.manage :blocks do |blocks|
  blocks.push(
    {
      name: "projects"
    },
    {
      name: "my_account",
      if: Proc.new { User.current.logged? }
    },
    {
      name: "news"
    },
    {
      name: "administration",
      if: Proc.new { User.current.admin? }
    },
    {
      name: "upsell",
      if: Proc.new { !(EnterpriseToken.active? || EnterpriseToken.hide_banners?) || EnterpriseToken.trial_only? }
    }
  )
end

OpenProject::Static::Homescreen.manage :links do |links|
  links.push(
    {
      label: :user_guides,
      icon: "milestone",
      url_key: :user_guides
    },
    {
      label: :glossary,
      icon: "op-glossar",
      url_key: :glossary
    },
    {
      label: :shortcuts,
      icon: "op-shortcuts",
      url_key: :shortcuts
    },
    {
      label: :impressum,
      icon: "info",
      url_key: :impressum
    }
  )
end
