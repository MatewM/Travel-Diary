require "rails_helper"

RSpec.describe Ticket, type: :model do
  describe "factory" do
    it "crea un ticket válido (status: manual, sin archivo)" do
      expect(build(:ticket)).to be_valid
    end
  end

  describe "validación de archivos" do
    it "falla sin archivo cuando status es pending_parse" do
      ticket = build(:ticket, status: :pending_parse)
      expect(ticket).not_to be_valid
      expect(ticket.errors[:original_files]).to be_present
    end

    it "es válido sin archivo cuando status es manual" do
      expect(build(:ticket, status: :manual)).to be_valid
    end
  end

  describe "validación de datetimes" do
    it "falla si departure_datetime es posterior a arrival_datetime" do
      ticket = build(
        :ticket,
        departure_datetime: 2.hours.from_now,
        arrival_datetime: 1.hour.from_now
      )
      expect(ticket).not_to be_valid
      expect(ticket.errors[:arrival_datetime]).to be_present
    end

    it "falla si departure_datetime es igual a arrival_datetime" do
      now = Time.current
      ticket = build(:ticket, departure_datetime: now, arrival_datetime: now)
      expect(ticket).not_to be_valid
    end

    it "es válido cuando arrival_datetime es posterior a departure_datetime" do
      ticket = build(
        :ticket,
        departure_datetime: 1.hour.from_now,
        arrival_datetime: 3.hours.from_now
      )
      expect(ticket).to be_valid
    end
  end

  describe "validación de códigos IATA" do
    it "falla con un código IATA de departure_airport inválido" do
      expect(build(:ticket, departure_airport: "mad")).not_to be_valid
      expect(build(:ticket, departure_airport: "MADD")).not_to be_valid
      expect(build(:ticket, departure_airport: "1AB")).not_to be_valid
    end

    it "falla con un código IATA de arrival_airport inválido" do
      expect(build(:ticket, arrival_airport: "bcn")).not_to be_valid
    end

    it "es válido con códigos IATA correctos" do
      expect(build(:ticket, departure_airport: "MAD", arrival_airport: "BCN")).to be_valid
    end

    it "es válido sin código IATA (campo opcional)" do
      expect(build(:ticket, departure_airport: nil, arrival_airport: nil)).to be_valid
    end
  end

  describe "scope: recent_first" do
    let(:user) { create(:user) }

    it "ordena los billetes de forma determinista: más recientes primero" do
      # Crear 3 billetes con created_at diferente
      ticket_1 = create(:ticket, user: user, created_at: 3.days.ago)
      ticket_2 = create(:ticket, user: user, created_at: 1.day.ago)
      ticket_3 = create(:ticket, user: user, created_at: 2.days.ago)

      result = Ticket.where(user: user).recent_first.pluck(:id)

      # El más reciente (ticket_2) debe estar primero, luego ticket_3, luego ticket_1
      expect(result).to eq([ticket_2.id, ticket_3.id, ticket_1.id])
    end

    it "rompe empates usando id como desempate cuando created_at es idéntico" do
      # Crear 2 billetes con el mismo created_at pero IDs diferentes
      now = Time.current
      ticket_1 = create(:ticket, user: user)
      ticket_1.update_column(:created_at, now)

      ticket_2 = create(:ticket, user: user)
      ticket_2.update_column(:created_at, now)

      result = Ticket.where(user: user).recent_first.pluck(:id)

      # Ambos tienen el mismo created_at, así que se ordenan por id DESC
      expect(result).to eq([ticket_2.id, ticket_1.id])
    end

    it "mantiene orden consistente al cambiar de año en el dashboard" do
      # Simular el comportamiento del dashboard: filtrar por año y ordenar
      user = create(:user)
      
      # Crear billetes con departure_datetime en el año 2024
      year_2024_start = Date.new(2024, 1, 1).beginning_of_day
      year_2024_end = Date.new(2024, 12, 31).end_of_day

      ticket_a = create(:ticket, 
        user: user, 
        departure_datetime: Date.new(2024, 6, 15).noon,
        created_at: 5.days.ago
      )
      ticket_b = create(:ticket, 
        user: user, 
        departure_datetime: Date.new(2024, 7, 20).noon,
        created_at: 3.days.ago
      )
      ticket_c = create(:ticket, 
        user: user, 
        departure_datetime: nil,
        created_at: 1.day.ago
      )

      # Filtro del dashboard (simular)
      filtered = user.tickets
                     .where("(departure_datetime BETWEEN ? AND ?) OR (departure_datetime IS NULL AND created_at BETWEEN ? AND ?)",
                            year_2024_start, year_2024_end, year_2024_start, year_2024_end)
                     .recent_first

      result_ids = filtered.pluck(:id)

      # Esperamos que se ordene por created_at DESC (más recientes primero)
      # ticket_c (1 día atrás) > ticket_b (3 días atrás) > ticket_a (5 días atrás)
      expect(result_ids).to eq([ticket_c.id, ticket_b.id, ticket_a.id])
    end
  end
end
