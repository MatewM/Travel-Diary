# frozen_string_literal: true

# HTTP client for Gemini API using Faraday (already a transitive dependency).
# Sends a document (PDF or image) encoded in base64 and returns the raw text
# response from the model.

class GeminiClient
  PROMPT = <<~PROMPT.freeze
You are a data extraction specialist for a fiscal travel diary application.
Users upload airline boarding passes and QR code tickets to document their international
travel for tax residency purposes. Extracted data may be reviewed by fiscal authorities.
Precision over completeness: when in doubt, report low confidence rather than guessing.

--- HIERARCHY OF DATA SOURCES ---

1. PRIMARY (Visual Text): Extract all visible data (flight number, airports, date, passenger)
   from the printed text on the document. This is your source of truth.

2. SECONDARY (QR Code): Attempt to decode the QR string if present. Use the 3-digit
   Julian Day embedded in QR codes (BCBP boarding pass standard) to cross-validate the
   visual date (day + month only — Julian Day does NOT contain the year).
   If the QR is blurry or unreadable, ignore it entirely and rely 100% on visual text.

3. CONFLICTS: If visual text and QR data conflict on any field, prioritize the visual text
   but set confidence to "low" or "medium" for that field.

--- EXTRACTED FIELDS ---

Return ONLY valid JSON with no extra text:

{
  "flight_number": "string or null",
  "airline": "string or null",
  "departure_airport": "IATA 3-letter uppercase code or null",
  "arrival_airport": "IATA 3-letter uppercase code or null",
  "departure_country": "ISO 3166-1 alpha-2 code (2 uppercase letters) or null",
  "arrival_country": "ISO 3166-1 alpha-2 code (2 uppercase letters) or null",
  "flight_date": "YYYY-MM-DD format or null",
  "departure_time": "HH:MM format or null",
  "arrival_time": "HH:MM format or null",
  "passenger_name": "string or null",
  "year_requires_verification": true,
  "year_source": "explicit | weekday_match | metadata_match | estimated | unknown",
  "confidence": {
    "flight_number": "high|medium|low",
    "airline": "high|medium|low",
    "departure_airport": "high|medium|low",
    "arrival_airport": "high|medium|low",
    "departure_country": "high|medium|low",
    "arrival_country": "high|medium|low",
    "flight_date": "high|medium|low",
    "departure_time": "high|medium|low",
    "arrival_time": "high|medium|low"
  }
}

If a field is not clearly visible, return null and confidence "low".
Return ONLY the JSON object, nothing else.

--- AIRPORT & COUNTRY VALIDATION ---

CROSS-CHECK: For departure_airport and arrival_airport, verify that the 3-letter IATA code
matches the city or airport name printed on the document.
Examples: "Barcelona" → "BCN", "Madrid" → "MAD", "London Heathrow" → "LHR",
"Larnaca" → "LCA", "Paris CDG" → "CDG", "Dubai" → "DXB".

CORRECTION: If the IATA code is blurry or missing but the city/airport name is clearly
visible, use your internal knowledge to provide the correct IATA code and set confidence
to "medium" (inferred, not directly read).

MISMATCH: If the printed IATA code and the visible city/airport name do NOT match
according to official IATA standards, set confidence for that airport field to "low".

COUNTRIES: Derive departure_country and arrival_country as ISO 3166-1 alpha-2 codes
directly from the confirmed IATA airport code using your internal knowledge.
Examples: BCN/MAD → "ES", LHR/LGW → "GB", LCA → "CY", CDG/ORY → "FR",
DXB/AUH → "AE", FCO/MXP → "IT".
- If airport confidence is "high" → country confidence is "high".
- If airport confidence is "medium" → country confidence is "medium".
- If airport confidence is "low" or airport is null → set country to null and confidence "low".

--- STRICT CONFIDENCE RULES FOR flight_date (MAXIMUM PRIORITY — PREVENT HALLUCINATIONS) ---

CRITICAL: Boarding passes and QR codes very frequently omit the 4-digit year.
Day and month being clearly visible does NOT by itself justify confidence "high" or "medium".
The year must be independently confirmed. Apply these rules in strict priority order:

RULE 1 — EXPLICIT YEAR → confidence: "high"
  The complete date including the 4-digit year (e.g., 2025-03-15) is unambiguously
  printed or encoded in the document. No inference needed.
  → Set year_source: "explicit", year_requires_verification: false.

RULE 2 — METADATA CONFIRMATION → confidence: "high"
  ⚠ PREREQUISITE: This rule ONLY applies when a "--- FILE METADATA ---" block
  is explicitly present at the END of this prompt. If no such block exists,
  skip this rule entirely and proceed directly to Rule 3.
  When the block IS present: verify that the capture date is 0 to 3 days BEFORE
  the flight day+month you extracted. This is logically consistent with a user
  photographing their ticket just before departure.
  If the metadata date is AFTER the flight date, or the gap exceeds 7 days,
  this rule does NOT apply — treat metadata as unreliable.
  → Set year_source: "metadata_match", year_requires_verification: false.

RULE 3 — WEEKDAY + CALENDAR/ROUTE MATCH → confidence: "high"
  The year is not explicitly printed, but a weekday name IS visible on the document
  (e.g., FRI, FRIDAY, MON, MONDAY, LUNES, VIE, JUE, etc.) AND using calendar arithmetic
  and your knowledge of flight routes/schedules you can uniquely identify one specific year
  where that exact weekday falls on that day+month for this route.
  The match must be unambiguous — if two or more recent years are equally plausible,
  downgrade to "medium".
  → Set year_source: "weekday_match", year_requires_verification: false.

RULE 4 — YEAR ESTIMATED FROM CONTEXT → confidence: "medium"
  No explicit year, no weekday, no usable metadata. You estimate using available context:
  - This app documents past travel for fiscal records.
    The most probable year is the calendar year immediately preceding today (last year).
  - Use last year if consistent with available clues (route, airline, season).
  - If clues suggest ambiguity or point to a different year, downgrade to "low".
  → Set year_source: "estimated", year_requires_verification: true.

RULE 5 — NO YEAR EVIDENCE AT ALL → confidence: "low" (MANDATORY)
  No year visible, no weekday name, no usable metadata, no reliable inference possible.
  You MUST set confidence "low" for flight_date. You may still return a best-guess date
  (default to last year), but it must be marked low.
  → Set year_source: "unknown", year_requires_verification: true.

RULE 6 — METADATA CONTRADICTION OR AMBIGUITY → confidence: "low" or "medium"
  The provided metadata contradicts the visual date or creates logical ambiguity.
  Do not use metadata to boost confidence. Fall back to Rules 3–5.
  → Apply discretion based on severity of contradiction.

NEVER set flight_date confidence to "high" based solely on a visible day and month.
PROMPT

  def self.parse_document(filepath, mimetype, target_year: nil, capture_date: nil)
    if target_year || capture_date
      new.parse_document(filepath, mimetype, target_year: target_year, capture_date: capture_date)
    else
      new.parse_document(filepath, mimetype)
    end
  end

  def parse_document(filepath, mimetype, target_year: nil, capture_date: nil)
    encoded = Base64.strict_encode64(File.binread(filepath))

    body = {
      contents: [
        {
          parts: [
            { 
              text: build_prompt_with_metadata(target_year, capture_date)
            },
            {
              inline_data: {
                mime_type: mimetype,
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

  def build_prompt_with_metadata(target_year, capture_date)
    prompt_text = PROMPT.dup
    
    # Añadir contexto del año si está disponible
    if target_year
      prompt_text += "\n\nCONTEXT: TARGET_YEAR=#{target_year}. Use this year for any date where the year is not explicitly printed on the document."
    end
    
    # Añadir bloque FILE METADATA para activar RULE 2 si tenemos fecha de captura
    if capture_date
      capture_day_month = capture_date.strftime("%m-%d")  # Solo mes-día para comparación
      capture_year = capture_date.year
      prompt_text += "\n\n--- FILE METADATA (applies to RULE 2 above) ---\n" \
                     "Photo capture date (month-day only): #{capture_day_month}\n" \
                     "If the flight date falls within 0-3 days AFTER this capture month-day, set confidence 'high' for flight_date.\n" \
                     "Additionally, use #{capture_year} as the flight year with confidence 'high' since the photo was taken in #{capture_year}.\n" \
                     "This indicates the photo was taken just before or on the departure date, making the metadata reliable."
    end
    
    prompt_text
  end
end
