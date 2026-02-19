# Lógica de Negocio — TaxDays

## 1. Parsing de Billetes (ParseTicketService)

### Tecnología elegida
Google Gemini 2.0 Flash API (free tier: 1500 req/día)
- Gem a usar: `ruby-gemini-ai` o llamada HTTP directa con Faraday
- Soporta PDF e imágenes (JPG, PNG) nativamente
- Devuelve JSON estructurado

### Pseudocódigo

ParseTicketService.call(ticket_id)

ticket = Ticket.find(ticket_id)
archivo = ticket.original_file # ActiveStorage attachment

SI archivo es PDF:
contenido = convertir a base64
mime_type = "application/pdf"
SI archivo es imagen:
contenido = convertir a base64
mime_type = "image/jpeg" o "image/png"

prompt = """
Eres un asistente experto en billetes de avión.
Extrae los siguientes datos del billete adjunto y devuelve SOLO un JSON válido:
{
"flight_number": "string o null",
"airline": "string o null",
"departure_airport": "código IATA 3 letras mayúsculas o null",
"arrival_airport": "código IATA 3 letras mayúsculas o null",
"departure_datetime": "ISO 8601 o null",
"arrival_datetime": "ISO 8601 o null",
"passenger_name": "string o null"
}
Si no encuentras un dato, devuelve null para ese campo.
Devuelve SOLO el JSON, sin texto adicional.
"""

respuesta = llamar Gemini API con (prompt + archivo en base64)

SI respuesta es JSON válido:
datos = parsear JSON

# Buscar países por código IATA
departure_country = Airport.find_by(iata_code: datos.departure_airport)&.country
arrival_country   = Airport.find_by(iata_code: datos.arrival_airport)&.country

ticket.update(
  flight_number:        datos.flight_number,
  airline:              datos.airline,
  departure_airport:    datos.departure_airport,
  arrival_airport:      datos.arrival_airport,
  departure_datetime:   datos.departure_datetime,
  arrival_datetime:     datos.arrival_datetime,
  departure_country:    departure_country,
  arrival_country:      arrival_country,
  status:               :parsed,
  parsed_data:          respuesta_cruda  # guardar para debugging
)
return { success: true, ticket: ticket }
SI respuesta es inválida o timeout (>30s):
ticket.update(status: :error)
return { success: false, error: "No se pudo extraer información del billete" }

### Casos de error a manejar
- Archivo corrupto o ilegible → status: :error, mensaje al usuario
- Aeropuerto no encontrado en BD → guardar código IATA, marcar país como nil, pedir revisión manual
- Fecha en formato ambiguo → intentar parsear, si falla → nil, pedir revisión manual
- Gemini API no disponible → reintentar 2 veces con backoff, luego status: :error

---

## 2. Detección de Billetes Duplicados (DuplicateTicketDetector)

### Cuándo ejecutarlo
- Siempre después de ParseTicketService antes de guardar definitivamente

### Pseudocódigo

DuplicateTicketDetector.call(ticket)

candidatos = Ticket.where(user: ticket.user)
.where(status: [:parsed, :manual])
.where(departure_airport: ticket.departure_airport)
.where(arrival_airport: ticket.arrival_airport)
.where(departure_datetime: rango ±2 horas)
.where.not(id: ticket.id)

SI candidatos.any?
return { duplicate: true, conflicting_ticket: candidatos.first }
SINO
return { duplicate: false }

---

## 3. Cálculo de Días por País (DaysInCountryService)

### Explicación en lenguaje natural
Dado un usuario, un país y un año, recorre todos sus viajes cuyo
destino sea ese país y calcula cuántos días de ese año pasó allí.
Tiene en cuenta viajes que empezaron el año anterior y terminaron
en el año consultado.

### Pseudocódigo

DaysInCountryService.call(user:, country:, year:)

año_inicio = Date.new(year, 1, 1)
año_fin = Date.new(year, 12, 31)

Trips con destino = país buscado, ordenados por fecha llegada
trips = user.trips
.where(destination_country: country)
.order(:arrival_date)

total_dias = 0

PARA CADA trip EN trips:

# Fecha en que empieza a contar en este país (llegada o 1 enero)
inicio_efectivo = [trip.arrival_date, año_inicio].max

# Buscar cuándo salió: departure_date del siguiente viaje del usuario
siguiente_trip = user.trips
                     .where("departure_date > ?", trip.arrival_date)
                     .order(:departure_date)
                     .first

SI siguiente_trip existe:
  fin_en_pais = siguiente_trip.departure_date - 1.day
SINO:
  fin_en_pais = año_fin  # sigue en el país hasta fin de año

# Cortar al rango del año consultado
fin_efectivo = [fin_en_pais, año_fin].min

# Solo sumar si el rango cae dentro del año
SI fin_efectivo >= inicio_efectivo:
  total_dias += (fin_efectivo - inicio_efectivo).to_i + 1
return total_dias

---

## 4. Detección de Conflictos (ConflictDetectorService)

### Tipos de conflictos a detectar

ConflictDetectorService.call(user:, year:)
conflictos = []

trips_del_año = user.trips ordenados por departure_date

PARA CADA par (trip_a, trip_b) consecutivos:

# Conflicto 1: solapamiento de fechas (imposible estar en dos sitios)
SI trip_b.arrival_date < trip_a fin_en_pais calculado:
  conflictos << {
    tipo: :overlap,
    mensaje: "Fechas solapadas entre viaje a #{trip_a.destination} y #{trip_b.destination}",
    trips: [trip_a, trip_b]
  }

# Conflicto 2: hueco entre viajes (días sin registrar)
SI hay días entre fin de trip_a y inicio de trip_b:
  conflictos << {
    tipo: :gap,
    fecha_inicio: fin_trip_a + 1.day,
    fecha_fin: trip_b.arrival_date - 1.day,
    dias: diferencia en días
  }
return conflictos

---

## 5. Vista del Dashboard (DashboardPresenter)

### Explicación en lenguaje natural
El dashboard muestra una tabla del año seleccionado con TODAS las
filas: trips registrados + huecos sin registrar. La primera fila
del año puede venir de un viaje del año anterior.

### Pseudocódigo

DashboardPresenter.build(user:, year:)

año_inicio = Date.new(year, 1, 1)
año_fin = Date.new(year, 12, 31)

filas = []

CASO ESPECIAL: ¿Había un viaje activo al inicio del año?
(viaje que llegó antes del 1 enero y aún no había partido)
viaje_previo = user.trips
.where("arrival_date < ?", año_inicio)
.where(destination_country: cualquiera)
.order(arrival_date: :desc)
.first

SI viaje_previo existe Y no hay un trip que salga antes del año_inicio + llegue después:
# Primera fila: ese país desde el 1 de enero
siguiente = primer trip del año del usuario
fin = siguiente ? siguiente.departure_date - 1 : año_fin
filas << {
tipo: :trip_heredado,
pais: viaje_previo.destination_country,
fecha_inicio: año_inicio,
fecha_fin: [fin, año_fin].min,
tiene_billete: viaje_previo.has_boarding_pass,
trip_id: viaje_previo.id
}

Resto de trips del año
trips_del_año = user.trips ordenados por arrival_date del año

fecha_cursor = primer trip o año_inicio

PARA CADA trip EN trips_del_año:

# Añadir fila de HUECO si hay días sin cubrir antes de este trip
SI trip.arrival_date > fecha_cursor:
  filas << {
    tipo: :gap,
    fecha_inicio: fecha_cursor,
    fecha_fin: trip.arrival_date - 1.day,
    dias: diferencia,
    accion: "añadir_periodo"
  }

# Calcular fin en este país
siguiente = siguiente trip del usuario
fin_en_pais = siguiente ? siguiente.departure_date - 1 : año_fin

filas << {
  tipo: :trip,
  pais: trip.destination_country,
  fecha_inicio: trip.arrival_date,
  fecha_fin: [fin_en_pais, año_fin].min,
  dias: calcular con DaysInCountryService,
  tiene_billete: trip.has_boarding_pass,
  manual: trip.manually_entered,
  trip_id: trip.id
}

fecha_cursor = fin_en_pais + 1.day
Hueco al final del año si no cubre hasta el 31/12
SI fecha_cursor <= año_fin:
filas << { tipo: :gap, fecha_inicio: fecha_cursor, fecha_fin: año_fin }

return filas

---

## 6. Alertas Fiscales (FiscalAlertService)

FiscalAlertService.call(user:, year:)
alertas = []

PARA CADA country EN todos los países donde el usuario tiene trips ese año:
dias = DaysInCountryService.call(user, country, year)

SI dias > 183:
  alertas << { nivel: :danger, pais: country, dias: dias,
               mensaje: "Llevas #{dias} días en #{country.name}. Superas el límite de 183." }

SI dias > 150 Y dias <= 183:
  alertas << { nivel: :warning, pais: country, dias: dias,
               mensaje: "Atención: llevas #{dias} días en #{country.name}. Te quedan #{183 - dias} días." }

SI country.min_days_required.present?:
  dias_restantes_año = (Date.new(year,12,31) - Date.today).to_i
  SI dias < country.min_days_required Y (dias + dias_restantes_año) >= country.min_days_required:
    alertas << { nivel: :info, pais: country,
                 mensaje: "Necesitas #{country.min_days_required - dias} días más en #{country.name} para residencia fiscal." }
return alertas

---

## 7. Generación del Informe Fiscal (GenerateFiscalReportService)

GenerateFiscalReportService.call(user:, year:)

filas_dashboard = DashboardPresenter.build(user, year)
alertas = FiscalAlertService.call(user, year)

Para cada fila con billete, obtener URL firmada del archivo
PARA CADA fila EN filas_dashboard donde tiene_billete = true:
ticket = Trip.find(fila.trip_id).tickets.with_attached_file.first
fila.archivo_url = Rails.application.routes.url_helpers
.rails_blob_url(ticket.original_file)

Generar PDF con:
1. Cabecera: nombre usuario, año, fecha generación
2. Tabla de días por país (trips + gaps marcados)
3. Sección de alertas si existen
4. Anexo: lista de billetes con thumbnail/link por cada trip
5. Nota al pie: "Períodos sin justificante" listados claramente
Gem recomendada: Prawn o WickedPDF
generar_pdf(datos)

---

## 8. AssignTicketToTripService — Regla de escalas

Criterio para determinar si una parada intermedia crea un Trip propio
o se trata como escala (transit day) sin impacto fiscal:

REGLA: Una parada en un país intermedio NO crea un Trip si:
  1. El usuario permanece en zona airside (tránsito internacional), Y
  2. El tiempo entre arrival_datetime del ticket entrante y
     departure_datetime del ticket saliente es < 24 horas

Si cualquiera de las dos condiciones se incumple → crear Trip intermedio.

Base legal:
- Modelo Convenio OCDE art. 15, Comentario 5: solo se computa presencia
  efectiva acreditada documentalmente (paso por inmigración).
- HMRC Statutory Residence Test (RFIG20730): el tránsito airside
  no cuenta como día en el país.
- Principio general: la presencia en zona internacional aeroportuaria
  no equivale a presencia física en el territorio nacional.

Limitación: el sistema no puede saber si el usuario salió del aeropuerto.
El proxy es el tiempo (<24h). Si supera las 24h, se crea Trip y se avisa
al usuario para que confirme si realmente salió del aeropuerto o no.

