u = User.find_by(login: "admin")
if u
  u.firstname = "TZ-WorkSpace"
  u.lastname = "Admin"
  u.save!
  $stdout.puts "Updated admin name to: #{u.name}"
else
  $stdout.puts "Admin user not found"
end
