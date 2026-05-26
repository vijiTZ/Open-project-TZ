# Force re-sync: clear comment labels then sync to trigger Teams notification
settings = Hash(Setting.plugin_openproject_github_integration).with_indifferent_access
token = TzGithubTokenStore.decrypt(settings[:github_admin_token])
repos = Array(settings[:connected_repos])

# Clear existing TZ: @ comment labels so has_new_comments triggers
GithubPullRequest.find_each do |pr|
  old_labels = pr.labels || []
  cleaned = old_labels.reject { |l| (l["name"] || "").start_with?("TZ: @") }
  if cleaned.size != old_labels.size
    pr.update_column(:labels, cleaned)
    puts "Cleared #{old_labels.size - cleaned.size} comment labels from PR ##{pr.number}"
  end
end

repos.each do |entry|
  entry_type = entry["type"].to_s
  next if entry_type == "org" || entry_type == "org_repo"
  fn = entry["full_name"]
  next unless fn.to_s.include?("/")
  owner, repo = fn.split("/", 2)
  puts "Syncing #{fn}..."
  result = TzGithubPrSync.sync_repo(owner, repo, token)
  puts "Result: #{result.inspect}"
end
