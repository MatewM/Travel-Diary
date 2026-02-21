require 'mini_magick'
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

    # Obtener la ruta del archivo adjunto para extraer EXIF
    file_path = nil
    capture_date = nil
    if ticket.original_files.attached?
      begin
        # Necesitamos la ruta física del archivo en el sistema de almacenamiento de ActiveStorage
        # Esto puede variar dependiendo del adaptador de ActiveStorage (Disk, S3, etc.)
        # Para el adaptador DiskStorage (común en desarrollo), esto podría ser:
        file_path = ActiveStorage::Blob.service.send(:path_for, ticket.original_files.first.blob.key)
        capture_date = get_exif_date(file_path)
        Rails.logger.debug "[ParseTicketJob] Valor de capture_date obtenido: #{capture_date.inspect}"
        Rails.logger.debug "[ParseTicketJob] EXIF capture date for #{ticket_id}: #{capture_date}"
      rescue StandardError => e
        Rails.logger.warn "[ParseTicketJob] Error extracting EXIF for ticket #{ticket_id}: #{e.message}"
      end
    end

    result = ParseTicketService.call(ticket_id, capture_date) # Pasar la fecha de captura

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
          success: result[:success],
          error: result[:error],
          # Añado aquí el parsed_data completo de Gemini
          gemini_parsed_data: result[:ticket]&.parsed_data,
          # Y aquí el resultado del ConfidenceCalculatorService
          confidence_calculator_result: ConfidenceCalculatorService.call(result[:ticket]&.parsed_data),
          ticket_status: result[:ticket]&.status,
          confidence_level: result[:confidence_level]
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

    # 3. Si necesita revisión → abrir modal automáticamente
    if ticket.needs_review? || ticket.manual_required?
      issues = ticket.parsed_data
                     &.dig("confidence")
                     &.select { |_, v| v == "low" }
                     &.keys || []

      Turbo::StreamsChannel.broadcast_replace_to(
        "tickets_#{ticket.user_id}",
        target: "modal",
        partial: "tickets/verify",
        locals: {
          ticket: ticket,
          airports: Airport.order(:iata_code),
          issues: issues.map(&:to_sym)
        }
      )
    end
  end

  private

  def get_exif_date(file_path)
    image = MiniMagick::Image.open(file_path)
    date_time_original = image['exif:DateTimeOriginal'] || image['date:create']

    if date_time_original
      # Formato "YYYY:MM:DD HH:MM:SS" -> "YYYY-MM-DD"
      date_time_original.split(' ')[0].gsub!(':', '-')
    else
      nil
    end
  rescue MiniMagick::Invalid => e
    Rails.logger.warn "[ParseTicketJob] Invalid image for EXIF extraction: #{e.message}"
    nil
  end
end
