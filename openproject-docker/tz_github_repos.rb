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
  # --- Controller: handles add/remove repo actions ---
  GithubIntegration::Admin::SettingsController.class_eval do
    # POST /github_integration/admin/settings/connect_repo
    def connect_repo
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
        redirect_to github_integration_admin_settings_path and return
      end

      # Parse repo owner/name from URL
      match = repo_url.match(%r{github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$})
      unless match
        flash[:error] = "Invalid GitHub URL. Use format: https://github.com/owner/repo"
        redirect_to github_integration_admin_settings_path and return
      end

      owner, repo = match[1], match[2]
      full_name = "#{owner}/#{repo}"

      # Build webhook URL
      settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
      api_user_id = settings[:github_user_id]
      api_user = api_user_id.present? ? User.find_by(id: api_user_id) : nil
      api_token = api_user&.api_token&.plain_value

      unless api_token
        flash[:error] = "No GitHub actor configured. Set the GitHub actor user first (needs an API token)."
        redirect_to github_integration_admin_settings_path and return
      end

      webhook_secret = settings[:webhook_secret] || ""
      host = Setting.host_name
      protocol = Setting.protocol rescue "https"
      webhook_url = "#{protocol}://#{host}/webhooks/github?key=#{api_token}"

      # Call GitHub API to create webhook
      begin
        result = TzGithubRepoManager.create_webhook(owner, repo, token, webhook_url, webhook_secret)

        if result[:success]
          # Save to settings
          repos = Array(settings[:connected_repos])
          repos.reject! { |r| r["full_name"] == full_name } # avoid duplicates
          repos << {
            "full_name" => full_name,
            "url" => "https://github.com/#{full_name}",
            "hook_id" => result[:hook_id],
            "connected_at" => Time.now.iso8601
          }

          merged = settings.merge("connected_repos" => repos)

          # Save token encrypted if requested
          if save_token
            merged["github_admin_token"] = TzGithubTokenStore.encrypt(token)
          end

          Setting.plugin_openproject_github_integration = merged
          flash[:notice] = "Successfully connected #{full_name}! Webhook is active."
          flash[:notice] += " Token saved securely." if save_token
        else
          flash[:error] = "Failed to connect: #{result[:error]}"
        end
      rescue => e
        flash[:error] = "Error connecting to GitHub: #{e.message}"
      end

      redirect_to github_integration_admin_settings_path
    end

    # POST /github_integration/admin/settings/disconnect_repo
    def disconnect_repo
      full_name = params[:full_name].to_s.strip
      token = params[:github_token].to_s.strip

      settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access

      # Use saved token if field is blank
      if token.blank? && settings[:github_admin_token].present?
        token = TzGithubTokenStore.decrypt(settings[:github_admin_token])
      end

      repos = Array(settings[:connected_repos])
      repo_config = repos.find { |r| r["full_name"] == full_name }

      if repo_config && token.present? && repo_config["hook_id"]
        # Try to delete webhook from GitHub
        owner, repo = full_name.split("/", 2)
        begin
          TzGithubRepoManager.delete_webhook(owner, repo, token, repo_config["hook_id"])
        rescue => e
          Rails.logger.warn "[TZ] Could not delete webhook from GitHub: #{e.message}"
        end
      end

      # Remove from settings regardless
      repos.reject! { |r| r["full_name"] == full_name }
      merged = settings.merge("connected_repos" => repos)
      Setting.plugin_openproject_github_integration = merged
      flash[:notice] = "Disconnected #{full_name}."

      redirect_to github_integration_admin_settings_path
    end

    # POST /github_integration/admin/settings/clear_saved_token
    def clear_saved_token
      settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
      merged = settings.except(:github_admin_token, "github_admin_token")
      Setting.plugin_openproject_github_integration = merged
      flash[:notice] = "Saved GitHub token has been removed."
      redirect_to github_integration_admin_settings_path
    end

    # Override show to load connected repos
    alias_method :original_show, :show
    def show
      original_show
      settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
      @connected_repos = Array(settings[:connected_repos])
      @has_saved_token = settings[:github_admin_token].present?
    end
  end

  # --- Routes ---
  Rails.application.routes.draw do
    namespace "github_integration" do
      namespace "admin" do
        post "settings/connect_repo", to: "settings#connect_repo", as: :connect_repo
        post "settings/disconnect_repo", to: "settings#disconnect_repo", as: :disconnect_repo
        post "settings/clear_saved_token", to: "settings#clear_saved_token", as: :clear_saved_token
      end
    end
  end

  Rails.logger.info "[TZ] GitHub repo manager loaded"
rescue => e
  Rails.logger.error "[TZ] Failed to load GitHub repo manager: #{e.message}"
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
      { success: false, error: "Webhook already exists on this repo or validation failed. (#{response.code})" }
    else
      error_msg = begin
                    JSON.parse(response.body)["message"]
                  rescue
                    response.body.to_s.truncate(200)
                  end
      { success: false, error: "GitHub API returned #{response.code}: #{error_msg}" }
    end
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
