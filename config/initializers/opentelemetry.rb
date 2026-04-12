require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"
require "opentelemetry-metrics-sdk"
require "opentelemetry-exporter-otlp-metrics"

OpenTelemetry::SDK.configure do |c|
  c.service_name = "bookstore-otel-demo"

  c.use_all
end

# OTel Metrics
meter_provider = OpenTelemetry::SDK::Metrics::MeterProvider.new
meter_provider.add_metric_reader(
  OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
    exporter: OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new,
    export_interval_millis: 60_000,
    export_timeout_millis: 30_000
  )
)
OpenTelemetry.meter_provider = meter_provider

meter = OpenTelemetry.meter_provider.meter("bookstore-otel-demo")
ORDERS_CREATED_COUNTER = meter.create_counter(
  "orders.created",
  unit: "{orders}",
  description: "累積注文作成数"
)
ORDERS_AMOUNT_HISTOGRAM = meter.create_histogram(
  "orders.amount",
  unit: "JPY",
  description: "注文金額の分布"
)

# EventReporter → OTel Logs Subscriber
# ビジネスイベントのみをOTel Logsに送信する（フレームワーク内部イベントは除外）
BUSINESS_EVENTS = %w[order.created order.status_changed book.viewed inventory.low].freeze

Rails.application.config.after_initialize do
  if defined?(Rails.event)
    Rails.event.subscribe(OtelLogsSubscriber.new) { |event| BUSINESS_EVENTS.include?(event[:name]) }
  end
end
