# frozen_string_literal: true

class ParseTicketJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 2 # Configuración a nivel de clase

  discard_on StandardError do |job, exception|
    ticket_id = job.arguments.first
    ticket = Ticket.find_by(id: ticket_id)
    next unless ticket

    ticket.update_columns(
      status: "error",
      parsed_data: { error: exception.message, final_attempt: true },
      updated_at: Time.current
    )

    Rails.logger.debug "[ParseTicketJob] Ticket #{ticket_id} discarded due to error: #{exception.message}" # Nuevo log
    # Broadcast del cambio para actualizar la UI
    Turbo::StreamsChannel.broadcast_replace_to(
      "tickets_#{ticket.user_id}",
      target: ActionView::RecordIdentifier.dom_id(ticket),
      partial: "tickets/ticket",
      locals: { ticket: ticket }
    )
  end

  def perform(ticket_id)
    Rails.logger.debug "[ParseTicketJob] Starting job for ticket #{ticket_id}" # Nuevo log
    # #region agent log - Job start
    File.open("/home/phunna/.cursor/debug-ad4598.log", "a") do |f|
      f.puts({
        sessionId: "ad4598",
        runId: "job_execution_#{ticket_id}_#{Time.now.to_i}",
        hypothesisId: "multiple_calls",
        location: "parse_ticket_job.rb:perform_start",
        message: "ParseTicketJob started",
        data: { ticket_id: ticket_id, timestamp: Time.now.to_i },
        timestamp: Time.now.to_i
      }.to_json)
      f.flush # Asegurar que se escribe inmediatamente
    end
    # #endregion

    ticket = Ticket.find(ticket_id)

    # Skip if ticket already processed successfully or has error
    if ticket.parsed? || ticket.auto_verified? || ticket.needs_review? || ticket.manual_required? || ticket.error?
      Rails.logger.debug "[ParseTicketJob] Skipping already processed ticket #{ticket_id} with status #{ticket.status}" # Nuevo log
      File.open("/home/phunna/.cursor/debug-ad4598.log", "a") do |f|
        f.puts({
          sessionId: "ad4598",
          runId: "job_execution_#{ticket_id}_#{Time.now.to_i}",
          hypothesisId: "skip_processed",
          location: "parse_ticket_job.rb:skip_processed",
          message: "Skipping already processed ticket",
          data: { ticket_id: ticket_id, status: ticket.status },
          timestamp: Time.now.to_i
        }.to_json)
        f.flush # Asegurar que se escribe inmediatamente
      end
      # #endregion
      return
    end

    # #region agent log - Ticket status before processing
    File.open("/home/phunna/.cursor/debug-ad4598.log", "a") do |f|
      f.puts({
        sessionId: "ad4598",
        runId: "job_execution_#{ticket_id}_#{Time.now.to_i}",
        hypothesisId: "status_change",
        location: "parse_ticket_job.rb:pre_processing",
        message: "Ticket status before processing",
        data: { ticket_id: ticket_id, status: ticket.status, user_id: ticket.user_id },
        timestamp: Time.now.to_i
      }.to_json)
    end
    # #endregion

    # Temporalmente removido rate limiting para debugging
    # # Global rate limiting: 1 job cada 0.5s (15 RPM máximo - límite gratuito)
    # Rails.cache.fetch("gemini_global_lock", expires_in: 1.seconds) do
    #   sleep(0.5)
    # end

    # # Per-user rate limiting: 1 job cada 1s por usuario
    # Rails.cache.fetch("gemini_user_#{ticket.user_id}", expires_in: 2.seconds) do
    #   sleep(1)
    # end

    result = ParseTicketService.call(ticket_id)

    # #region agent log - Parse result
    File.open("/home/phunna/.cursor/debug-ad4598.log", "a") do |f|
      f.puts({
        sessionId: "ad4598",
        runId: "job_execution_#{ticket_id}_#{Time.now.to_i}",
        hypothesisId: "parse_result",
        location: "parse_ticket_job.rb:post_parsing",
        message: "ParseTicketService result",
        data: {
          ticket_id: ticket_id,
          success: result.is_a?(Hash) ? result[:success] : nil,
          error: result.is_a?(Hash) ? result[:error] : nil,
          # Añado aquí el parsed_data completo de Gemini
          gemini_parsed_data: result.is_a?(Hash) && result[:ticket] ? result[:ticket].parsed_data : nil,
          # Y aquí el resultado del ConfidenceCalculatorService
          confidence_calculator_result: result.is_a?(Hash) && result[:ticket]&.parsed_data ? ConfidenceCalculatorService.call(result[:ticket].parsed_data) : nil,
          ticket_status: result.is_a?(Hash) && result[:ticket] ? result[:ticket].status : nil,
          confidence_level: result.is_a?(Hash) ? result[:confidence_level] : nil
        },
        timestamp: Time.now.to_i
      }.to_json)
    end
    # #endregion

    ticket = Ticket.find(ticket_id) # Recargar el ticket para asegurar el estado más reciente
    return unless ticket

    # #region agent log - Final ticket status
    File.open("/home/phunna/.cursor/debug-ad4598.log", "a") do |f|
      f.puts({
        sessionId: "ad4598",
        runId: "job_execution_#{ticket_id}_#{Time.now.to_i}",
        hypothesisId: "final_status",
        location: "parse_ticket_job.rb:final_status",
        message: "Final ticket status before broadcasts",
        data: {
          ticket_id: ticket_id,
          status: ticket.status,
          parsed_data_keys: ticket.parsed_data&.keys,
          has_error: ticket.parsed_data&.dig("error").present?
        },
        timestamp: Time.now.to_i
      }.to_json)
    end
    # #endregion

    # 1. Actualizar la tarjeta del ticket en la lista
    Turbo::StreamsChannel.broadcast_replace_to(
      "tickets_#{ticket.user_id}",
      target: ActionView::RecordIdentifier.dom_id(ticket),
      partial: "tickets/ticket",
      locals: { ticket: ticket }
    )

    # 2. Actualizar el banner de pendientes
    pending_count = Ticket.where(
      user_id: ticket.user_id,
      status: :pending_parse
    ).count

    Turbo::StreamsChannel.broadcast_replace_to(
      "tickets_#{ticket.user_id}",
      target: "pending_analysis_banner",
      partial: "dashboard/pending_analysis_banner",
      locals: { pending_count: pending_count }
    )

    # 3. Abrir modal de revisión solo si launch_modal fue activado por ConfidenceCalculatorService
    # Y NO es un estado que solo requiere visualización en la tabla (como need_review según petición del usuario)
    if (ticket.needs_review? || ticket.manual_required?) && (ticket.parsed_data || {})["launch_modal"] == true

      # Resaltar todos los campos con confidence != "high" (medium y low), no solo low
      raw_issues = (ticket.parsed_data || {}).dig("confidence")
                     &.select { |_, v| v != "high" }
                     &.keys
                     &.map(&:to_sym) || []

      # Normalizar: Gemini usa "flight_date" pero el formulario usa :departure_datetime
      issues = raw_issues.map { |k| k == :flight_date ? :departure_datetime : k }
      issues |= [:departure_datetime] if raw_issues.include?(:flight_date)

      year_source = (ticket.parsed_data || {})["year_source"]

      Turbo::StreamsChannel.broadcast_replace_to(
        "tickets_#{ticket.user_id}",
        target: "modal",
        partial: "tickets/verify",
        locals: {
          ticket: ticket,
          airports: Airport.order(:iata_code),
          issues: issues.uniq,
          year_source: year_source
        }
      )
    end
  end

  private
end
