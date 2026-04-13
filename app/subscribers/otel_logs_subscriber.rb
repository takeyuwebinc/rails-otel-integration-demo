require "opentelemetry-logs-sdk"

class OtelLogsSubscriber
  def initialize
    @logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new
    @logger_provider.add_log_record_processor(
      OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(
        OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new
      )
    )
    @logger = @logger_provider.logger(name: "bookstore-otel-demo.event_reporter")
  end

  # event is a Hash with keys: :name, :payload, :tags, :context, :timestamp, :source_location
  def emit(event)
    attributes = {}
    event[:payload]&.each { |key, value| attributes[key.to_s] = value }
    event[:tags]&.each { |key, value| attributes["tag.#{key}"] = value }
    event[:context]&.each { |key, value| attributes["context.#{key}"] = value }

    span_context = OpenTelemetry::Trace.current_span.context

    @logger.on_emit(
      body: event[:name],
      severity_text: "INFO",
      severity_number: OpenTelemetry::Logs::SeverityNumber::SEVERITY_NUMBER_INFO,
      timestamp: event[:timestamp],
      attributes: attributes,
      trace_id: span_context&.trace_id,
      span_id: span_context&.span_id,
      trace_flags: span_context&.trace_flags,
      context: OpenTelemetry::Context.current
    )
  end

  def shutdown
    @logger_provider.shutdown
  end
end
