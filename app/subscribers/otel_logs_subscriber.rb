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

    # payload → attributes
    payload = event[:payload]
    if payload.respond_to?(:each)
      payload.each do |key, value|
        attributes[key.to_s] = value.to_s
      end
    end

    # tags → attributes with "tag." prefix
    tags = event[:tags]
    if tags.respond_to?(:each)
      tags.each do |key, value|
        attributes["tag.#{key}"] = value.to_s
      end
    end

    # context → attributes with "context." prefix
    ctx = event[:context]
    if ctx.respond_to?(:each)
      ctx.each do |key, value|
        attributes["context.#{key}"] = value.to_s
      end
    end

    # 現在のSpanコンテキストからtrace_id/span_idを取得し、Log Recordに付与する
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
