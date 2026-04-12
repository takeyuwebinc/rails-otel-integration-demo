require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

OpenTelemetry::SDK.configure do |c|
  c.service_name = "bookstore-otel-demo"

  c.use_all
end

# EventReporter → OTel Logs Subscriber
Rails.application.config.after_initialize do
  if defined?(Rails.event)
    Rails.event.subscribe(OtelLogsSubscriber.new)
  end
end
