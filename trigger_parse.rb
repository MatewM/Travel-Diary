#!/usr/bin/env ruby
# Script para disparar ParseTicketService y ver logs

require_relative 'config/environment'

puts "=== Triggering ParseTicketService with detailed logging ==="

# Resetear el ticket
ticket_id = "702af707-bc5d-48b4-ae76-7aef7e8198d6"
ticket = Ticket.find(ticket_id)

ticket.update_columns(
  status: 'pending_parse',
  flight_number: nil,
  airline: nil,
  departure_airport: nil,
  arrival_airport: nil,
  departure_datetime: nil,
  arrival_datetime: nil,
  departure_country_id: nil,
  arrival_country_id: nil,
  parsed_data: nil,
  updated_at: Time.current
)

puts "Ticket reset. Now calling ParseTicketService..."
puts "Check the Rails logs for detailed output..."

# Llamar ParseTicketService
result = ParseTicketService.call(ticket_id)

puts "Result: #{result[:success] ? 'SUCCESS' : 'FAILED'}"
puts "Confidence: #{result[:confidence_level]}"

ticket.reload
puts "Final status: #{ticket.status}"
puts "Flight number: #{ticket.flight_number}"