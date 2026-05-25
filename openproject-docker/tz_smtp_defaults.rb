# frozen_string_literal: true

# Tamil Zorous: Set default SMTP configuration in the database so it is
# editable from Administration → Email notifications in the UI.
#
# Environment-variable-based SMTP (OPENPROJECT_SMTP__*) locks the fields
# to read-only in the admin panel. By writing directly to Settings instead,
# the admin can change the values at any time without restarting containers.
#
# This initializer only writes defaults when the settings are still blank
# (first boot or after a DB reset). Once the admin edits them through the
# UI, those values are preserved across restarts.

Rails.application.config.after_initialize do
  begin
    # Only seed if email delivery method hasn't been configured yet
    if Setting.email_delivery_method.blank? || Setting.email_delivery_method == :sendmail
      Rails.logger.info "[TZ] Setting default SMTP configuration (editable via admin UI)..."

      Setting.email_delivery_method = :smtp
      Setting.smtp_address          = "smtp.gmail.com"
      Setting.smtp_port             = 587
      Setting.smtp_authentication   = :plain
      Setting.smtp_user_name        = ENV.fetch("TZ_SMTP_USER", "tamilzorous@gmail.com")
      Setting.smtp_password         = ENV.fetch("TZ_SMTP_PASS", "")
      Setting.smtp_enable_starttls_auto = true

      Rails.logger.info "[TZ] SMTP defaults applied. Change them in Administration → Email notifications."
    end

    # Set mail_from if still default
    if Setting.mail_from.blank? || Setting.mail_from == "openproject@example.net"
      Setting.mail_from = "tamilzorous@gmail.com"
    end

    # Ensure ActionMailer picks up the DB settings
    Setting.reload_mailer_settings!
    Rails.logger.info "[TZ] Mailer settings reloaded from database"
  rescue => e
    Rails.logger.error "[TZ] Failed to set SMTP defaults: #{e.message}"
  end
end
