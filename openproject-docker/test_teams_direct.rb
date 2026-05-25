# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Delete old duplicate webhook
Webhooks::Webhook.where(name: "Teams Notifications").destroy_all

webhook = Webhooks::Webhook.find_by(name: "Tvs Team")
puts "Webhook: #{webhook.name} (ID=#{webhook.id})"
puts "Events: #{webhook.events.map(&:name).join(', ')}"

# Send a test Adaptive Card directly to the Power Automate URL
url = webhook.url
uri = URI.parse(url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.open_timeout = 15
http.read_timeout = 30

# Try simple text format first (Power Automate might not support Adaptive Cards)
simple_payload = {
  type: "message",
  attachments: [
    {
      contentType: "application/vnd.microsoft.card.adaptive",
      contentUrl: nil,
      content: {
        "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
        "type" => "AdaptiveCard",
        "version" => "1.4",
        "body" => [
          { "type" => "TextBlock", "text" => "Test from OpenProject", "weight" => "Bolder", "size" => "Medium" },
          { "type" => "TextBlock", "text" => "This is a test notification from Tamil Zorous OpenProject.", "wrap" => true },
          { "type" => "TextBlock", "text" => "Time: #{Time.now.strftime('%B %d, %Y at %H:%M')}", "size" => "Small", "isSubtle" => true }
        ]
      }
    }
  ]
}

request = Net::HTTP::Post.new(uri.request_uri)
request["Content-Type"] = "application/json"
request.body = simple_payload.to_json

puts "\nSending Adaptive Card..."
response = http.request(request)
puts "Response: #{response.code} #{response.message}"
puts "Body: #{response.body.to_s[0..500]}"

# Also try MessageCard format (older Teams format)
puts "\n--- Trying MessageCard format ---"
msgcard_payload = {
  "@type" => "MessageCard",
  "@context" => "http://schema.org/extensions",
  "themeColor" => "0076D7",
  "summary" => "OpenProject Test Notification",
  "sections" => [
    {
      "activityTitle" => "Test from OpenProject (Tamil Zorous)",
      "activitySubtitle" => Time.now.strftime("%B %d, %Y at %H:%M"),
      "facts" => [
        { "name" => "Status", "value" => "Test" },
        { "name" => "Source", "value" => "OpenProject" }
      ],
      "markdown" => true
    }
  ]
}

request2 = Net::HTTP::Post.new(uri.request_uri)
request2["Content-Type"] = "application/json"
request2.body = msgcard_payload.to_json

response2 = http.request(request2)
puts "Response: #{response2.code} #{response2.message}"
puts "Body: #{response2.body.to_s[0..500]}"

# Also try plain JSON (Power Automate trigger may expect raw data)
puts "\n--- Trying plain JSON ---"
plain_payload = {
  "event" => "work_package:created",
  "message" => "Test notification from OpenProject (Tamil Zorous)",
  "timestamp" => Time.now.iso8601,
  "source" => "OpenProject"
}

request3 = Net::HTTP::Post.new(uri.request_uri)
request3["Content-Type"] = "application/json"
request3.body = plain_payload.to_json

response3 = http.request(request3)
puts "Response: #{response3.code} #{response3.message}"
puts "Body: #{response3.body.to_s[0..500]}"
