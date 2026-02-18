# frozen_string_literal: true

class TicketsController < ApplicationController
  def new
    @ticket = current_user.tickets.build
  end

  def create
    @ticket = current_user.tickets.build(ticket_params)

    if @ticket.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to dashboard_path, notice: "Billete subido correctamente" }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :new, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  private

  def ticket_params
    params.fetch(:ticket, {}).permit(:original_file)
  end
end
