# frozen_string_literal: true

class TicketsController < ApplicationController
  include ActionView::RecordIdentifier
  before_action :set_ticket, only: %i[verify update destroy requeue]

  def new
    @ticket = current_user.tickets.build
  end

  def create
    files = uploaded_files

    if files.empty?
      @ticket = current_user.tickets.build
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "upload_form_errors",
            "<div class='p-3 mb-4 rounded-lg bg-red-50 text-red-700 text-sm'>
              ⚠️ Debes seleccionar al menos un archivo.
            </div>".html_safe
          ), status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end

    created_tickets = files.filter_map do |file|
      ticket = current_user.tickets.new(status: :pending_parse, original_files: [file])
      ticket.save ? ticket : nil
    end

    @created_tickets = created_tickets

    if created_tickets.any?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("modal", ""),
            turbo_stream.prepend("tickets_list", partial: "tickets/ticket", collection: @created_tickets ),
            turbo_stream.replace("pending_analysis_banner", partial: "dashboard/pending_analysis_banner", locals: { pending_count: current_user.tickets.pending_parse.count })
          ]
        end
        format.html { redirect_to dashboard_path, notice: "#{created_tickets.size} billetes subidos correctamente" }
      end
    else
      @ticket = current_user.tickets.build
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "upload_form_errors",
            partial: "tickets/upload_errors",
            locals: { message: "Todos los archivos fallaron la validación. Comprueba el tipo y tamaño." }
          ), status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  # POST /tickets/process
  def process_tickets
    @processing_tickets = current_user.tickets.pending_parse.to_a

    # Limpiar tickets atascados en processing (más de 10 minutos)
    stuck_tickets = current_user.tickets.where(status: :processing)
                               .where('updated_at < ?', 10.minutes.ago)

    stuck_tickets.each do |ticket|
      ticket.update_columns(
        status: "error",
        parsed_data: { error: "Ticket stuck in processing - reset automatically" },
        updated_at: Time.current
      )
    end

    @processing_tickets.each do |ticket|
      ticket.update_column(:status, "processing")
      ParseTicketJob.perform_later(ticket.id)
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to dashboard_path }
    end
  end

  # GET /tickets/:id/verify
  def verify
    @airports = Airport.order(:iata_code)
    @issues   = (@ticket.parsed_data&.dig("confidence") || {})
               .select { |_, v| v == "low" }
               .keys
  end

  # PATCH /tickets/:id
  def update
    if @ticket.update(ticket_params.merge(status: :parsed, verified_by_user: true))
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(ActionView::RecordIdentifier.dom_id(@ticket), partial: "tickets/ticket", locals: { ticket: @ticket }),
            turbo_stream.update("modal", "")
          ]
        end
        format.html { redirect_to dashboard_path, notice: "Billete verificado correctamente." }
      end
    else
      @airports = Airport.order(:iata_code)
      @issues   = (@ticket.parsed_data&.dig("confidence") || {})
                 .select { |_, v| v == "low" }
                 .keys
      respond_to do |format|
        format.turbo_stream do
          # ✅ CORRECTO: re-renderizar el modal completo con los errores
          render turbo_stream: turbo_stream.update("modal",
            partial: "tickets/verify",
            locals: { ticket: @ticket, airports: @airports, issues: @issues }
          )
        end
        format.html { redirect_to dashboard_path, alert: @ticket.errors.full_messages.to_sentence }
      end
    end
  end

  def requeue
    @ticket.update_column(:status, "processing")
    ParseTicketJob.perform_later(@ticket.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          @ticket,
          partial: "tickets/ticket",
          locals: { ticket: @ticket.reload }
        )
      end
      format.html { redirect_to dashboard_path }
    end
  end

  def destroy
    dom_id = ActionView::RecordIdentifier.dom_id(@ticket)
    @ticket.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id) }
      format.html { redirect_to dashboard_path }
    end
  end

  private

  def set_ticket
    @ticket = current_user.tickets.find(params[:id])
  end

  def uploaded_files
    raw = params.dig(:ticket, :original_files) || []
    Array(raw).reject { |f| f.blank? || !f.respond_to?(:content_type) }
  end

  def ticket_params
    params.require(:ticket).permit(
      :flight_number,
      :airline,
      :departure_airport,
      :arrival_airport,
      :departure_datetime,
      :arrival_datetime
    )
  end
end
