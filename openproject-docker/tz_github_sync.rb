# frozen_string_literal: true

# Tamil Zorous: GitHub PR Sync — Controller patches & auto-sync thread
# The TzGithubPrSync module is defined in tz_pr_sync_module.rb (loaded first alphabetically).

Rails.application.config.after_initialize do
  begin
    GithubIntegration::Admin::SettingsController.class_eval do
      unless method_defined?(:tz_handle_repo_actions_original)
        alias_method :tz_handle_repo_actions_original, :tz_handle_repo_actions
      end

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

        # Expand org entries
        expanded_repos = []
        repos.each do |entry|
          entry_type = entry["type"].to_s
          if entry_type == "org"
            org_name = entry["org_name"] || entry["full_name"]
            org_repos = TzGithubRepoManager.fetch_org_repos(org_name, token)
            expanded_repos.concat(org_repos) if org_repos.is_a?(Array)
          elsif entry_type != "org_repo"
            full_name = entry["full_name"]
            expanded_repos << full_name if full_name.to_s.include?("/")
          end
        end
        expanded_repos.uniq!

        total_synced = 0
        total_linked = 0
        errors = []

        expanded_repos.each do |full_name|
          owner, repo = full_name.split("/", 2)
          begin
            result = TzGithubPrSync.sync_repo(owner, repo, token)
            total_synced += result[:synced]
            total_linked += result[:linked]
            errors << "#{full_name}: #{result[:error]}" if result[:error]
          rescue => e
            errors << "#{full_name}: #{e.message}"
          end
        end

        if errors.any?
          flash[:warning] = "Synced #{total_synced} PRs (#{total_linked} linked). Errors: #{errors.join('; ')}"
        else
          flash[:notice] = "Synced #{total_synced} PRs from #{expanded_repos.size} repo(s). #{total_linked} linked to tasks."
        end

        redirect_to "/github_integration/admin/settings"
      end
    end

    # --- Auto-sync thread (every 60s) ---
    if defined?(Puma) || $PROGRAM_NAME.include?("puma") || $PROGRAM_NAME.include?("rails")
      Thread.new do
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
                expanded_repos = []
                repos.each do |entry|
                  entry_type = entry["type"].to_s
                  if entry_type == "org"
                    org_name = entry["org_name"] || entry["full_name"]
                    org_repos = TzGithubRepoManager.fetch_org_repos(org_name, token)
                    expanded_repos.concat(org_repos) if org_repos.is_a?(Array)
                  elsif entry_type != "org_repo"
                    fn = entry["full_name"]
                    expanded_repos << fn if fn.to_s.include?("/")
                  end
                end
                expanded_repos.uniq!

                total = 0
                expanded_repos.each do |full_name|
                  owner, repo = full_name.split("/", 2)
                  result = TzGithubPrSync.sync_repo(owner, repo, token)
                  total += result[:synced]
                rescue => e
                  Rails.logger.warn "[TZ] Auto-sync failed for #{full_name}: #{e.message}"
                end
                Rails.logger.info "[TZ] Auto-sync complete: #{total} PRs from #{expanded_repos.size} repo(s)"
              end
            end
          rescue => e
            Rails.logger.warn "[TZ] Auto-sync error: #{e.message}"
          end

          sleep 60
        end
      end
      Rails.logger.info "[TZ] GitHub PR auto-sync started (every 1 min)"
    end

    Rails.logger.info "[TZ] GitHub PR sync loaded (module v#{TzGithubPrSync::TZ_SYNC_VERSION rescue '?'})"
  rescue => e
    Rails.logger.error "[TZ] Failed to load GitHub PR sync: #{e.message}"
  end
end
