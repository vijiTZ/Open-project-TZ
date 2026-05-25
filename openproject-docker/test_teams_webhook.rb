# frozen_string_literal: true

# Test sending a webhook notification to Teams
webhook = Webhooks::Webhook.find_by(name: "Teams Notifications")
unless webhook
  puts "No Teams webhook found"
  exit 1
end

puts "Testing webhook: #{webhook.name}"
puts "URL: #{webhook.url.truncate(80)}"
puts "Events: #{webhook.events.map(&:name).join(', ')}"

# Directly call the Teams formatter and send
payload = TzTeamsFormatter.format("work_package:created", nil, webhook)
if payload
  uri = URI.parse(webhook.url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")
  http.open_timeout = 10
  http.read_timeout = 15

  request = Net::HTTP::Post.new(uri.request_uri)
  request["Content-Type"] = "application/json"
  request.body = payload.to_json

  response = http.request(request)
  puts "Response: #{response.code} #{response.message}"
  puts "Body: #{response.body.to_s.truncate(200)}"
else
  puts "Formatter returned nil"
end
