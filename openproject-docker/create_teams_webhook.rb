# frozen_string_literal: true

teams_url = "https://default43e98a1a0bea4f3881cd0f9bddfb80.52.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/9217d907f8d648569ee4c7826599c943/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=xftnCI5rFVBn8AKPhGo9uglCYIbs-ApQAHz1A6lM1iU"

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
