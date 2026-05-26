# frozen_string_literal: true

# Tamil Zorous: GitHub PR Sync
#
# Fetches pull requests from connected GitHub repos via the GitHub API
# and creates/updates GithubPullRequest records in the database.
# This is needed because GitHub webhooks cannot reach localhost,
# so PRs (open, merged, closed) won't appear unless we poll for them.
#
# Adds a "Sync PRs" action to the GitHub admin settings page.
# Admin clicks "Sync Now" → system fetches PRs from all connected repos
# → matches TZ#<id> or OP#<id> references → links to work packages.

require "net/http"
require "json"
require "uri"

Rails.application.config.after_initialize do
  begin
    GithubIntegration::Admin::SettingsController.class_eval do
      # Add sync action to the existing tz_handle_repo_actions
      # We monkey-patch the method to add "sync_repos" case
      alias_method :tz_handle_repo_actions_original, :tz_handle_repo_actions

      private

      def tz_handle_repo_actions
        if params[:tz_action].to_s == "sync_repos"
          tz_sync_repos
        else
          tz_handle_repo_actions_original
        end
      end

      def tz_sync_repos
        settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
        repos = Array(settings[:connected_repos])
        token = nil

        # Get token: from form field or saved token
        token = params[:github_token].to_s.strip if params[:github_token].present?
        if token.blank? && settings[:github_admin_token].present?
          token = TzGithubTokenStore.decrypt(settings[:github_admin_token])
        end

        if token.blank?
          flash[:error] = "GitHub token is required to sync PRs."
          redirect_to "/github_integration/admin/settings" and return
        end

        if repos.empty?
          flash[:warning] = "No repositories connected. Add a repository first."
          redirect_to "/github_integration/admin/settings" and return
        end

        total_synced = 0
        total_linked = 0
        errors = []

        repos.each do |repo_config|
          full_name = repo_config["full_name"]
          owner, repo = full_name.split("/", 2)

          begin
            result = TzGithubPrSync.sync_repo(owner, repo, token)
            total_synced += result[:synced]
            total_linked += result[:linked]
            errors << "#{full_name}: #{result[:error]}" if result[:error]
          rescue => e
            errors << "#{full_name}: #{e.message}"
            Rails.logger.error "[TZ] Sync failed for #{full_name}: #{e.message}"
          end
        end

        if errors.any?
          flash[:warning] = "Synced #{total_synced} PRs (#{total_linked} linked to tasks). Errors: #{errors.join('; ')}"
        else
          flash[:notice] = "Synced #{total_synced} PRs from #{repos.size} repo(s). #{total_linked} linked to tasks."
        end

        redirect_to "/github_integration/admin/settings"
      end
    end

    # --- Auto-sync: run every 5 minutes in the background ---
    # Only start the thread in the web/puma process (not worker/cron)
    if defined?(Puma) || $PROGRAM_NAME.include?("puma") || $PROGRAM_NAME.include?("rails")
      Thread.new do
        # Wait 90s after boot for Puma workers to be ready
        sleep 90

        loop do
          begin
            ActiveRecord::Base.connection_pool.with_connection do
              settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
              repos = Array(settings[:connected_repos])
              token = nil

              if settings[:github_admin_token].present?
                token = TzGithubTokenStore.decrypt(settings[:github_admin_token])
              end

              if token.present? && repos.any?
                total = 0
                repos.each do |repo_config|
                  owner, repo = repo_config["full_name"].split("/", 2)
                  result = TzGithubPrSync.sync_repo(owner, repo, token)
                  total += result[:synced]
                rescue => e
                  Rails.logger.warn "[TZ] Auto-sync failed for #{repo_config['full_name']}: #{e.message}"
                end
                Rails.logger.info "[TZ] Auto-sync complete: #{total} PRs from #{repos.size} repo(s)"
              end
            end
          rescue => e
            Rails.logger.warn "[TZ] Auto-sync error: #{e.message}"
          end

          sleep 60 # 1 minute
        end
      end
      Rails.logger.info "[TZ] GitHub PR auto-sync started (every 1 min)"
    end

    Rails.logger.info "[TZ] GitHub PR sync loaded"
  rescue => e
    Rails.logger.error "[TZ] Failed to load GitHub PR sync: #{e.message}"
  end
end

# --- GitHub PR Sync helper ---
module TzGithubPrSync
  # Fetches PRs from a GitHub repo and upserts them into OpenProject.
  # Returns { synced: N, linked: N, error: nil|string }
  def self.sync_repo(owner, repo, token)
    synced = 0
    linked = 0

    # Fetch all PRs (open + closed + merged, last 100)
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

  # Fetch PRs from GitHub API
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

  # Fetch full PR details (the list endpoint doesn't include merged_by, additions, etc.)
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

  # Sync a single PR into OpenProject
  def self.sync_single_pr(owner, repo, token, pr_data)
    full_name = "#{owner}/#{repo}"

    # Extract WP IDs from title + body (TZ# or OP#)
    text = "#{pr_data['title']} #{pr_data['body']}"
    host_name = (Regexp.escape(Setting.host_name) rescue "localhost")
    wp_regex = /(?:TZ|OP)#(\d+)|http(?:s?):\/\/#{host_name}\/(?:\S+?\/)*(?:work_packages|wp)\/([0-9]+)/
    wp_ids = text.to_s.scan(wp_regex).map { |a, b| (a || b).to_i }.select(&:positive?).uniq

    work_packages = wp_ids.any? ? WorkPackage.where(id: wp_ids).to_a : []

    # Build a payload compatible with UpsertPullRequest service
    # The service expects the GitHub webhook PR payload format
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

    # The list endpoint doesn't return merged, additions, deletions, changed_files, merged_by.
    # Always fetch full detail for PRs that reference our work packages.
    mergeable_status = nil
    if wp_ids.any?
      detail = fetch_pr_detail(owner, repo, token, pr_data["number"])
      if detail
        pr_data = detail
        mergeable_status = detail["mergeable"]
        # Re-extract merged_by from detail
        merged_by_data = pr_data["merged_by"] ? {
          "id" => pr_data["merged_by"]["id"],
          "login" => pr_data["merged_by"]["login"],
          "html_url" => pr_data["merged_by"]["html_url"],
          "avatar_url" => pr_data["merged_by"]["avatar_url"]
        } : nil
      end
    end

    # Infer merged from merged_at if the explicit field isn't set
    # (the list endpoint returns merged_at but not merged boolean)
    is_merged = pr_data["merged"] || pr_data["merged_at"].present?

    # Check existing PR state BEFORE upsert to detect changes
    existing_pr = GithubPullRequest.find_by(github_id: pr_data["id"])
    old_state = existing_pr&.state
    old_merged = existing_pr&.merged
    old_labels = existing_pr&.labels&.map { |l| l[:name] || l["name"] } || []

    # Build labels: keep original GitHub labels + add TZ status labels
    labels = Array(pr_data["labels"]).map { |l| { "name" => l["name"] || "", "color" => l["color"] || "000000" } }

    # Remove old TZ status labels before re-adding
    labels.reject! { |l| l["name"].start_with?("TZ:") }

    # Add conflict label if mergeable is explicitly false (open PRs only)
    if pr_data["state"] == "open" && mergeable_status == false
      labels << { "name" => "TZ: Conflicts", "color" => "d73a49" }
    end

    # Detect reopened PRs and find who reopened
    reopener = nil
    if existing_pr && old_state == "closed" && pr_data["state"] == "open" && !is_merged
      reopener = fetch_pr_reopener(owner, repo, token, pr_data["number"])
      labels << { "name" => "TZ: Reopened by @#{reopener}", "color" => "e3b341" } if reopener
    end

    # Fetch latest PR comments for WP-linked PRs
    if wp_ids.any?
      comments_data = fetch_pr_comments(owner, repo, token, pr_data["number"])
      if comments_data.is_a?(Array) && comments_data.any?
        comments_data.first(3).each_with_index do |c, i|
          user_login = c.dig("user", "login") || "unknown"
          comment_body = c["body"].to_s.gsub(/\s+/, " ").strip
          comment_body = comment_body[0..120] + "..." if comment_body.length > 120
          labels << { "name" => "TZ: @#{user_login}: #{comment_body}", "color" => "0075ca" }
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

    # Determine what changed and notify Teams
    if wp_ids.any?
      is_new = existing_pr.nil?
      state_changed = old_state != pr_data["state"]
      merged_changed = old_merged != is_merged
      is_reopened = old_state == "closed" && pr_data["state"] == "open" && !is_merged
      has_conflicts = labels.any? { |l| l["name"] == "TZ: Conflicts" }
      had_conflicts = old_labels.include?("TZ: Conflicts")
      new_conflicts = has_conflicts && !had_conflicts

      # Collect latest comments for notification
      comment_texts = labels.select { |l| l["name"].to_s.start_with?("TZ: @") }.map { |l| l["name"].sub(/^TZ:\s*/, "") }

      if is_new || state_changed || merged_changed || new_conflicts
        notify_teams_pr_sync(
          pr_data: pr_data,
          full_name: full_name,
          wp_ids: wp_ids,
          is_merged: is_merged,
          has_conflicts: has_conflicts,
          comment_texts: comment_texts,
          is_new: is_new,
          is_reopened: is_reopened,
          reopener: reopener
        )
      end
    end

    { linked_count: work_packages.size, pr: pr }
  end

  # Send a Teams notification about a PR sync event
  def self.notify_teams_pr_sync(pr_data:, full_name:, wp_ids:, is_merged:, has_conflicts:, comment_texts:, is_new:, is_reopened: false, reopener: nil)
    host = Setting.host_name rescue "localhost:8080"
    protocol = Setting.protocol rescue "http"

    pr_author = pr_data.dig("user", "login") || "Someone"
    pr_number = pr_data["number"]
    pr_title = pr_data["title"] || "Unknown PR"
    pr_url = pr_data["html_url"] || ""

    # Determine effective status
    if is_merged
      status = "Merged"
      emoji = "\u{1F7E3}"
      color = "Accent"
    elsif is_reopened
      status = "Reopened"
      emoji = "\u{1F7E0}"
      color = "Warning"
    elsif pr_data["state"] == "closed"
      status = "Closed"
      emoji = "\u{1F534}"
      color = "Attention"
    else
      status = "Open"
      emoji = "\u{1F7E2}"
      color = "Good"
    end

    # For reopened, show who reopened (may differ from original author)
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
                  else
                    "updated"
                  end

    # Build WP links
    wp_links = wp_ids.map { |id| "[TZ##{id}](#{protocol}://#{host}/work_packages/#{id})" }.join(", ")

    facts = [
      { "title" => "Repository", "value" => full_name },
      { "title" => "Author", "value" => "**#{pr_author}**" },
      { "title" => "Status", "value" => "**#{status}**" },
      { "title" => "Work Packages", "value" => wp_links }
    ]

    if has_conflicts
      facts << { "title" => "\u{26A0} Conflicts", "value" => "**This PR has merge conflicts**" }
    end

    body_items = [
      { "type" => "TextBlock", "text" => "#{emoji} **#{action_actor}** #{action_text} PR for #{wp_links}", "weight" => "Bolder", "size" => "Medium", "color" => color, "wrap" => true },
      { "type" => "TextBlock", "text" => "**##{pr_number}** #{pr_title}", "wrap" => true },
      { "type" => "FactSet", "facts" => facts }
    ]

    # Add conflict warning
    if has_conflicts
      body_items << { "type" => "TextBlock", "text" => "\u{26A0}\u{FE0F} **This PR has merge conflicts!**", "color" => "Attention", "weight" => "Bolder", "wrap" => true }
    end

    # Add latest comments
    if comment_texts.any?
      body_items << { "type" => "TextBlock", "text" => "\u{1F4AC} **Latest Comments:**", "weight" => "Bolder", "size" => "Small", "wrap" => true }
      comment_texts.each do |ct|
        body_items << { "type" => "TextBlock", "text" => ct, "wrap" => true, "size" => "Small", "isSubtle" => true }
      end
    end

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
            "body" => body_items,
            "actions" => [
              { "type" => "Action.OpenUrl", "title" => "View PR \u{2192}", "url" => pr_url }
            ]
          }
        }
      ]
    }

    # Send to all Teams webhooks
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
          body: card.to_json
        )
        Rails.logger.info "[TZ Teams] PR sync notification ##{pr_number} (#{status}) sent -> #{response&.code}"
      rescue => e
        Rails.logger.error "[TZ Teams] Failed to send PR sync notification: #{e.message}"
      end
    end
  rescue => e
    Rails.logger.error "[TZ Teams] PR sync notification error: #{e.message}"
  end

  # Fetch who reopened a PR (from GitHub Events API)
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
    # Find the latest "reopened" event
    reopened_event = events.reverse.find { |e| e["event"] == "reopened" }
    reopened_event&.dig("actor", "login")
  rescue => e
    Rails.logger.warn "[TZ] Failed to fetch reopener for PR ##{pr_number}: #{e.message}"
    nil
  end

  # Fetch latest comments on a PR (via issues API which includes PR comments)
  def self.fetch_pr_comments(owner, repo, token, pr_number)
    uri = URI("https://api.github.com/repos/#{owner}/#{repo}/issues/#{pr_number}/comments?per_page=5&sort=updated&direction=desc")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri.request_uri)
    request["Authorization"] = "token #{token}"
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "OpenProject-TZ"

    response = http.request(request)
    return [] unless response.code.to_i == 200

    JSON.parse(response.body)
  rescue => e
    Rails.logger.warn "[TZ] Failed to fetch comments for PR ##{pr_number}: #{e.message}"
    []
  end

  def self.extract_token_from_context
    # Fallback — get saved token from settings
    settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
    if settings[:github_admin_token].present?
      TzGithubTokenStore.decrypt(settings[:github_admin_token])
    else
      nil
    end
  end
end
