pr = GithubPullRequest.find_by(number: 1)
if pr
  labels = pr.labels.select { |l| l["name"].to_s.start_with?("TZ: @") }
  labels.each_with_index do |l, i|
    parts = l["name"].sub(/^TZ:\s*/, "").split("|||")
    $stdout.puts "LABEL #{i}: type=[#{parts[2]}] id=[#{parts[4]}] reply_to=[#{parts[5]}] text=#{parts[0][0..50]}"
  end
  $stdout.puts "Total: #{labels.size} comment labels"
else
  $stdout.puts "PR #1 not found"
end
