# frozen_string_literal: true

# Tamil Zorous: Send instant emails for all important work-package events
# Uses TzWorkPackageMailer for proper subjects (assigned/commented/etc.)

Rails.application.config.after_initialize do
  supported = %i[mentioned assigned responsible commented created shared watched]

  Notifications::CreateFromModelService::WorkPackageStrategy
    .define_singleton_method(:supports_mail?) { |reason| reason.in?(supported) }

  Notifications::MailService::WorkPackageStrategy
    .define_singleton_method(:send_mail) do |notification|
      reason = notification.reason&.to_sym
      return unless reason&.in?(supported)
      user_prefs = (notification.recipient.pref.immediate_reminders rescue {})
      return unless user_prefs["mentioned"] || user_prefs[:mentioned]
      return unless notification.journal
      TzWorkPackageMailer
        .notify(notification.recipient, notification.journal, reason)
        .deliver_later
    end

  Rails.logger.info "[TZ] Instant mail: patched with TzWorkPackageMailer"
rescue => e
  Rails.logger.error "[TZ] Instant mail FAILED: #{e.class} #{e.message}"
end
