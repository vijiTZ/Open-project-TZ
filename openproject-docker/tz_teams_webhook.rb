# frozen_string_literal: true

# Tamil Zorous: Microsoft Teams webhook integration
#
# OpenProject's built-in webhook system sends JSON payloads in its own
# format. Microsoft Teams expects an Adaptive Card (or MessageCard) format.
#
# This initializer monkey-patches the outgoing webhook request service
# so that when the target URL is a Teams webhook (*.webhook.office.com
# or *.logic.azure.com), the payload is automatically converted to a
# Teams Adaptive Card before sending.
#
# Also adds a "Test Connection" endpoint so admins can verify webhook
# URLs work before relying on them.
#
# Setup (done by admin in UI):
#   1. Administration → API and Webhooks → Webhooks
#   2. Add new webhook → paste Teams Incoming Webhook URL
#   3. Select events: work_package:created, work_package:updated
#   4. Choose projects (all or specific)
#   5. Save — done, notifications flow to Teams automatically
#   6. Click "Test Connection" on the webhook detail page to verify
#
# No code changes needed to add/remove/change Teams channels.

Rails.application.config.after_initialize do
  service = Webhooks::Outgoing::RequestWebhookService

  # Save original method
  service.class_eval do
    alias_method :original_perform, :perform
  end

  service.define_method(:perform) do
    webhook_url = @webhook&.url.to_s

    # Detect Teams webhook URLs
    is_teams = webhook_url.include?("webhook.office.com") ||
               webhook_url.include?("logic.azure.com") ||
               webhook_url.include?("webhook.office365.com")

    if is_teams && @event_name && @payload
      begin
        teams_payload = TzTeamsFormatter.format(@event_name, @payload, @webhook)
        if teams_payload
          uri = URI.parse(webhook_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.open_timeout = 10
          http.read_timeout = 15

          request = Net::HTTP::Post.new(uri.request_uri)
          request["Content-Type"] = "application/json"
          request.body = teams_payload.to_json

          response = http.request(request)

          # Log the delivery
          Webhooks::Log.create!(
            webhook: @webhook,
            event_name: @event_name,
            url: webhook_url,
            request_headers: { "Content-Type" => "application/json" },
            request_body: teams_payload.to_json.truncate(10_000),
            response_code: response.code.to_i,
            response_headers: response.each_header.to_h,
            response_body: response.body.to_s.truncate(5_000)
          )

          Rails.logger.info "[TZ Teams] Sent notification to Teams: #{@event_name} → #{response.code}"
          return
        end
      rescue => e
        Rails.logger.error "[TZ Teams] Failed to send to Teams: #{e.message}"
      end
    end

    # Fall back to original for non-Teams webhooks
    original_perform
  end

  # --- Test Connection endpoint ---
  # POST /admin/settings/webhooks/:webhook_id/test_connection
  Webhooks::Outgoing::AdminController.class_eval do
    def test_connection
      webhook = ::Webhooks::Webhook.find(params[:webhook_id])
      webhook_url = webhook.url.to_s

      is_teams = webhook_url.include?("webhook.office.com") ||
                 webhook_url.include?("logic.azure.com") ||
                 webhook_url.include?("webhook.office365.com")

      host = Setting.host_name rescue "localhost:8080"
      protocol = Setting.protocol rescue "http"
      now = Time.now.strftime("%B %d, %Y at %H:%M")

      if is_teams
        # Send a Teams Adaptive Card test message
        test_payload = {
          type: "message",
          attachments: [
            {
              contentType: "application/vnd.microsoft.card.adaptive",
              contentUrl: nil,
              content: {
                "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                type: "AdaptiveCard",
                version: "1.4",
                body: [
                  { type: "TextBlock", text: "Test Connection Successful!", weight: "Bolder", size: "Medium", color: "Good" },
                  { type: "TextBlock", text: "This is a test message from **OpenProject** (Tamil Zorous).", wrap: true },
                  { type: "TextBlock", text: "Webhook: **#{webhook.name}**", size: "Small", isSubtle: true },
                  { type: "TextBlock", text: "Sent: #{now}", size: "Small", isSubtle: true }
                ],
                actions: [
                  { type: "Action.OpenUrl", title: "Open OpenProject", url: "#{protocol}://#{host}" }
                ]
              }
            }
          ]
        }
      else
        # Send a generic JSON test payload
        test_payload = {
          test: true,
          source: "OpenProject (Tamil Zorous)",
          webhook_name: webhook.name,
          timestamp: Time.now.iso8601,
          message: "Test connection from OpenProject webhook '#{webhook.name}'"
        }
      end

      begin
        uri = URI.parse(webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "OpenProject-TZ"
        request.body = test_payload.to_json

        response = http.request(request)

        # Log the test delivery
        Webhooks::Log.create!(
          webhook: webhook,
          event_name: "test_connection",
          url: webhook_url,
          request_headers: { "Content-Type" => "application/json" },
          request_body: test_payload.to_json.truncate(10_000),
          response_code: response.code.to_i,
          response_headers: response.each_header.to_h,
          response_body: response.body.to_s.truncate(5_000)
        )

        if response.code.to_i.between?(200, 299)
          flash[:notice] = "Test successful! #{is_teams ? 'Teams' : 'Webhook'} responded with #{response.code}. Check your #{is_teams ? 'Teams channel' : 'endpoint'} for the test message."
        else
          flash[:error] = "Test failed. Server responded with HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        flash[:error] = "Test failed: Connection timed out (#{e.message}). Check the URL."
      rescue => e
        flash[:error] = "Test failed: #{e.message}"
      end

      redirect_to admin_outgoing_webhook_path(webhook)
    end
  end

  # Add the test_connection route
  Rails.application.routes.draw do
    scope "admin" do
      scope :settings do
        post "webhooks/:webhook_id/test_connection",
             to: "webhooks/outgoing/admin#test_connection",
             as: "test_webhook_connection"
      end
    end
  end

  Rails.logger.info "[TZ] Teams webhook formatter loaded"
rescue => e
  Rails.logger.error "[TZ] Failed to load Teams webhook: #{e.message}"
end

# Formatter: converts OpenProject webhook payloads to Teams Adaptive Cards
module TzTeamsFormatter
  COLORS = {
    "created" => "Good",      # green
    "updated" => "Accent",    # blue
    "commented" => "Warning"  # yellow
  }.freeze

  def self.format(event_name, payload, webhook)
    action = event_name.to_s.split(":").last # "created", "updated", etc.

    case event_name.to_s
    when /work_package/
      format_work_package(action, payload)
    when /project/
      format_project(action, payload)
    when /attachment/
      format_attachment(action, payload)
    else
      format_generic(event_name, payload)
    end
  rescue => e
    Rails.logger.error "[TZ Teams] Format error: #{e.message}"
    nil
  end

  def self.format_work_package(action, payload)
    wp = payload.is_a?(Hash) ? payload : payload.to_h rescue {}

    # Extract work package data (handles both symbolized and string keys)
    wp_data = wp[:work_package] || wp["work_package"] || wp
    actor = wp[:actor] || wp["actor"] || {}

    subject = dig_value(wp_data, :subject, :_links, :subject) || "Unknown task"
    wp_id = dig_value(wp_data, :id) || "?"
    status = dig_value(wp_data, :_embedded, :status, :name) ||
             dig_value(wp_data, :status) || ""
    priority = dig_value(wp_data, :_embedded, :priority, :name) ||
               dig_value(wp_data, :priority) || ""
    assignee = dig_value(wp_data, :_embedded, :assignee, :name) ||
               dig_value(wp_data, :assignee) || "Unassigned"
    project_name = dig_value(wp_data, :_embedded, :project, :name) ||
                   dig_value(wp_data, :project) || ""
    author = dig_value(actor, :name) ||
             dig_value(wp_data, :_embedded, :author, :name) || "Someone"
    wp_url = dig_value(wp_data, :_links, :self, :href) || ""
    description = dig_value(wp_data, :description, :raw) || ""

    # Build the host URL for the link
    host = Setting.host_name rescue "localhost:8080"
    protocol = Setting.protocol rescue "http"
    view_url = "#{protocol}://#{host}/work_packages/#{wp_id}"

    title = case action
            when "created" then "New Task Created"
            when "updated" then "Task Updated"
            when "comment", "internal_comment" then "New Comment"
            else "Task #{action.capitalize}"
            end

    emoji = case action
            when "created" then "🆕"
            when "updated" then "✏️"
            when "comment", "internal_comment" then "💬"
            else "📋"
            end

    color = COLORS[action] || "Default"

    # Teams Adaptive Card format
    {
      type: "message",
      attachments: [
        {
          contentType: "application/vnd.microsoft.card.adaptive",
          contentUrl: nil,
          content: {
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            type: "AdaptiveCard",
            version: "1.4",
            body: [
              {
                type: "TextBlock",
                text: "#{emoji} #{title}",
                weight: "Bolder",
                size: "Medium",
                color: color
              },
              {
                type: "TextBlock",
                text: "**#{subject}** (##{wp_id})",
                wrap: true,
                size: "Default"
              },
              {
                type: "ColumnSet",
                columns: [
                  {
                    type: "Column",
                    width: "auto",
                    items: [
                      { type: "TextBlock", text: "**Project:**", size: "Small", isSubtle: true },
                      { type: "TextBlock", text: "**Status:**", size: "Small", isSubtle: true },
                      { type: "TextBlock", text: "**Priority:**", size: "Small", isSubtle: true },
                      { type: "TextBlock", text: "**Assignee:**", size: "Small", isSubtle: true },
                      { type: "TextBlock", text: "**By:**", size: "Small", isSubtle: true }
                    ]
                  },
                  {
                    type: "Column",
                    width: "stretch",
                    items: [
                      { type: "TextBlock", text: project_name.to_s, size: "Small" },
                      { type: "TextBlock", text: status.to_s, size: "Small" },
                      { type: "TextBlock", text: priority.to_s, size: "Small" },
                      { type: "TextBlock", text: assignee.to_s, size: "Small" },
                      { type: "TextBlock", text: author.to_s, size: "Small" }
                    ]
                  }
                ]
              }
            ],
            actions: [
              {
                type: "Action.OpenUrl",
                title: "View in OpenProject →",
                url: view_url
              }
            ]
          }
        }
      ]
    }
  end

  def self.format_project(action, payload)
    project = payload.is_a?(Hash) ? (payload[:project] || payload["project"] || payload) : {}
    name = dig_value(project, :name) || "Unknown project"

    {
      type: "message",
      attachments: [
        {
          contentType: "application/vnd.microsoft.card.adaptive",
          contentUrl: nil,
          content: {
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            type: "AdaptiveCard",
            version: "1.4",
            body: [
              { type: "TextBlock", text: "📁 Project #{action}", weight: "Bolder", size: "Medium" },
              { type: "TextBlock", text: "**#{name}**", wrap: true }
            ]
          }
        }
      ]
    }
  end

  def self.format_attachment(action, payload)
    {
      type: "message",
      attachments: [
        {
          contentType: "application/vnd.microsoft.card.adaptive",
          contentUrl: nil,
          content: {
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            type: "AdaptiveCard",
            version: "1.4",
            body: [
              { type: "TextBlock", text: "📎 Attachment #{action}", weight: "Bolder", size: "Medium" }
            ]
          }
        }
      ]
    }
  end

  def self.format_generic(event_name, payload)
    {
      type: "message",
      attachments: [
        {
          contentType: "application/vnd.microsoft.card.adaptive",
          contentUrl: nil,
          content: {
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            type: "AdaptiveCard",
            version: "1.4",
            body: [
              { type: "TextBlock", text: "📋 #{event_name}", weight: "Bolder", size: "Medium" }
            ]
          }
        }
      ]
    }
  end

  # Helper to dig into nested hashes with string or symbol keys
  def self.dig_value(hash, *keys)
    return nil unless hash.is_a?(Hash)

    result = hash
    keys.each do |key|
      break unless result.is_a?(Hash)
      result = result[key] || result[key.to_s]
    end
    result unless result.is_a?(Hash)
  rescue
    nil
  end
end
