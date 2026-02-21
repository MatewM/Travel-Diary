# frozen_string_literal: true

# HTTP client for Gemini API using Faraday (already a transitive dependency).
# Sends a document (PDF or image) encoded in base64 and returns the raw text
# response from the model.

class GeminiClient
  PROMPT = <<~PROMPT.freeze
Act as an expert aviation data extractor specialized in boarding passes and the IATA BCBP standard. Your task is to analyze the provided image and return ONLY a valid JSON object.

CRITICAL EXTRACTION & DATE LOGIC RULES:
1. QR DECODING: Locate the raw text string from the QR code. Extract the "Julian Day" (3-digit format) and use it as the technical baseline for the flight date.
2. VISUAL CROSS-CHECK: Compare the Julian Day from the QR with the printed date (day/month) visible on the ticket. If they match, set confidence to "high".
3. YEAR DEDUCTION (YEAR MISSING PROBLEM): 
   - If the year is not explicitly printed, look for the day of the week (e.g., 'Friday 15 Jul','FRI 15 jul, etc...). Calculate the most likely recent year where that date/day combination exists.
   - Use any provided metadata (e.g., image capture date) to infer the correct year.
   - If the year remains uncertain after these steps, set 'can_search_flight' to true and set the year part of 'flight_date' or the entire field to null.
4. SEARCH STATUS: 'can_search_flight' must be true if the year is uncertain or flight date is missing, or if data requires external validation.

REQUIRED JSON SCHEMA:
{
  "flight_number": "IATA Airline Code + Number (e.g., IB3456) or null",
  "airline": "Airline name string or null",
  "departure_airport": "3-letter IATA code or null",
  "arrival_airport": "3-letter IATA code or null",
  "flight_date": "YYYY-MM-DD or null",
  "arrival_time": "HH:MM or null",
  "passenger_name": "Full name string or null",
  "can_search_flight": boolean,
  "confidence": {
    "flight_number": "high|medium|low",
    "airline": "high|medium|low",
    "departure_airport": "high|medium|low",
    "arrival_airport": "high|medium|low",
    "flight_date": "high|medium|low",
    "arrival_time": "high|medium|low",
    "passenger_name": "high|medium|low"
  }
}

FINAL INSTRUCTION: Do not include Markdown tags (like ```json), explanatory text, or code blocks. Return only the raw, parseable JSON object.
PROMPT

  
  def self.parse_document(file_path, mime_type, capture_date = nil)
    new.parse_document(file_path, mime_type)
  end

  def parse_document(file_path, mime_type, capture_date = nil)
    encoded = Base64.strict_encode64(File.binread(file_path))

    body = {
      contents: [
        {
          parts: [
            { text: build_prompt_with_metadata(capture_date) },
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

    endpoint_path = "/v1beta/models/#{Gemini::MODEL}:generateContent"
    full_request_url = "#{Gemini::BASE_URL}#{endpoint_path}" # Definir aquí para acceso global en el método

    # #region agent log H1/H2/H3/H4/H5/H6
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
          full_url: full_request_url, # Ahora accesible
          body_size: body.to_json.length,
          api_key_in_header: true
        },
        timestamp: Time.now.to_i
      }.to_json)
      f.flush # Asegurar que se escribe inmediatamente
    end
    # #endregion

    # Añado un log justo antes de la llamada HTTP para ver la URL exacta y el cuerpo
    Rails.logger.debug do
      {
        message: "Calling Gemini API",
        full_url: full_request_url,
        request_body: body.to_json,
        timestamp: Time.current.iso8601
      }.to_json
    end

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
      f.flush # Asegurar que se escribe inmediatamente
    end
    # #endregion

    unless response.success?
      case response.status
      when 400
        raise "❌ SOLICITUD INVÁLIDA - Los datos enviados a Gemini no son válidos. Verifica el formato del archivo."
      when 401
        raise "🔐 ERROR DE AUTENTICACIÓN - La clave API de Gemini no es válida o ha expirado."
      when 403
        raise "🚫 ACCESO DENEGADO - No tienes permisos para usar Gemini o has excedido el límite de uso."
      when 404
        raise "🔍 MODELO NO ENCONTRADO - El modelo de Gemini especificado no existe."
      when 429
        raise "⏱️ LÍMITE EXCEDIDO - Has hecho demasiadas solicitudes a Gemini. Espera antes de reintentar."
      when 500
        raise "💥 ERROR INTERNO DE GEMINI - Problema temporal en los servidores de Google."
      when 503
        raise "🚨 SERVIDOR GEMINI SATURADO - El servicio de Google Gemini está experimentando alta demanda durante hora punta. Este es un problema temporal del proveedor, no de tu aplicación. El sistema reintentará automáticamente en breve."
      else
        raise "❓ ERROR DESCONOCIDO DE GEMINI (#{response.status}): #{response.body}"
      end
    end

    # Verificar que la respuesta tenga contenido
    raise "Gemini API returned empty response body" if response.body.blank?

    begin
      response_data = JSON.parse(response.body)

      # Extraer el texto de diferentes posibles estructuras de respuesta
      candidates = response_data.dig("candidates", 0, "content", "parts", 0, "text") ||
                   response_data.dig("candidates", 0, "content", "parts", 0, "inline_data") ||
                   response_data.dig("candidates", 0, "text") ||
                   response_data.dig("text")

      raise "Gemini returned empty or invalid response structure" if candidates.blank?

      # Strip potential markdown code fences that the model sometimes adds despite the prompt
      candidates.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
    rescue JSON::ParserError => e
      raise "Failed to parse Gemini API response: #{e.message}. Response body: #{response.body[0..500]}..."
    end
  end

  private

  def build_prompt_with_metadata(capture_date)
    dynamic_prompt = PROMPT.dup
    if capture_date.present?
      "Metadata: La fecha de captura de esta imagen es: #{capture_date}. Utiliza esta información para inferir el año de la fecha del vuelo si no es visible.\n\n" + dynamic_prompt
    else
      dynamic_prompt
    end
  end

  private

  def connection
    # Nueva conexión cada vez para evitar problemas con conexiones reutilizadas
    Faraday.new(url: Gemini::BASE_URL) do |f|
      f.options.timeout      = 20 # Reducido de 45s para fallar más rápido
      f.options.open_timeout = 5  # Reducido de 10s para conexiones TCP
      f.options.read_timeout = 50 # Reducido de 35s para leer respuesta

      # Evitar conexiones TCP persistentes que se cierran por inactividad
      f.adapter Faraday.default_adapter
      f.headers['Connection'] = 'close'
    end
  end

  def api_key
    api_key = Rails.application.credentials.dig(:gemini, :api_key)
    raise "GEMINI_API_KEY not configured" unless api_key.present?
    api_key
  end
end
