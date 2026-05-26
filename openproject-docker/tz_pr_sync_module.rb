# frozen_string_literal: true

# Tamil Zorous: GitHub PR Sync Module
# Separated into its own file to avoid Puma preload_app! caching issues.

require "net/http"
require "json"
require "uri"

module TzGithubPrSync
  TZ_SYNC_VERSION = "2026-05-26-v6"

  def self.sync_repo(owner, repo, token)
    synced = 0
    linked = 0
    prs = fetch_pull_requests(owner, repo, token, "all")
    prs.each do |pr_data|
      begin
        result = sync_single_pr(owner, repo, token, pr_data)
        synced += 1
        linked += result[:linked_count]
      rescue => e
        Rails.logger.warn "[TZ] Could not sync PR ##{pr_data['number']}: #{e.message}"
      end
    end
    { synced: synced, linked: linked, error: nil }
  rescue => e
    { synced: synced, linked: linked, error: e.message }
  end

  def self.fetch_pull_requests(owner, repo, token, state, per_page: 50)
    uri = URI("https://api.github.com/repos/#{owner}/#{repo}/pulls?state=#{state}&per_page=#{per_page}&sort=updated&direction=desc")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 20
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Authorization"] = "token #{token}"
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "OpenProject-TZ"
    response = http.request(request)
    if response.code.to_i == 200
      JSON.parse(response.body)
    else
      Rails.logger.warn "[TZ] GitHub API returned #{response.code} for #{owner}/#{repo} PRs (#{state})"
      []
    end
  end

  def self.fetch_pr_detail(owner, repo, token, pr_number)
    uri = URI("https://api.github.com/repos/#{owner}/#{repo}/pulls/#{pr_number}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Authorization"] = "token #{token}"
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "OpenProject-TZ"
    response = http.request(request)
    return nil unless response.code.to_i == 200
    JSON.parse(response.body)
  end

  def self.sync_single_pr(owner, repo, token, pr_data)
    full_name = "#{owner}/#{repo}"

    text = "#{pr_data['title']} #{pr_data['body']}"
    host_name = (Regexp.escape(Setting.host_name) rescue "localhost")
    wp_regex = /(?:TZ|OP)#(\d+)|http(?:s?):\/\/#{host_name}\/(?:\S+?\/)*(?:work_packages|wp)\/([0-9]+)/
    wp_ids = text.to_s.scan(wp_regex).map { |a, b| (a || b).to_i }.select(&:positive?).uniq

    work_packages = wp_ids.any? ? WorkPackage.where(id: wp_ids).to_a : []

    github_user_data = pr_data["user"] ? {
      "id" => pr_data["user"]["id"],
      "login" => pr_data["user"]["login"],
      "html_url" => pr_data["user"]["html_url"],
      "avatar_url" => pr_data["user"]["avatar_url"]
    } : nil

    merged_by_data = pr_data["merged_by"] ? {
      "id" => pr_data["merged_by"]["id"],
      "login" => pr_data["merged_by"]["login"],
      "html_url" => pr_data["merged_by"]["html_url"],
      "avatar_url" => pr_data["merged_by"]["avatar_url"]
    } : nil

    mergeable_status = nil
    if wp_ids.any?
      detail = fetch_pr_detail(owner, repo, token, pr_data["number"])
      if detail
        pr_data = detail
        mergeable_status = detail["mergeable"]
        merged_by_data = pr_data["merged_by"] ? {
          "id" => pr_data["merged_by"]["id"],
          "login" => pr_data["merged_by"]["login"],
          "html_url" => pr_data["merged_by"]["html_url"],
          "avatar_url" => pr_data["merged_by"]["avatar_url"]
        } : nil
      end
    end

    is_merged = pr_data["merged"] || pr_data["merged_at"].present?

    existing_pr = GithubPullRequest.find_by(github_id: pr_data["id"])
    old_state = existing_pr&.state
    old_merged = existing_pr&.merged
    old_labels = existing_pr&.labels&.map { |l| l[:name] || l["name"] } || []

    labels = Array(pr_data["labels"]).map { |l| { "name" => l["name"] || "", "color" => l["color"] || "000000" } }
    labels.reject! { |l| l["name"].start_with?("TZ:") }

    if pr_data["state"] == "open" && mergeable_status == false
      labels << { "name" => "TZ: Conflicts", "color" => "d73a49" }
    end

    reopener = nil
    if existing_pr && old_state == "closed" && pr_data["state"] == "open" && !is_merged
      reopener = fetch_pr_reopener(owner, repo, token, pr_data["number"])
      labels << { "name" => "TZ: Reopened by @#{reopener}", "color" => "e3b341" } if reopener
    end

    if wp_ids.any?
      comments_data = fetch_pr_comments(owner, repo, token, pr_data["number"])
      if comments_data.is_a?(Array) && comments_data.any?
        comments_data.each do |c|
          user_login = c.dig("user", "login") || "unknown"
          comment_body = c["body"].to_s.gsub(/\s+/, " ").strip
          comment_body = comment_body[0..100] + "..." if comment_body.length > 100
          comment_url = c["html_url"].to_s
          is_reply = c["in_reply_to_id"].present?
          is_review = c["_tz_is_review"] == true
          comment_type = is_reply ? "reply" : (is_review ? "review" : "")
          file_path = (is_review || is_reply) ? (c["path"].to_s) : ""
          comment_id = c["id"].to_s
          reply_to_id = c["in_reply_to_id"].to_s
          label_name = "TZ: @#{user_login}: #{comment_body}|||#{comment_url}|||#{comment_type}|||#{file_path}|||#{comment_id}|||#{reply_to_id}"
          labels << { "name" => label_name, "color" => "0075ca" }
        end
      end
    end

    payload = {
      "id" => pr_data["id"],
      "number" => pr_data["number"],
      "html_url" => pr_data["html_url"],
      "updated_at" => pr_data["updated_at"],
      "state" => pr_data["state"],
      "title" => pr_data["title"],
      "body" => pr_data["body"].presence || "-",
      "draft" => pr_data["draft"] || false,
      "merged" => is_merged,
      "merged_at" => pr_data["merged_at"],
      "merge_commit_sha" => pr_data["merge_commit_sha"],
      "merged_by" => merged_by_data,
      "user" => github_user_data,
      "comments" => pr_data["comments"] || 0,
      "review_comments" => pr_data["review_comments"] || 0,
      "additions" => pr_data["additions"] || 0,
      "deletions" => pr_data["deletions"] || 0,
      "changed_files" => pr_data["changed_files"] || 0,
      "labels" => labels,
      "base" => {
        "repo" => {
          "full_name" => full_name,
          "html_url" => "https://github.com/#{full_name}"
        }
      }
    }

    pr = OpenProject::GithubIntegration::Services::UpsertPullRequest.new.call(payload, work_packages: work_packages)

    if wp_ids.any?
      is_new = existing_pr.nil?
      state_changed = old_state != pr_data["state"]
      merged_changed = old_merged != is_merged
      is_reopened = old_state == "closed" && pr_data["state"] == "open" && !is_merged
      has_conflicts = labels.any? { |l| l["name"] == "TZ: Conflicts" }
      had_conflicts = old_labels.include?("TZ: Conflicts")
      new_conflicts = has_conflicts && !had_conflicts

      comment_labels_raw = labels.select { |l| l["name"].to_s.start_with?("TZ: @") }
      parsed_comments = comment_labels_raw.map do |l|
        parts = l["name"].sub(/^TZ:\s*/, "").split("|||")
        text = parts[0] || ""
        comment_type = parts[2] || ""
        file_path = parts[3] || ""
        comment_id = parts[4] || ""
        reply_to_id = parts[5] || ""
        file_basename = file_path.present? && file_path.include?("/") ? file_path.split("/").last : file_path
        display = (comment_type == "review" || comment_type == "reply") && file_basename.present? ? "#{text} (#{file_basename})" : text
        { text: display, type: comment_type, id: comment_id, reply_to: reply_to_id }
      end
      # Group: parents first, then their replies indented
      parents = parsed_comments.select { |c| c[:type] != "reply" }
      replies_by_parent = parsed_comments.select { |c| c[:type] == "reply" && c[:reply_to].present? }.group_by { |c| c[:reply_to] }
      orphan_replies = parsed_comments.select { |c| c[:type] == "reply" && c[:reply_to].blank? }
      comment_texts = []
      parents.each do |p|
        comment_texts << p[:text]
        (replies_by_parent.delete(p[:id]) || []).each { |r| comment_texts << "\u{00A0}\u{00A0}\u{00A0}\u{21B3} #{r[:text]}" }
      end
      replies_by_parent.values.flatten.each { |r| comment_texts << "\u{21B3} #{r[:text]}" }
      orphan_replies.each { |r| comment_texts << "\u{21B3} #{r[:text]}" }

      old_comment_labels = old_labels.select { |l| l.to_s.start_with?("TZ: @") }.map { |l| l.split("|||").first }
      new_comment_labels = comment_labels_raw.map { |l| l["name"].split("|||").first }
      has_new_comments = (new_comment_labels - old_comment_labels).any?

      if is_new || state_changed || merged_changed || new_conflicts || has_new_comments
        notify_teams_pr_sync(
          pr_data: pr_data, full_name: full_name, wp_ids: wp_ids,
          is_merged: is_merged, has_conflicts: has_conflicts,
          comment_texts: comment_texts, is_new: is_new,
          is_reopened: is_reopened, reopener: reopener,
          has_new_comments: has_new_comments
        )
      end
    end

    { linked_count: work_packages.size, pr: pr }
  end

  def self.notify_teams_pr_sync(pr_data:, full_name:, wp_ids:, is_merged:, has_conflicts:, comment_texts:, is_new:, is_reopened: false, reopener: nil, has_new_comments: false)
    host = Setting.host_name rescue "localhost:8080"
    protocol = Setting.protocol rescue "http"

    pr_author = pr_data.dig("user", "login") || "Someone"
    pr_number = pr_data["number"]
    pr_title = pr_data["title"] || "Unknown PR"
    pr_url = pr_data["html_url"] || ""

    if is_merged
      status, emoji, color = "Merged", "\u{1F7E3}", "Accent"
    elsif is_reopened
      status, emoji, color = "Reopened", "\u{1F7E0}", "Warning"
    elsif pr_data["state"] == "closed"
      status, emoji, color = "Closed", "\u{1F534}", "Attention"
    else
      status, emoji, color = "Open", "\u{1F7E2}", "Good"
    end

    action_actor = pr_author
    action_text = if is_new
                    "raised"
                  elsif is_reopened
                    action_actor = reopener || pr_author
                    "reopened"
                  elsif is_merged
                    "merged"
                  elsif pr_data["state"] == "closed"
                    "closed"
                  elsif has_new_comments
                    "commented on"
                  else
                    "updated"
                  end

    wp_links = wp_ids.map { |id| "[TZ##{id}](#{protocol}://#{host}/work_packages/#{id})" }.join(", ")

    facts = [
      { "title" => "Repository", "value" => full_name },
      { "title" => "Author", "value" => "**#{pr_author}**" },
      { "title" => "Status", "value" => "**#{status}**" },
      { "title" => "Work Packages", "value" => wp_links }
    ]
    facts << { "title" => "\u{26A0} Conflicts", "value" => "**This PR has merge conflicts**" } if has_conflicts

    body_items = [
      { "type" => "TextBlock", "text" => "#{emoji} **#{action_actor}** #{action_text} PR for #{wp_links}", "weight" => "Bolder", "size" => "Medium", "color" => color, "wrap" => true },
      { "type" => "TextBlock", "text" => "**##{pr_number}** #{pr_title}", "wrap" => true },
      { "type" => "FactSet", "facts" => facts }
    ]
    body_items << { "type" => "TextBlock", "text" => "\u{26A0}\u{FE0F} **This PR has merge conflicts!**", "color" => "Attention", "weight" => "Bolder", "wrap" => true } if has_conflicts

    if comment_texts.any?
      body_items << { "type" => "TextBlock", "text" => "\u{1F4AC} **Latest Comments:**", "weight" => "Bolder", "size" => "Small", "wrap" => true }
      comment_texts.each do |ct|
        body_items << { "type" => "TextBlock", "text" => ct, "wrap" => true, "size" => "Small", "isSubtle" => true }
      end
    end

    card = {
      "type" => "message",
      "attachments" => [{
        "contentType" => "application/vnd.microsoft.card.adaptive",
        "contentUrl" => nil,
        "content" => {
          "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
          "type" => "AdaptiveCard", "version" => "1.4",
          "body" => body_items,
          "actions" => [{ "type" => "Action.OpenUrl", "title" => "View PR \u{2192}", "url" => pr_url }]
        }
      }]
    }

    Webhooks::Webhook.where(enabled: true).each do |wh|
      url = wh.url.to_s
      is_teams = url.include?("webhook.office.com") || url.include?("logic.azure.com") ||
                 url.include?("webhook.office365.com") || url.include?("powerplatform.com") ||
                 url.include?("powerautomate")
      next unless is_teams
      begin
        response = OpenProject::SsrfProtection.post(url, headers: { "Content-Type": "application/json" }, body: card.to_json)
        Rails.logger.info "[TZ Teams] PR sync notification ##{pr_number} (#{status}) sent -> #{response&.code}"
      rescue => e
        Rails.logger.error "[TZ Teams] Failed: #{e.message}"
      end
    end
  rescue => e
    Rails.logger.error "[TZ Teams] PR sync notification error: #{e.message}"
  end

  def self.fetch_pr_reopener(owner, repo, token, pr_number)
    uri = URI("https://api.github.com/repos/#{owner}/#{repo}/issues/#{pr_number}/events?per_page=10")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Authorization"] = "token #{token}"
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "OpenProject-TZ"
    response = http.request(request)
    return nil unless response.code.to_i == 200
    events = JSON.parse(response.body)
    reopened_event = events.reverse.find { |e| e["event"] == "reopened" }
    reopened_event&.dig("actor", "login")
  rescue => e
    Rails.logger.warn "[TZ] Failed to fetch reopener for PR ##{pr_number}: #{e.message}"
    nil
  end

  def self.fetch_pr_comments(owner, repo, token, pr_number)
    issue_comments = []
    review_comments = []

    begin
      uri1 = URI("https://api.github.com/repos/#{owner}/#{repo}/issues/#{pr_number}/comments?per_page=100&sort=updated&direction=desc")
      http1 = Net::HTTP.new(uri1.host, uri1.port)
      http1.use_ssl = true
      http1.open_timeout = 10
      http1.read_timeout = 15
      req1 = Net::HTTP::Get.new(uri1.request_uri)
      req1["Authorization"] = "token #{token}"
      req1["Accept"] = "application/vnd.github+json"
      req1["User-Agent"] = "OpenProject-TZ"
      res1 = http1.request(req1)
      issue_comments = JSON.parse(res1.body) if res1.code.to_i == 200
    rescue => e
      Rails.logger.warn "[TZ] Failed to fetch issue comments for PR ##{pr_number}: #{e.message}"
    end

    begin
      uri2 = URI("https://api.github.com/repos/#{owner}/#{repo}/pulls/#{pr_number}/comments?per_page=100&sort=updated&direction=desc")
      http2 = Net::HTTP.new(uri2.host, uri2.port)
      http2.use_ssl = true
      http2.open_timeout = 10
      http2.read_timeout = 15
      req2 = Net::HTTP::Get.new(uri2.request_uri)
      req2["Authorization"] = "token #{token}"
      req2["Accept"] = "application/vnd.github+json"
      req2["User-Agent"] = "OpenProject-TZ"
      res2 = http2.request(req2)
      review_comments = JSON.parse(res2.body) if res2.code.to_i == 200
    rescue => e
      Rails.logger.warn "[TZ] Failed to fetch review comments for PR ##{pr_number}: #{e.message}"
    end

    review_comments.each { |c| c["_tz_is_review"] = true }
    all_comments = (issue_comments + review_comments)
    # Sort by created_at ascending so parent comments come before their replies
    all_comments.sort_by { |c| c["created_at"] || c["updated_at"] || "" }
  rescue => e
    Rails.logger.warn "[TZ] Failed to fetch comments for PR ##{pr_number}: #{e.message}"
    []
  end

  def self.extract_token_from_context
    settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
    settings[:github_admin_token].present? ? TzGithubTokenStore.decrypt(settings[:github_admin_token]) : nil
  end
end
