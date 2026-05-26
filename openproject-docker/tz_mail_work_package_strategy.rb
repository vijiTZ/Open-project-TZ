# frozen_string_literal: true

# TZ override: send instant emails for assigned/responsible/commented/etc.
# Uses TzWorkPackageMailer with proper subjects and WP details.

module Notifications::MailService::WorkPackageStrategy
  TZ_SUPPORTED_REASONS = %i[mentioned assigned responsible commented created shared watched].freeze

  class << self
    def send_mail(notification)
      reason = notification.reason&.to_sym
      return unless reason.in?(TZ_SUPPORTED_REASONS)

      user_prefs = (notification.recipient.pref.immediate_reminders rescue {})
      return unless user_prefs["mentioned"] || user_prefs[:mentioned]
      return unless notification.journal

      TzWorkPackageMailer
        .notify(notification.recipient, notification.journal, reason)
        .deliver_later
    end
  end
end
