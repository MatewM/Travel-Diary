#coding:UTF-8
_erbout = +'';  _issues    = local_assigns.fetch(:issues, []) ; _erbout.<< "\n".freeze
;  year_source = local_assigns.fetch(:year_source, nil) ; _erbout.<< "\n".freeze
; 
  # Forzamos el uso de variables locales, con fallback a las del controlador si existen
  ticket = local_assigns.fetch(:ticket, @ticket)
  issues = local_assigns.fetch(:issues, @issues || []).map(&:to_sym)
  airports = local_assigns.fetch(:airports, @airports || [])
_erbout.<< "\n".freeze
; _erbout.<<(( turbo_frame_tag "modal" do ).to_s); _erbout.<< "\n    <div data-controller=\"modal\">\n      <div class=\"fixed inset-0 z-50 flex items-center justify-center p-4\">\n\n    ".freeze



; 

























; _erbout.<< "\n        ".freeze
; 
          year_msgs = {
            "estimated"     => "El año del vuelo fue estimado automáticamente. Por favor verifica que es correcto.",
            "unknown"       => "No fue posible determinar el año con certeza. Introduce la fecha completa.",
            "weekday_match" => "El año fue deducido por el día de la semana. Por favor confírmalo.",
            "metadata_match"=> nil,
            "explicit"      => nil
          }
          year_msg = year_source.present? ? year_msgs[year_source] : nil
        ; _erbout.<< "\n        <div class=\"mx-6 mt-4 p-3 bg-amber-50 border border-amber-200 rounded-lg space-y-1\">\n          <p class=\"text-xs font-semibold text-amber-800 flex items-center gap-1.5\">\n            \xE2\x9A\xA0 Revisa los campos marcados en amarillo \xE2\x80\x94 la IA no pudo leerlos con certeza.\n          </p>\n          ".freeze




;  if year_msg.present? && _issues.include?(:departure_datetime) ; _erbout.<< "\n            <p class=\"text-xs text-amber-700\">".freeze
; _erbout.<<(( year_msg ).to_s); _erbout.<< "</p>\n          ".freeze
;  end ; _erbout.<< "\n        </div>\n      ".freeze

;  end ; _erbout.<< "\n\n      ".freeze

; ; _erbout.<< "\n      <div class=\"grid grid-cols-1 md:grid-cols-2 gap-0\">\n\n        ".freeze


; ; _erbout.<< "\n        ".freeze
;  first_file = ticket.original_files.first ; _erbout.<< "\n        <div class=\"p-4 border-b md:border-b-0 md:border-r border-slate-100 flex flex-col items-center justify-center bg-slate-50 rounded-bl-2xl min-h-96\">\n          ".freeze

;  if first_file ; _erbout.<< "\n            ".freeze
;  if first_file.content_type.in?(%w[image/jpeg image/png]) ; _erbout.<< "\n              ".freeze
; _erbout.<<(( image_tag rails_blob_path(first_file, disposition: "inline"),
                    alt: first_file.filename.to_s,
                    class: "max-h-[32rem] w-full rounded-lg shadow object-contain" ).to_s); _erbout.<< "\n            ".freeze
;  else ; _erbout.<< "\n              ".freeze
; ; _erbout.<< "\n              <div class=\"w-24 h-28 bg-red-100 rounded-xl flex flex-col items-center justify-center shadow-sm\">\n                <svg class=\"w-10 h-10 text-red-400 mb-2\" fill=\"currentColor\" viewBox=\"0 0 24 24\">\n                  <path d=\"M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6z\"/>\n                </svg>\n                <span class=\"text-xs font-bold text-red-500 uppercase tracking-wide\">PDF</span>\n              </div>\n              <p class=\"text-xs text-slate-500 mt-3 text-center break-all max-w-full px-2\">\n                ".freeze







; _erbout.<<(( first_file.filename ).to_s); _erbout.<< "\n              </p>\n            ".freeze

;  end ; _erbout.<< "\n          ".freeze
;  else ; _erbout.<< "\n            <p class=\"text-sm text-slate-400\">Sin archivo adjunto</p>\n          ".freeze

;  end ; _erbout.<< "\n        </div>\n\n        ".freeze


; ; _erbout.<< "\n        <div class=\"p-6\">\n          ".freeze

; _erbout.<<(( form_with model: ticket,
                url: ticket_path(ticket),
                method: :patch,
                data: { turbo_frame: "_top" },
                class: "space-y-4" do |f| ).to_s); _erbout.<< "\n\n            ".freeze

; ; _erbout.<< "\n            ".freeze
;  if ticket.errors.any? ; _erbout.<< "\n              <div class=\"p-3 mb-4 rounded-lg bg-red-50 text-red-700 text-sm\">\n                \xE2\x9A\xA0\xEF\xB8\x8F ".freeze

; _erbout.<<(( ticket.errors.full_messages.to_sentence ).to_s); _erbout.<< "\n              </div>\n            ".freeze

;  end ; _erbout.<< "\n\n            ".freeze

; ; _erbout.<< "\n            ".freeze
;  def field_classes(field_name, _issues)
                 _issues.include?(field_name.to_s) ?
                   "border-amber-400 bg-amber-50 focus:ring-amber-300" :
                   "border-emerald-300 bg-white focus:ring-emerald-200"
               end ; _erbout.<< "\n            ".freeze
;  def field_icon(field_name, _issues)
                 _issues.include?(field_name.to_s) ? "⚠️" : "✓"
               end ; _erbout.<< "\n\n            ".freeze

; ; _erbout.<< "\n            <div>\n              ".freeze

; _erbout.<<(( f.label :flight_number, "Número de vuelo", class: "block text-xs font-medium text-slate-600 mb-1" ).to_s); _erbout.<< "\n              <div class=\"flex items-center gap-2\">\n                ".freeze

; _erbout.<<(( f.text_field :flight_number,
                      class: "flex-1 rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-2 transition #{field_classes(:flight_number, issues)}",
                      placeholder: "ej. IB3456" ).to_s); _erbout.<< "\n                <span class=\"text-base\">".freeze
; _erbout.<<(( field_icon(:flight_number, issues) ).to_s); _erbout.<< "</span>\n              </div>\n            </div>\n\n            ".freeze



; ; _erbout.<< "\n            <div>\n              ".freeze

; _erbout.<<(( f.label :airline, "Aerolínea", class: "block text-xs font-medium text-slate-600 mb-1" ).to_s); _erbout.<< "\n              <div class=\"flex items-center gap-2\">\n                ".freeze

; _erbout.<<(( f.text_field :airline,
                      class: "flex-1 rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-2 transition #{field_classes(:airline, issues)}",
                      placeholder: "ej. Iberia" ).to_s); _erbout.<< "\n                <span class=\"text-base\">".freeze
; _erbout.<<(( field_icon(:airline, issues) ).to_s); _erbout.<< "</span>\n              </div>\n            </div>\n\n            ".freeze



; ; _erbout.<< "\n            <div class=\"grid grid-cols-2 gap-3\">\n              <div>\n                ".freeze


; _erbout.<<(( f.label :departure_airport, "Origen (IATA)", class: "block text-xs font-medium text-slate-600 mb-1" ).to_s); _erbout.<< "\n                <div class=\"flex items-center gap-1\">\n                  ".freeze

; _erbout.<<(( f.text_field :departure_airport,
                        list: "airports_datalist",
                        maxlength: 3,
                        class: "flex-1 rounded-lg border px-3 py-2 text-sm uppercase focus:outline-none focus:ring-2 transition #{field_classes(:departure_airport, issues)}",
                        placeholder: "MAD" ).to_s); _erbout.<< "\n                  <span class=\"text-sm\">".freeze
; _erbout.<<(( field_icon(:departure_airport, issues) ).to_s); _erbout.<< "</span>\n                </div>\n              </div>\n              <div>\n                ".freeze



; _erbout.<<(( f.label :arrival_airport, "Destino (IATA)", class: "block text-xs font-medium text-slate-600 mb-1" ).to_s); _erbout.<< "\n                <div class=\"flex items-center gap-1\">\n                  ".freeze

; _erbout.<<(( f.text_field :arrival_airport,
                        list: "airports_datalist",
                        maxlength: 3,
                        class: "flex-1 rounded-lg border px-3 py-2 text-sm uppercase focus:outline-none focus:ring-2 transition #{field_classes(:arrival_airport, issues)}",
                        placeholder: "LHR" ).to_s); _erbout.<< "\n                  <span class=\"text-sm\">".freeze
; _erbout.<<(( field_icon(:arrival_airport, issues) ).to_s); _erbout.<< "</span>\n                </div>\n              </div>\n            </div>\n\n            ".freeze




; ; _erbout.<< "\n            <datalist id=\"airports_datalist\">\n              ".freeze

;  airports.each do |airport| ; _erbout.<< "\n                <option value=\"".freeze
; _erbout.<<(( airport.iata_code ).to_s); _erbout.<< "\">".freeze; _erbout.<<(( airport.iata_code ).to_s); _erbout.<< " \xE2\x80\x93 ".freeze; _erbout.<<(( airport.name ).to_s); _erbout.<< "</option>\n              ".freeze
;  end ; _erbout.<< "\n            </datalist>\n\n            ".freeze


; ; _erbout.<< "\n            <div>\n              ".freeze

; _erbout.<<(( f.label :departure_datetime, "Salida", class: "block text-xs font-medium text-slate-600 mb-1" ).to_s); _erbout.<< "\n              <div class=\"flex items-center gap-2\">\n                ".freeze

; _erbout.<<(( f.datetime_local_field :departure_datetime, required: false,
                      class: "flex-1 rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-2 transition #{field_classes(:departure_datetime, issues)}" ).to_s); _erbout.<< "\n                <span class=\"text-base\">".freeze
; _erbout.<<(( field_icon(:departure_datetime, issues) ).to_s); _erbout.<< "</span>\n              </div>\n            </div>\n\n            ".freeze



; ; _erbout.<< "\n            <div>\n              ".freeze

; _erbout.<<(( f.label :arrival_datetime, "Llegada", class: "block text-xs font-medium text-slate-600 mb-1" ).to_s); _erbout.<< "\n              <div class=\"flex items-center gap-2\">\n                ".freeze

; _erbout.<<(( f.datetime_local_field :arrival_datetime, required: false,
                      class: "flex-1 rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-2 transition #{field_classes(:arrival_datetime, issues)}" ).to_s); _erbout.<< "\n                <span class=\"text-base\">".freeze
; _erbout.<<(( field_icon(:arrival_datetime, issues) ).to_s); _erbout.<< "</span>\n              </div>\n            </div>\n\n            ".freeze



; ; _erbout.<< "\n            <div class=\"flex justify-end gap-3 pt-2 border-t border-slate-100\">\n              <button type=\"button\"\n                      data-action=\"click->modal#close\"\n                      class=\"border border-slate-200 text-slate-700 rounded-lg px-4 py-2 text-sm font-medium hover:bg-slate-50 transition-colors\">\n                Cancelar\n              </button>\n              ".freeze






; _erbout.<<(( f.submit "Confirmar y guardar",
                    class: "bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg px-4 py-2
                            text-sm font-medium transition-colors cursor-pointer" ).to_s); _erbout.<< "\n            </div>\n\n          ".freeze


;  end ; _erbout.<< "\n        </div>\n\n      </div>\n    </div>\n    </div>\n".freeze





;  end ; _erbout.<< "\n".freeze
; _erbout