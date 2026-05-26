# Check what payload structure an attachment webhook sends
wp = WorkPackage.joins(:attachments).where("attachments.id > 0").first
if wp && wp.attachments.any?
  att = wp.attachments.first
  # Simulate the webhook payload
  representer = API::V3::Attachments::AttachmentRepresenter.new(att, current_user: User.admin.first)
  payload = representer.to_json
  $stdout.puts "ATTACHMENT PAYLOAD KEYS: #{JSON.parse(payload).keys.inspect}"
  $stdout.puts "CONTAINER LINK: #{JSON.parse(payload).dig('_links', 'container').inspect}"
  $stdout.puts "FULL PAYLOAD: #{payload[0..500]}"
else
  $stdout.puts "No WP with attachments found"
end
