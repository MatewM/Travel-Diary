# frozen_string_literal: true

class ParseTicketJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    result = ParseTicketService.call(ticket_id)
    ticket = result[:ticket] || Ticket.find_by(id: ticket_id)
    return unless ticket

    Turbo::StreamsChannel.broadcast_replace_to(
      "tickets_#{ticket.user_id}",
      target: ActionView::RecordIdentifier.dom_id(ticket),
      partial: "tickets/ticket",
      locals:  { ticket: ticket }
    )
  end
end
