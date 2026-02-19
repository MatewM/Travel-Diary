# frozen_string_literal: true

class TicketsController < ApplicationController
  before_action :set_ticket, only: %i[verify update]

  def new
    @ticket = current_user.tickets.build
  end

  def create
    files = uploaded_files

    if files.empty?
      @ticket = current_user.tickets.build
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("upload_form_errors",
            '<p class="text-sm text-red-600 mt-2 flex items-center gap-1">' \
            '<span>⚠️</span> Debes seleccionar al menos un archivo.</p>'.html_safe),
            status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end

    # Construir un ticket por cada archivo usando asignación en constructor
    # para que has_many_attached registre el cambio ANTES de la validación.
    @created_tickets = files.filter_map do |file|
      ticket = current_user.tickets.new(status: :pending_parse, original_files: [ file ])
      ticket.save ? ticket : nil
    end
    

    if @created_tickets.any?
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to dashboard_path, notice: "#{@created_tickets.size} billete(s) subido(s) correctamente" }
      end
    else
      @ticket = current_user.tickets.build
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("upload_form_errors",
            '<p class="text-sm text-red-600 mt-2 flex items-center gap-1">' \
            '<span>⚠️</span> Todos los archivos fallaron la validación. Comprueba el tipo y tamaño.</p>'.html_safe),
            status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  # POST /tickets/process
  # Enqueues a background job for every pending_parse ticket of the current user.
  # Marks them as :processing immediately so the UI shows the spinner right away.
  def process_tickets
    @processing_tickets = current_user.tickets.pending_parse.to_a
  
    @processing_tickets.each do |ticket|
      ticket.update_column(:status, :processing)
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
    @issues   = @ticket.parsed_data&.dig("confidence")
                       &.select { |_, v| v == "low" }
                       &.keys || []
  end

  # PATCH /tickets/:id — saves verified data from the review modal
  def update
    if @ticket.update(ticket_params.merge(status: :parsed, verified_by_user: true))
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@ticket, partial: "tickets/ticket", locals: { ticket: @ticket }),
            turbo_stream.replace("modal", html: "")
          ]
        end
        format.html { redirect_to dashboard_path, notice: "Billete verificado correctamente." }
      end
    else
      @airports = Airport.order(:iata_code)
      @issues   = []
      render :verify, status: :unprocessable_entity
    end
  end

  private

  def set_ticket
    @ticket = current_user.tickets.find(params[:id])
  end

  def uploaded_files
    raw = params.dig(:ticket, :original_files)
    Array(raw).reject { |f| f.blank? || !f.respond_to?(:content_type) }
  end

  def ticket_params
    params.require(:ticket).permit(
      :flight_number, :airline,
      :departure_airport, :arrival_airport,
      :departure_datetime, :arrival_datetime
    )
  end
end
