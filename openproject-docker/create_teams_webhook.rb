# frozen_string_literal: true

teams_url = ENV.fetch("TZ_TEAMS_WEBHOOK_URL", "YOUR_POWER_AUTOMATE_WEBHOOK_URL_HERE")

# Delete any existing webhook with same name
Webhooks::Webhook.where(name: "Teams Notifications").destroy_all

webhook = Webhooks::Webhook.create!(
  name: "Teams Notifications",
  url: teams_url,
  description: "Tamil Zorous Teams channel notifications",
  secret: nil,
  enabled: true,
  all_projects: true
)

# Add events using the correct FK column
["work_package:created", "work_package:updated"].each do |event_name|
  Webhooks::Event.create!(name: event_name, webhooks_webhook_id: webhook.id)
end

puts "Webhook created successfully!"
puts "  ID: #{webhook.id}"
puts "  Name: #{webhook.name}"
puts "  Events: #{webhook.events.reload.map(&:name).join(', ')}"
puts "  All projects: #{webhook.all_projects}"
