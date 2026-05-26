# frozen_string_literal: true

# TZ override: supports_mail? returns true for all important reasons
# (upstream only returns true for :mentioned)

module Notifications::CreateFromModelService::WorkPackageStrategy
  def self.reasons
    %i(mentioned assigned responsible watched commented created processed prioritized scheduled shared)
  end

  def self.permission(journal, _reason)
    if journal&.internal?
      :view_internal_comments
    else
      :view_work_packages
    end
  end

  def self.supports_ian?(_reason)
    true
  end

  def self.supports_mail_digest?(_reason)
    true
  end

  def self.supports_mail?(reason)
    reason.in?(%i[mentioned assigned responsible commented created shared watched])
  end

  def self.watcher_users(journal)
    User.watcher_recipients(journal.journable)
  end

  def self.shared_users(journal)
    journal.journable.member_principals
  end

  def self.project(journal)
    journal.data.project
  end

  def self.user(journal)
    journal.user
  end
end
