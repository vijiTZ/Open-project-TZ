# frozen_string_literal: true

# Tamil Zorous: Change the PR-to-WP linking prefix from OP# to TZ#.
# Developers now write "TZ#5" in PR titles/bodies instead of "OP#5".
# Both prefixes are accepted so existing PRs with OP# still work.

Rails.application.config.after_initialize do
  begin
    helper = OpenProject::GithubIntegration::NotificationHandler::Helper

    helper.define_method(:extract_work_package_ids) do |text|
      host_name = Regexp.escape(Setting.host_name)
      # Accept both TZ# and OP# so old references keep working
      wp_regex = /(?:TZ|OP)#(\d+)|http(?:s?):\/\/#{host_name}\/(?:\S+?\/)*(?:work_packages|wp)\/([0-9]+)/

      String(text)
        .scan(wp_regex)
        .map { |first, second| (first || second).to_i }
        .select(&:positive?)
        .uniq
    end

    Rails.logger.info "[TZ] GitHub PR prefix changed: TZ#<number> (OP# also accepted)"
  rescue => e
    Rails.logger.error "[TZ] Failed to patch WP prefix: #{e.message}"
  end
end
