# frozen_string_literal: true

# HTTP client for Gemini API using Faraday (already a transitive dependency).
# Sends a document (PDF or image) encoded in base64 and returns the raw text
# response from the model.

module Gemini
  BASE_URL = "https://generativelanguage.googleapis.com".freeze
  MODEL = "gemini-2.0-flash".freeze
  TIMEOUT = 30.seconds.freeze
end
class GeminiClient
  PROMPT = <<~PROMPT.freeze
    You are an expert at extracting data from airline boarding passes and tickets.
    Extract the following fields and return ONLY valid JSON, no extra text:
    {
      "flight_number": "string or null",
      "airline": "string or null",
      "departure_airport": "IATA 3-letter uppercase code or null",
      "arrival_airport": "IATA 3-letter uppercase code or null",
      "departure_datetime": "ISO 8601 format or null",
      "arrival_datetime": "ISO 8601 format or null",
      "passenger_name": "string or null",
      "confidence": {
        "flight_number": "high|medium|low",
        "airline": "high|medium|low",
        "departure_airport": "high|medium|low",
        "arrival_airport": "high|medium|low",
        "departure_datetime": "high|medium|low",
        "arrival_datetime": "high|medium|low"
      }
    }
    If a field is not clearly visible, return null and confidence "low".
    Return ONLY the JSON object, nothing else.
  PROMPT

  
  def self.parse_document(file_path, mime_type)
    new.parse_document(file_path, mime_type)
  end

  def parse_document(file_path, mime_type)
    encoded = Base64.strict_encode64(File.binread(file_path))

    body = {
      contents: [
        {
          parts: [
            { text: PROMPT },
            {
              inline_data: {
                mime_type: mime_type,
                data: encoded
              }
            }
          ]
        }
      ]
    }

    # #region agent log H2/H4/H5
    key = begin; api_key; rescue => e; "ERROR:#{e.message}"; end
    _ep = "/models/#{Gemini::MODEL}:generateContent?key=REDACTED"
    File.open("/home/phunna/.cursor/debug-4050d7.log", "a") do |f|
      f.puts({ sessionId: "4050d7", hypothesisId: "H2/H4/H5", location: "gemini_client.rb:pre_request",
               message: "About to call Gemini",
               data: { model: Gemini::MODEL, base_url: Gemini::BASE_URL, full_endpoint: _ep,
                       key_present: key != "ERROR:GEMINI_API_KEY not configured" && key.present?,
                       key_prefix: key.to_s[0, 8] }, timestamp: Time.now.to_i }.to_json)
    end
    # #endregion

    response = connection.post(endpoint, body.to_json, "Content-Type" => "application/json")

    # #region agent log H1/H3
    File.open("/home/phunna/.cursor/debug-4050d7.log", "a") do |f|
      f.puts({ sessionId: "4050d7", hypothesisId: "H1/H3", location: "gemini_client.rb:post_request",
               message: "Gemini response received",
               data: { status: response.status, body_length: response.body.to_s.length,
                       body_preview: response.body.to_s[0, 500] }, timestamp: Time.now.to_i }.to_json)
    end
    # #endregion

    raise "Gemini API error #{response.status}: #{response.body}" unless response.success?

    candidates = JSON.parse(response.body).dig("candidates", 0, "content", "parts", 0, "text")
    raise "Gemini returned empty response" if candidates.blank?

    # Strip potential markdown code fences that the model sometimes adds despite the prompt
    candidates.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
  end

  private

  def connection
    @connection ||= Faraday.new(url: Gemini::BASE_URL) do |f|
      f.options.timeout      = 30
      f.options.open_timeout = 30

           f.adapter Faraday.default_adapter
    end
  end

  def endpoint
    "/v1beta/models/#{Gemini::MODEL}:generateContent?key=#{api_key}"
  end
  
  def api_key
    api_key = Rails.application.credentials.dig(:gemini, :api_key)
    raise "GEMINI_API_KEY not configured" unless api_key.present?
    api_key
  end
end
