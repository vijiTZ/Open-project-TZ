svc = Webhooks::Outgoing::RequestWebhookService

# Check initialize parameters
m = svc.instance_method(:initialize)
puts "Init params: #{m.parameters.inspect}"

# Check what readers/accessors exist
puts "Instance methods: #{svc.instance_methods(false).sort.inspect}"

# Check the Log model columns
puts "Log columns: #{Webhooks::Log.column_names.inspect}"
