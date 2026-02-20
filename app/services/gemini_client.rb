# frozen_string_literal: true

# HTTP client for Gemini API using Faraday (already a transitive dependency).
# Sends a document (PDF or image) encoded in base64 and returns the raw text
# response from the model.

class GeminiClient
  PROMPT = <<~PROMPT.freeze
  Extract data from this airline boarding pass or ticket.
  Return ONLY valid JSON, no extra text:
  {
    "flight_number": "airline IATA code + number e.g. IB3456, or null",
    "airline": "string or null",
    "departure_airport": "IATA 3-letter uppercase code or null",
    "arrival_airport": "IATA 3-letter uppercase code or null",
    "flight_date": "date in YYYY-MM-DD format or null",
    "arrival_time": "HH:MM in local time or null",
    "passenger_name": "string or null",
    "confidence": {
      "flight_number": "high|medium|low",
      "departure_airport": "high|medium|low",
      "arrival_airport": "high|medium|low",
      "flight_date": "high|medium|low"
    }
  }
  Separate date and time fields - they are easier to read independently.
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

    # #region agent log H1/H2/H3/H4/H5/H6
    endpoint_path = "/v1beta/models/#{Gemini::MODEL}:generateContent"
    File.open("/home/phunna/.cursor/debug-ad4598.log", "a") do |f|
      f.puts({
        sessionId: "ad4598",
        runId: "run5", # Probando con modelo gemini-2.0-flash
        hypothesisId: "endpoint_issue", # Problema con la construcción del endpoint
        location: "gemini_client.rb:pre_request_debug",
        message: "Full Gemini API call details",
        data: {
          model_constant: "gemini-2.5-flash",
          base_url_constant: Gemini::BASE_URL,
          api_key_present: Rails.application.credentials.dig(:gemini, :api_key).present?,
          generated_endpoint: endpoint_path,
          full_url: "#{Gemini::BASE_URL}#{endpoint_path}",
          body_size: body.to_json.length,
          api_key_in_header: true
        },
        timestamp: Time.now.to_i
      }.to_json)
    end
    # #endregion

    response = connection.post(endpoint_path, body.to_json, {
      "Content-Type" => "application/json",
      "x-goog-api-key" => api_key
    })

    # #region agent log - Response details
    File.open("/home/phunna/.cursor/debug-ad4598.log", "a") do |f|
      f.puts({
        sessionId: "ad4598",
        runId: "run5",
        hypothesisId: "response_analysis",
        location: "gemini_client.rb:post_response",
        message: "Gemini API response details",
        data: {
          status_code: response.status,
          response_body: response.body,
          response_headers: response.headers.to_h,
          full_url: "#{Gemini::BASE_URL}#{endpoint_path}"
        },
        timestamp: Time.now.to_i
      }.to_json)
    end
    # #endregion

    unless response.success?
      if response.status == 503
        raise "🚨 SERVIDOR GEMINI SATURADO - El servicio de Google Gemini está experimentando alta demanda durante hora punta. Este es un problema temporal del proveedor, no de tu aplicación. El sistema reintentará automáticamente en breve."
      else
        raise "Gemini API error #{response.status}: #{response.body}"
      end
    end

    candidates = JSON.parse(response.body).dig("candidates", 0, "content", "parts", 0, "text")
    raise "Gemini returned empty response" if candidates.blank?

    # Strip potential markdown code fences that the model sometimes adds despite the prompt
    candidates.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
  end

  private

  def connection
    # Nueva conexión cada vez para evitar problemas con conexiones reutilizadas
    Faraday.new(url: Gemini::BASE_URL) do |f|
      f.options.timeout      = 45 # Sincronizado con config/initializers/gemini.rb
      f.options.open_timeout = 10 # Reducido para conexiones TCP
      f.options.read_timeout = 35 # Tiempo específico para leer respuesta

      # Evitar conexiones TCP persistentes que se cierran por inactividad
      f.adapter Faraday.default_adapter
      f.headers['Connection'] = 'close'
    end
  end

  def endpoint
    "/v1beta/models/gemini-2.5-flash:generateContent"
  end
  
  def api_key
    api_key = Rails.application.credentials.dig(:gemini, :api_key)
    raise "GEMINI_API_KEY not configured" unless api_key.present?
    api_key
  end
end
