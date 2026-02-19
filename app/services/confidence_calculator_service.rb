# frozen_string_literal: true

class ConfidenceCalculatorService
  CRITICAL_FIELDS = %i[departure_airport arrival_airport departure_datetime arrival_datetime].freeze

  def self.call(parsed_data)
    new(parsed_data).call
  end

  def initialize(parsed_data)
    @data = parsed_data
  end

  def call
    issues = []

    # Signal 1: null critical fields
    CRITICAL_FIELDS.each do |field|
      issues << field if @data[field.to_s].nil?
    end

    # Signal 2: invalid IATA format
    %i[departure_airport arrival_airport].each do |field|
      val = @data[field.to_s]
      issues << field if val && val !~ /\A[A-Z]{3}\z/
    end

    # Signal 3: airport not found in DB
    %i[departure_airport arrival_airport].each do |field|
      val = @data[field.to_s]
      issues << field if val && !Airport.exists?(iata_code: val)
    end

    # Signal 4: incoherent dates (arrival before departure)
    dep = @data["departure_datetime"]
    arr = @data["arrival_datetime"]
    if dep && arr
      begin
        issues << :arrival_datetime if Time.parse(arr) < Time.parse(dep)
      rescue ArgumentError
        issues << :departure_datetime
        issues << :arrival_datetime
      end
    end

    # Signal 5: low confidence declared by Gemini itself
    @data["confidence"]&.each do |field, level|
      issues << field.to_sym if level == "low"
    end

    issues.uniq!

    if issues.empty?
      { level: :high,   status: :auto_verified,  issues: [] }
    elsif issues.count <= 2
      { level: :medium, status: :needs_review,    issues: issues }
    else
      { level: :low,    status: :manual_required, issues: issues }
    end
  end
end
