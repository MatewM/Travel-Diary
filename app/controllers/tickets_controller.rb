# frozen_string_literal: true

class TicketsController < ApplicationController
  def new
    @ticket = current_user.tickets.build
  end

  def create
    files = uploaded_files

    if files.empty?
      @ticket = current_user.tickets.build   # necesario para render :new (HTML fallback)
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
      @ticket = current_user.tickets.build   # necesario para render :new (HTML fallback)
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

  private

  def uploaded_files
    raw = params.dig(:ticket, :original_files)
    Array(raw).reject { |f| f.blank? || !f.respond_to?(:content_type) }
  end
end
