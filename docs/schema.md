# Schema de Base de Datos — TaxDays

## Convenciones generales
- Primary keys: UUID en tablas de usuario, integer en catálogos (countries, airports)
- Todos los timestamps en UTC
- Snake_case para todo
- Índices en todas las claves foráneas y campos de búsqueda frecuente

---

## Tabla: users

| Columna        | Tipo      | Restricciones               | Notas                          |
|----------------|-----------|-----------------------------|--------------------------------|
| id             | uuid      | PK, default: gen_random_uuid| No exponer en URLs             |
| email          | string    | NOT NULL, UNIQUE            |                                |
| name           | string    | NOT NULL                    |                                |
| provider       | string    | NOT NULL, default: 'email'  | email / google / apple         |
| uid            | string    |                             | ID externo de OAuth            |
| password_digest| string    |                             | Solo para provider: email      |
| created_at     | datetime  | NOT NULL                    |                                |
| updated_at     | datetime  | NOT NULL                    |                                |

Índices: users(email), users(provider, uid)

---

## Tabla: countries

| Columna           | Tipo    | Restricciones   | Notas                              |
|-------------------|---------|-----------------|------------------------------------|
| id                | integer | PK              | Catálogo fijo, no necesita UUID    |
| name              | string  | NOT NULL        | Nombre en inglés                   |
| code              | string  | NOT NULL, UNIQUE| ISO 3166-1 alpha-2 (ES, FR, UK...) |
| continent         | string  |                 |                                    |
| min_days_required | integer |                 | Días mínimos para residencia fiscal|
| max_days_allowed  | integer | default: 183    | Días máximos antes de ser residente|
| created_at        | datetime| NOT NULL        |                                    |
| updated_at        | datetime| NOT NULL        |                                    |

Índices: countries(code)
Seed: cargar todos los países del mundo al inicializar la app

---

## Tabla: airports

| Columna    | Tipo    | Restricciones   | Notas                     |
|------------|---------|-----------------|---------------------------|
| id         | integer | PK              |                           |
| iata_code  | string  | NOT NULL, UNIQUE| 3 letras mayúsculas       |
| name       | string  | NOT NULL        | Nombre del aeropuerto     |
| city       | string  |                 |                           |
| country_id | integer | FK → countries  | La relación clave         |
| created_at | datetime| NOT NULL        |                           |
| updated_at | datetime| NOT NULL        |                           |

Índices: airports(iata_code), airports(country_id)
Seed: cargar principales aeropuertos internacionales con su país

---

## Tabla: trips

| Columna               | Tipo     | Restricciones       | Notas                                      |
|-----------------------|----------|---------------------|--------------------------------------------|
| id                    | uuid     | PK                  |                                            |
| user_id               | uuid     | FK → users, NOT NULL|                                            |
| origin_country_id     | integer  | FK → countries      | País desde donde sale                      |
| destination_country_id| integer  | FK → countries      | País al que llega (donde acumula días)     |
| departure_date        | date     | NOT NULL            | Día que sale del país origen               |
| arrival_date          | date     | NOT NULL            | Día que llega al país destino              |
| title                 | string   |                     | Autogenerado si vacío                      |
| transport_type        | string   | default: 'flight'   | flight/train/car/ship/other/unknown        |
| has_boarding_pass     | boolean  | default: false      | true si tiene ticket con archivo adjunto   |
| manually_entered      | boolean  | default: false      | true si el usuario lo introdujo a mano     |
| notes                 | text     |                     | Notas libres del usuario                   |
| created_at            | datetime | NOT NULL            |                                            |
| updated_at            | datetime | NOT NULL            |                                            |

Índices: trips(user_id), trips(user_id, departure_date),
         trips(destination_country_id), trips(departure_date)

Validaciones:
- departure_date <= arrival_date
- user_id obligatorio
- destination_country_id obligatorio

---

## Tabla: tickets

| Columna              | Tipo     | Restricciones        | Notas                                        |
|----------------------|----------|----------------------|----------------------------------------------|
| id                   | uuid     | PK                   |                                              |
| user_id              | uuid     | FK → users, NOT NULL |                                              |
| trip_id              | uuid     | FK → trips, NULL OK  | NULL si aún no está asignado a un trip       |
| flight_number        | string   |                      |                                              |
| airline              | string   |                      |                                              |
| departure_airport    | string   |                      | Código IATA 3 letras                         |
| arrival_airport      | string   |                      | Código IATA 3 letras                         |
| departure_datetime   | datetime |                      | Fecha y hora de salida                       |
| arrival_datetime     | datetime |                      | Fecha y hora de llegada                      |
| departure_country_id | integer  | FK → countries       | Derivado del aeropuerto via airports tabla   |
| arrival_country_id   | integer  | FK → countries       | Derivado del aeropuerto via airports tabla   |
| status               | string   | default:'pending'    | pending_parse/parsed/manual/error            |
| parsed_data          | jsonb    |                      | Datos crudos del OCR para debugging          |
| created_at           | datetime | NOT NULL             |                                              |
| updated_at           | datetime | NOT NULL             |                                              |

ActiveStorage: ticket tiene un attachment llamado `original_file`
               (PDF, JPG o PNG, máximo 10MB)

Índices: tickets(user_id), tickets(trip_id), tickets(status),
         tickets(departure_country_id), tickets(arrival_country_id)

Validaciones:
- departure_datetime anterior a arrival_datetime
- departure_airport y arrival_airport: exactamente 3 letras mayúsculas
- original_file: máximo 10MB, solo PDF/JPG/PNG

---

## Relaciones (resumen)

User         has_many :trips
User         has_many :tickets
Trip         belongs_to :user
Trip         belongs_to :origin_country (class: Country)
Trip         belongs_to :destination_country (class: Country)
Trip         has_many :tickets
Ticket       belongs_to :user
Ticket       belongs_to :trip (optional: true)
Ticket       belongs_to :departure_country (class: Country)
Ticket       belongs_to :arrival_country (class: Country)
Country      has_many :trips (como origen y como destino)
Airport      belongs_to :country

---

## Lógica de cálculo de días (NO se almacena, se calcula)

Los días que un usuario pasó en un país durante un año se calculan así:

Para cada Trip donde destination_country = país buscado:
  - inicio_efectivo = MAX(arrival_date, 1 de enero del año)
  - fin_efectivo    = MIN(departure_date del siguiente trip - 1 día,
                         31 de diciembre del año)
  - dias_este_trip  = fin_efectivo - inicio_efectivo + 1

Total = suma de dias_este_trip de todos los trips relevantes

Los "huecos" (gaps) son los rangos del año no cubiertos por ningún trip.
Se calculan en GapDetectorService y se muestran en el dashboard
como períodos sin registrar con botón "Añadir período".
