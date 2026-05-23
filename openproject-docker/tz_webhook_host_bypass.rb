# frozen_string_literal: true

# Tamil Zorous: Allow webhook requests from external tunnels / GitHub.
# The production.rb host_authorization exclude list only allows
# /health_check and /sys.  This initializer patches the exclude proc
# to also skip host checking for /webhooks/ (used by GitHub integration).

Rails.application.config.after_initialize do
  ha = Rails.application.config.host_authorization
  next unless ha.is_a?(Hash)

  original_exclude = ha[:exclude]

  ha[:exclude] = ->(request) do
    request.path.start_with?("/webhooks") ||
      (original_exclude.respond_to?(:call) && original_exclude.call(request))
  end
end
