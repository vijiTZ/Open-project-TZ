# frozen_string_literal: true

# Tamil Zorous: GitHub Repository Manager
#
# Adds admin UI for connecting GitHub repos to OpenProject.
# The admin pastes a repo URL and GitHub token → the system
# automatically registers a webhook on that repo.
#
# Admin flow:
#   1. Go to Administration → GitHub → Settings
#   2. Scroll to "Connected Repositories"
#   3. Enter repo URL (e.g., https://github.com/org/repo)
#   4. Enter a GitHub Personal Access Token (with admin:repo_hook scope)
#   5. Optionally check "Save token" to store it encrypted for future use
#   6. Click "Connect Repository"
#   7. The webhook is auto-created on GitHub
#   8. Admin can remove repos with "Disconnect" (uses saved token automatically)
#
# Repo configs are stored in Setting.plugin_openproject_github_integration
# under the key "connected_repos" as a JSON array.
# The GitHub token (if saved) is stored encrypted under "github_admin_token".

require "net/http"
require "json"
require "uri"
require "openssl"
require "base64"

Rails.application.config.after_initialize do
  begin
  # --- Controller: intercept POST requests via before_action on update ---
  GithubIntegration::Admin::SettingsController.class_eval do
    before_action :tz_handle_repo_actions, only: [:update]

    # Override show to load connected repos
    alias_method :original_show, :show
    def show
      original_show
      settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
      @connected_repos = Array(settings[:connected_repos])
      @has_saved_token = settings[:github_admin_token].present?
    end

    private

    def tz_handle_repo_actions
      tz_action = params[:tz_action].to_s
      return unless tz_action.present?

      case tz_action
      when "connect_repo"
        tz_connect_repo
      when "disconnect_repo"
        tz_disconnect_repo
      when "clear_saved_token"
        tz_clear_saved_token
      end
    end

    def tz_connect_repo
      repo_url = params[:repo_url].to_s.strip
      token = params[:github_token].to_s.strip
      save_token = params[:save_token] == "1"

      # Use saved token if field is blank
      if token.blank?
        settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
        token = TzGithubTokenStore.decrypt(settings[:github_admin_token]) if settings[:github_admin_token].present?
      end

      if repo_url.blank? || token.blank?
        flash[:error] = "Repository URL and GitHub token are required."
        redirect_to "/github_integration/admin/settings" and return
      end

      settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access

      # Detect if this is an org URL (https://github.com/org-name) or repo URL (https://github.com/owner/repo)
      org_match = repo_url.match(%r{github\.com/([^/]+)/?$})
      repo_match = repo_url.match(%r{github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$})

      if repo_match
        # Individual repo connection
        owner, repo = repo_match[1], repo_match[2]
        tz_connect_single_repo(owner, repo, token, save_token, settings)
      elsif org_match
        # Organization connection — fetch all repos and connect them
        org_name = org_match[1]
        tz_connect_org(org_name, token, save_token, settings)
      else
        flash[:error] = "Invalid GitHub URL. Use https://github.com/org or https://github.com/owner/repo"
        redirect_to "/github_integration/admin/settings" and return
      end
    end

    def tz_connect_single_repo(owner, repo, token, save_token, settings)
      full_name = "#{owner}/#{repo}"

      # Build webhook URL
      webhook_secret = settings[:webhook_secret] || ""
      host = Setting.host_name
      protocol = (Setting.protocol rescue "https")

      api_user_id = settings[:github_user_id]
      api_user = api_user_id.present? ? User.find_by(id: api_user_id) : nil
      api_token = api_user&.api_tokens&.first&.plain_value

      if api_token.present?
        webhook_url = "#{protocol}://#{host}/webhooks/github?key=#{api_token}"
      else
        webhook_url = "#{protocol}://#{host}/webhooks/github"
      end

      begin
        result = TzGithubRepoManager.create_webhook(owner, repo, token, webhook_url, webhook_secret)

        if result[:success]
          repos = Array(settings[:connected_repos])
          repos.reject! { |r| r["full_name"] == full_name }
          repos << {
            "full_name" => full_name,
            "url" => "https://github.com/#{full_name}",
            "hook_id" => result[:hook_id],
            "connected_at" => Time.now.iso8601,
            "type" => "repo"
          }

          merged = settings.merge("connected_repos" => repos)
          merged["github_admin_token"] = TzGithubTokenStore.encrypt(token) if save_token

          Setting.plugin_openproject_github_integration = merged
          if result[:already_exists]
            flash[:notice] = "Connected #{full_name}! (Webhook already existed on GitHub)"
          else
            flash[:notice] = "Successfully connected #{full_name}! Webhook is active."
          end
          flash[:notice] += " Token saved securely." if save_token
        else
          flash[:error] = "Failed to connect: #{result[:error]}"
        end
      rescue => e
        flash[:error] = "Error connecting to GitHub: #{e.message}"
      end

      redirect_to "/github_integration/admin/settings"
    end

    def tz_connect_org(org_name, token, save_token, settings)
      begin
        org_repos = TzGithubRepoManager.fetch_org_repos(org_name, token)

        if org_repos.nil?
          flash[:error] = "Could not fetch repos for '#{org_name}'. Check the token has access to this org."
          redirect_to "/github_integration/admin/settings" and return
        end

        if org_repos.empty?
          flash[:warning] = "No repositories found under '#{org_name}'."
          redirect_to "/github_integration/admin/settings" and return
        end

        repos = Array(settings[:connected_repos])

        # Remove any previous org entry for this org
        repos.reject! { |r| r["type"] == "org" && r["org_name"] == org_name }
        # Remove individual repos from this org that were auto-added by a previous org connect
        repos.reject! { |r| r["org_name"] == org_name && r["type"] == "org_repo" }

        # Add the org entry (this is what the sync thread uses to expand repos)
        repos << {
          "full_name" => org_name,
          "url" => "https://github.com/#{org_name}",
          "type" => "org",
          "org_name" => org_name,
          "connected_at" => Time.now.iso8601,
          "repo_count" => org_repos.size
        }

        merged = settings.merge("connected_repos" => repos)
        merged["github_admin_token"] = TzGithubTokenStore.encrypt(token) if save_token

        Setting.plugin_openproject_github_integration = merged
        flash[:notice] = "Connected org '#{org_name}' — #{org_repos.size} repos will be synced automatically."
        flash[:notice] += " Token saved securely." if save_token
      rescue => e
        flash[:error] = "Error connecting org: #{e.message}"
      end

      redirect_to "/github_integration/admin/settings"
    end

    def tz_disconnect_repo
      full_name = params[:full_name].to_s.strip
      entry_type = params[:entry_type].to_s.strip
      token = params[:github_token].to_s.strip

      settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access

      if token.blank? && settings[:github_admin_token].present?
        token = TzGithubTokenStore.decrypt(settings[:github_admin_token])
      end

      repos = Array(settings[:connected_repos])

      if entry_type == "org"
        # Disconnect org — remove the org entry (existing PRs in DB stay)
        repos.reject! { |r| r["full_name"] == full_name && r["type"] == "org" }
        repos.reject! { |r| r["org_name"] == full_name && r["type"] == "org_repo" }
        flash[:notice] = "Disconnected org '#{full_name}'. Existing PRs remain visible but no new PRs will sync."
      else
        # Disconnect individual repo
        repo_config = repos.find { |r| r["full_name"] == full_name && r["type"] != "org" }

        if repo_config && token.present? && repo_config["hook_id"]
          owner, repo = full_name.split("/", 2)
          begin
            TzGithubRepoManager.delete_webhook(owner, repo, token, repo_config["hook_id"])
          rescue => e
            Rails.logger.warn "[TZ] Could not delete webhook from GitHub: #{e.message}"
          end
        end

        repos.reject! { |r| r["full_name"] == full_name && r["type"] != "org" }
        flash[:notice] = "Disconnected #{full_name}. Existing PRs remain visible but no new PRs will sync."
      end

      merged = settings.merge("connected_repos" => repos)
      Setting.plugin_openproject_github_integration = merged

      redirect_to "/github_integration/admin/settings"
    end

    def tz_clear_saved_token
      settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
      merged = settings.except(:github_admin_token, "github_admin_token")
      Setting.plugin_openproject_github_integration = merged
      flash[:notice] = "Saved GitHub token has been removed."
      redirect_to "/github_integration/admin/settings"
    end
  end

  Rails.logger.info "[TZ] GitHub repo manager loaded"
  rescue => e
    Rails.logger.error "[TZ] Failed to load GitHub repo manager: #{e.message}"
  end
end

# --- Encrypted token storage ---
# Uses AES-256-GCM with a key derived from Rails secret_key_base.
# The token is encrypted at rest in the database (Setting) and only
# decrypted in memory when needed for API calls.
module TzGithubTokenStore
  def self.encryption_key
    secret = Rails.application.secret_key_base.to_s
    OpenSSL::Digest::SHA256.digest(secret)
  end

  def self.encrypt(plaintext)
    return nil if plaintext.blank?
    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.encrypt
    iv = cipher.random_iv
    cipher.key = encryption_key
    cipher.iv = iv
    cipher.auth_data = "tz-github-token"
    encrypted = cipher.update(plaintext) + cipher.final
    tag = cipher.auth_tag
    Base64.strict_encode64(iv + tag + encrypted)
  rescue => e
    Rails.logger.error "[TZ] Token encryption failed: #{e.message}"
    nil
  end

  def self.decrypt(encoded)
    return nil if encoded.blank?
    raw = Base64.strict_decode64(encoded)
    iv = raw[0, 12]
    tag = raw[12, 16]
    ciphertext = raw[28..]
    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.decrypt
    cipher.key = encryption_key
    cipher.iv = iv
    cipher.auth_tag = tag
    cipher.auth_data = "tz-github-token"
    cipher.update(ciphertext) + cipher.final
  rescue => e
    Rails.logger.error "[TZ] Token decryption failed: #{e.message}"
    nil
  end
end

# --- GitHub API helper ---
module TzGithubRepoManager
  def self.create_webhook(owner, repo, token, webhook_url, secret)
    uri = URI("https://api.github.com/repos/#{owner}/#{repo}/hooks")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    body = {
      name: "web",
      active: true,
      events: ["pull_request", "issue_comment"],
      config: {
        url: webhook_url,
        content_type: "json",
        secret: secret,
        insecure_ssl: "0"
      }
    }

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Authorization"] = "token #{token}"
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "OpenProject-TZ"
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    response = http.request(request)

    if response.code.to_i == 201
      data = JSON.parse(response.body)
      { success: true, hook_id: data["id"] }
    elsif response.code.to_i == 422
      # Webhook already exists — treat as success
      { success: true, hook_id: nil, already_exists: true }
    else
      error_msg = (JSON.parse(response.body)["message"] rescue response.body.to_s.truncate(200))
      { success: false, error: "GitHub API returned #{response.code}: #{error_msg}" }
    end
  end

  # Fetch all repos for a GitHub org (paginated, up to 200)
  def self.fetch_org_repos(org_name, token)
    all_repos = []
    page = 1

    loop do
      uri = URI("https://api.github.com/orgs/#{org_name}/repos?per_page=100&page=#{page}&type=all")
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
        repos = JSON.parse(response.body)
        break if repos.empty?
        all_repos.concat(repos.map { |r| r["full_name"] })
        break if repos.size < 100 || page >= 2 # cap at 200 repos
        page += 1
      else
        Rails.logger.warn "[TZ] GitHub API returned #{response.code} for org #{org_name}"
        return nil if all_repos.empty?
        break
      end
    end

    all_repos
  end

  def self.delete_webhook(owner, repo, token, hook_id)
    uri = URI("https://api.github.com/repos/#{owner}/#{repo}/hooks/#{hook_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Delete.new(uri.request_uri)
    request["Authorization"] = "token #{token}"
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "OpenProject-TZ"

    http.request(request)
  end
end
