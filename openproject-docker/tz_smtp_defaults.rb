# frozen_string_literal: true

# Tamil Zorous: Ensure SMTP configuration is always correct on every boot.
#
# The password is read from the TZ_SMTP_PASS environment variable and written
# to the database on every startup. This guarantees emails keep working after
# container restarts without manual intervention.

Rails.application.config.after_initialize do
  begin
    smtp_pass = ENV.fetch("TZ_SMTP_PASS", "")
    smtp_user = ENV.fetch("TZ_SMTP_USER", "tamilzorous@gmail.com")

    # Always ensure SMTP is the delivery method
    if Setting.email_delivery_method.blank? || Setting.email_delivery_method == :sendmail
      Rails.logger.info "[TZ] First boot: setting SMTP defaults..."
      Setting.email_delivery_method = :smtp
      Setting.smtp_address          = "smtp.gmail.com"
      Setting.smtp_port             = 587
      Setting.smtp_authentication   = :plain
      Setting.smtp_enable_starttls_auto = true
    end

    # Always sync the password from env var (survives container restarts)
    if smtp_pass.present?
      current_pass = Setting.smtp_password rescue ""
      if current_pass != smtp_pass
        Setting.smtp_password  = smtp_pass
        Setting.smtp_user_name = smtp_user
        Rails.logger.info "[TZ] SMTP password synced from TZ_SMTP_PASS env var"
      end
    end

    # Set mail_from if still default
    if Setting.mail_from.blank? || Setting.mail_from == "openproject@example.net"
      Setting.mail_from = smtp_user
    end

    # Ensure ActionMailer picks up the DB settings
    Setting.reload_mailer_settings!
    Rails.logger.info "[TZ] Mailer settings reloaded (SMTP: #{Setting.smtp_address}:#{Setting.smtp_port})"
  rescue => e
    Rails.logger.error "[TZ] Failed to set SMTP defaults: #{e.message}"
  end
end
