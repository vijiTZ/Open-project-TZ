# frozen_string_literal: true

# Check current webhook setup
webhook = Webhooks::Webhook.find(3)
puts "--- Current webhook events ---"
webhook.events.each { |e| puts "  #{e.name}" }

# Check all distinct event names in DB
puts "\n--- All event names in events table ---"
Webhooks::Event.distinct.pluck(:name).sort.each { |n| puts "  #{n}" }

# Check webhook logs
puts "\n--- Recent webhook logs ---"
Webhooks::Log.order(created_at: :desc).limit(5).each do |log|
  puts "  #{log.event_name} -> #{log.response_code} at #{log.created_at}"
end

# Check the call! method to understand payload structure
svc = Webhooks::Outgoing::RequestWebhookService
puts "\n--- RequestWebhookService source file ---"
puts svc.instance_method(:call!).source_location.inspect
