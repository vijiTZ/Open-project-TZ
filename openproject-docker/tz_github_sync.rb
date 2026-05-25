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

          sleep 300 # 5 minutes
        end
      end
      Rails.logger.info "[TZ] GitHub PR auto-sync started (every 5 min)"
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
    if wp_ids.any?
      detail = fetch_pr_detail(owner, repo, token, pr_data["number"])
      if detail
        pr_data = detail
        # Re-extract merged_by from detail
        merged_by_data = pr_data["merged_by"] ? {
          "id" => pr_data["merged_by"]["id"],
          "login" => pr_data["merged_by"]["login"],
          "html_url" => pr_data["merged_by"]["html_url"],
          "avatar_url" => pr_data["merged_by"]["avatar_url"]
        } : nil
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
      "merged" => pr_data["merged"] || false,
      "merged_at" => pr_data["merged_at"],
      "merge_commit_sha" => pr_data["merge_commit_sha"],
      "merged_by" => merged_by_data,
      "user" => github_user_data,
      "comments" => pr_data["comments"] || 0,
      "review_comments" => pr_data["review_comments"] || 0,
      "additions" => pr_data["additions"] || 0,
      "deletions" => pr_data["deletions"] || 0,
      "changed_files" => pr_data["changed_files"] || 0,
      "labels" => Array(pr_data["labels"]).map { |l| { "name" => l["name"] || "", "color" => l["color"] || "000000" } },
      "base" => {
        "repo" => {
          "full_name" => full_name,
          "html_url" => "https://github.com/#{full_name}"
        }
      }
    }

    pr = OpenProject::GithubIntegration::Services::UpsertPullRequest.new.call(payload, work_packages: work_packages)

    { linked_count: work_packages.size, pr: pr }
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
