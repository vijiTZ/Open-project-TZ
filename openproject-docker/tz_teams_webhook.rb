# frozen_string_literal: true

# Tamil Zorous: Microsoft Teams / Power Automate webhook integration
#
# Intercepts outgoing webhook requests and converts OpenProject's JSON
# payload to a Teams Adaptive Card when the target URL is Teams or
# Power Automate. Also handles GitHub PR notifications.

Rails.application.config.after_initialize do
  begin
    service = Webhooks::Outgoing::RequestWebhookService

    service.class_eval do
      alias_method :original_call!, :call!
    end

    service.define_method(:call!) do |body:, headers:|
      webhook_url = webhook&.url.to_s

      is_teams = webhook_url.include?("webhook.office.com") ||
                 webhook_url.include?("logic.azure.com") ||
                 webhook_url.include?("webhook.office365.com") ||
                 webhook_url.include?("powerplatform.com") ||
                 webhook_url.include?("powerautomate")

      if is_teams
        begin
          parsed = JSON.parse(body) rescue {}
          teams_card = TzTeamsFormatter.format_from_payload(event_name.to_s, parsed)

          if teams_card
            response = OpenProject::SsrfProtection.post(
              webhook_url,
              headers: { "Content-Type": "application/json" },
              body: teams_card.to_json
            )

            log!(
              body: teams_card.to_json,
              headers: { "Content-Type": "application/json" },
              response: response,
              exception: nil
            )

            Rails.logger.info "[TZ Teams] Sent: #{event_name} -> #{response&.code}"
            return
          end
        rescue => e
          Rails.logger.error "[TZ Teams] Error: #{e.message}"
        end
      end

      original_call!(body: body, headers: headers)
    end

    Rails.logger.info "[TZ] Teams webhook formatter loaded"

    # Subscribe to GitHub PR events and forward to Teams
    ::OpenProject::Notifications.subscribe("github.pull_request") do |payload|
      begin
        pr_payload = payload[:payload] || payload
        action = pr_payload["action"].to_s
        pr = pr_payload["pull_request"] || {}

        pr_title = pr["title"] || "Unknown PR"
        pr_number = pr["number"] || "?"
        pr_url = pr["html_url"] || ""
        pr_author = pr.dig("user", "login") || "Someone"
        pr_repo = pr.dig("base", "repo", "full_name") || pr.dig("head", "repo", "full_name") || ""
        pr_merged = pr["merged"] == true
        effective_action = (action == "closed" && pr_merged) ? "merged" : action

        # Extract work package IDs from PR body (TZ#123 or OP#123 patterns)
        pr_body = pr["body"].to_s
        host = Setting.host_name rescue "localhost:8080"
        wp_regex = /(?:TZ|OP)#(\d+)|https?:\/\/#{Regexp.escape(host)}\/(?:\S+?\/)*(?:work_packages|wp)\/(\d+)/i
        wp_ids = pr_body.scan(wp_regex).map { |first, second| (first || second).to_i }.select(&:positive?).uniq

        pr_data = {
          title: pr_title,
          number: pr_number,
          url: pr_url,
          action: effective_action,
          author: pr_author,
          repo: pr_repo,
          work_package_ids: wp_ids
        }

        teams_card = TzTeamsFormatter.format_github_pr(pr_data)

        # Send to all Teams-type webhooks
        Webhooks::Webhook.where(enabled: true).each do |wh|
          url = wh.url.to_s
          is_teams = url.include?("webhook.office.com") ||
                     url.include?("logic.azure.com") ||
                     url.include?("webhook.office365.com") ||
                     url.include?("powerplatform.com") ||
                     url.include?("powerautomate")
          next unless is_teams

          begin
            response = OpenProject::SsrfProtection.post(
              url,
              headers: { "Content-Type": "application/json" },
              body: teams_card.to_json
            )
            Rails.logger.info "[TZ Teams] GitHub PR #{effective_action} ##{pr_number} sent to Teams -> #{response&.code}"
          rescue => e
            Rails.logger.error "[TZ Teams] Failed to send GitHub PR to Teams: #{e.message}"
          end
        end
      rescue => e
        Rails.logger.error "[TZ Teams] GitHub PR notification error: #{e.message}"
      end
    end

    Rails.logger.info "[TZ] GitHub PR -> Teams notification subscriber loaded"
  rescue => e
    Rails.logger.error "[TZ] Failed to load Teams webhook: #{e.message}"
  end
end

# Formatter: rich Adaptive Cards for Teams / Power Automate
module TzTeamsFormatter
  def self.format_from_payload(event_name, data)
    action = event_name.split(":").last rescue "unknown"
    resource_type = event_name.split(":").first rescue "unknown"

    case resource_type
    when "work_package"
      format_work_package(action, data)
    when "work_package_comment"
      format_comment(action, data)
    when "project"
      format_project(action, data)
    when "attachment"
      format_attachment(action, data)
    when "time_entry"
      format_time_entry(action, data)
    else
      format_generic(event_name, data)
    end
  rescue => e
    Rails.logger.error "[TZ Teams] Format error: #{e.message}"
    nil
  end

  def self.format_work_package(action, data)
    wp = data["work_package"] || data
    actor = data["actor"] || {}

    subject = dig(wp, "_links", "subject", "title") ||
              dig(wp, "subject") ||
              dig(wp, "_embedded", "subject") || "Untitled"
    wp_id = dig(wp, "id") || "?"
    status = dig(wp, "_embedded", "status", "name") ||
             dig(wp, "_links", "status", "title") || ""
    priority = dig(wp, "_embedded", "priority", "name") ||
               dig(wp, "_links", "priority", "title") || ""
    assignee = dig(wp, "_embedded", "assignee", "name") ||
               dig(wp, "_links", "assignee", "title") || "Unassigned"
    project_name = dig(wp, "_embedded", "project", "name") ||
                   dig(wp, "_links", "project", "title") || ""
    author = dig(actor, "name") ||
             dig(wp, "_embedded", "author", "name") || "Someone"
    wp_type = dig(wp, "_embedded", "type", "name") ||
              dig(wp, "_links", "type", "title") || "Task"
    responsible = dig(wp, "_embedded", "responsible", "name") ||
                  dig(wp, "_links", "responsible", "title") || ""
    description_raw = dig(wp, "description", "raw") || ""

    host = Setting.host_name rescue "localhost:8080"
    protocol = Setting.protocol rescue "http"
    view_url = "#{protocol}://#{host}/work_packages/#{wp_id}"

    emoji = case action
            when "created" then "\u{1F195}"
            when "updated" then "\u{270F}\u{FE0F}"
            else "\u{1F4CB}"
            end

    color = case action
            when "created" then "Good"
            when "updated" then "Accent"
            else "Default"
            end

    title = "#{emoji} #{wp_type} #{action.capitalize}: #{subject}"

    facts = []
    facts << { "title" => "Project", "value" => project_name } if project_name.present?
    facts << { "title" => "Status", "value" => status } if status.present?
    facts << { "title" => "Priority", "value" => priority } if priority.present?
    facts << { "title" => "Assignee", "value" => "**#{assignee}**" }
    facts << { "title" => "Responsible", "value" => responsible } if responsible.present?
    facts << { "title" => "By", "value" => author }

    body_items = [
      { "type" => "TextBlock", "text" => title, "weight" => "Bolder", "size" => "Medium", "color" => color, "wrap" => true },
      { "type" => "TextBlock", "text" => "**##{wp_id}** - #{subject}", "wrap" => true },
      {
        "type" => "FactSet",
        "facts" => facts
      }
    ]

    if description_raw.present? && action == "created"
      desc_short = description_raw.truncate(200)
      body_items << { "type" => "TextBlock", "text" => desc_short, "wrap" => true, "size" => "Small", "isSubtle" => true }
    end

    adaptive_card(body_items, view_url)
  end

  def self.format_comment(action, data)
    wp = data["work_package"] || data["comment"] || data
    actor = data["actor"] || {}
    comment = data["comment"] || {}

    subject = dig(wp, "subject") || dig(wp, "_links", "subject", "title") || "Unknown"
    wp_id = dig(wp, "id") || "?"
    author = dig(actor, "name") || "Someone"
    comment_body = dig(comment, "body", "raw") || dig(comment, "rawBody") || ""

    host = Setting.host_name rescue "localhost:8080"
    protocol = Setting.protocol rescue "http"
    view_url = "#{protocol}://#{host}/work_packages/#{wp_id}/activity"

    body_items = [
      { "type" => "TextBlock", "text" => "\u{1F4AC} New Comment on ##{wp_id}", "weight" => "Bolder", "size" => "Medium", "color" => "Warning", "wrap" => true },
      { "type" => "TextBlock", "text" => "**#{subject}**", "wrap" => true },
      { "type" => "TextBlock", "text" => "**#{author}** commented:", "wrap" => true, "size" => "Small" },
      { "type" => "TextBlock", "text" => comment_body.truncate(300), "wrap" => true, "size" => "Small", "isSubtle" => true }
    ]

    adaptive_card(body_items, view_url)
  end

  def self.format_project(action, data)
    project = data["project"] || data
    name = dig(project, "name") || dig(project, "identifier") || "Unknown"
    host = Setting.host_name rescue "localhost:8080"
    protocol = Setting.protocol rescue "http"
    url = "#{protocol}://#{host}"

    body_items = [
      { "type" => "TextBlock", "text" => "\u{1F4C1} Project #{action.capitalize}", "weight" => "Bolder", "size" => "Medium" },
      { "type" => "TextBlock", "text" => "**#{name}**", "wrap" => true }
    ]

    adaptive_card(body_items, url)
  end

  def self.format_attachment(action, data)
    body_items = [
      { "type" => "TextBlock", "text" => "\u{1F4CE} Attachment #{action.capitalize}", "weight" => "Bolder", "size" => "Medium" }
    ]
    adaptive_card(body_items, nil)
  end

  def self.format_time_entry(action, data)
    body_items = [
      { "type" => "TextBlock", "text" => "\u{23F1} Time Entry #{action.capitalize}", "weight" => "Bolder", "size" => "Medium" }
    ]
    adaptive_card(body_items, nil)
  end

  def self.format_generic(event_name, data)
    body_items = [
      { "type" => "TextBlock", "text" => "\u{1F4CB} #{event_name}", "weight" => "Bolder", "size" => "Medium" }
    ]
    adaptive_card(body_items, nil)
  end

  # Build a GitHub PR notification card
  def self.format_github_pr(pr_data)
    pr_title = pr_data[:title] || "Unknown PR"
    pr_number = pr_data[:number] || "?"
    pr_url = pr_data[:url] || ""
    pr_action = pr_data[:action] || "opened"
    pr_author = pr_data[:author] || "Someone"
    pr_repo = pr_data[:repo] || ""
    wp_ids = pr_data[:work_package_ids] || []

    host = Setting.host_name rescue "localhost:8080"
    protocol = Setting.protocol rescue "http"

    emoji = case pr_action
            when "opened" then "\u{1F7E2}"
            when "closed" then "\u{1F534}"
            when "merged" then "\u{1F7E3}"
            when "synchronize", "updated" then "\u{1F504}"
            else "\u{1F517}"
            end

    color = case pr_action
            when "opened" then "Good"
            when "closed" then "Attention"
            when "merged" then "Accent"
            else "Default"
            end

    facts = [
      { "title" => "Repository", "value" => pr_repo },
      { "title" => "Author", "value" => "**#{pr_author}**" },
      { "title" => "Action", "value" => pr_action.capitalize }
    ]

    if wp_ids.any?
      wp_links = wp_ids.map { |id| "[TZ##{id}](#{protocol}://#{host}/work_packages/#{id})" }.join(", ")
      facts << { "title" => "Work Packages", "value" => wp_links }
    end

    body_items = [
      { "type" => "TextBlock", "text" => "#{emoji} Pull Request #{pr_action.capitalize}", "weight" => "Bolder", "size" => "Medium", "color" => color, "wrap" => true },
      { "type" => "TextBlock", "text" => "**##{pr_number}** #{pr_title}", "wrap" => true },
      { "type" => "FactSet", "facts" => facts }
    ]

    adaptive_card(body_items, pr_url)
  end

  private_class_method def self.adaptive_card(body_items, action_url)
    card = {
      "type" => "message",
      "attachments" => [
        {
          "contentType" => "application/vnd.microsoft.card.adaptive",
          "contentUrl" => nil,
          "content" => {
            "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
            "type" => "AdaptiveCard",
            "version" => "1.4",
            "body" => body_items
          }
        }
      ]
    }

    if action_url.present?
      card["attachments"][0]["content"]["actions"] = [
        { "type" => "Action.OpenUrl", "title" => "View in OpenProject \u{2192}", "url" => action_url }
      ]
    end

    card
  end

  private_class_method def self.dig(hash, *keys)
    return nil unless hash.is_a?(Hash)
    result = hash
    keys.each do |key|
      break unless result.is_a?(Hash)
      result = result[key] || result[key.to_s] || result[key.to_sym]
    end
    result unless result.is_a?(Hash) && keys.last != keys.last
  rescue
    nil
  end
end
