# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_23_111525) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "name", "record_id", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "airports", force: :cascade do |t|
    t.string "city"
    t.bigint "country_id", null: false
    t.datetime "created_at", null: false
    t.string "iata_code", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_airports_on_country_id"
    t.index ["iata_code"], name: "index_airports_on_iata_code", unique: true
  end

  create_table "countries", force: :cascade do |t|
    t.string "code", null: false
    t.string "continent"
    t.datetime "created_at", null: false
    t.integer "max_days_allowed", default: 183
    t.integer "min_days_required"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_countries_on_code", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tickets", id: :uuid, default: nil, force: :cascade do |t|
    t.string "airline"
    t.string "arrival_airport"
    t.bigint "arrival_country_id"
    t.datetime "arrival_datetime"
    t.datetime "created_at", null: false
    t.string "departure_airport"
    t.bigint "departure_country_id"
    t.datetime "departure_datetime"
    t.string "flight_number"
    t.jsonb "original_file_metadata"
    t.jsonb "parsed_data"
    t.string "status", default: "pending_parse"
    t.uuid "trip_id"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.boolean "verified_by_user", default: false, null: false
    t.index ["arrival_country_id"], name: "index_tickets_on_arrival_country_id"
    t.index ["departure_country_id"], name: "index_tickets_on_departure_country_id"
    t.index ["status"], name: "index_tickets_on_status"
    t.index ["trip_id"], name: "index_tickets_on_trip_id"
    t.index ["user_id"], name: "index_tickets_on_user_id"
  end

  create_table "trips", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "arrival_date", null: false
    t.datetime "created_at", null: false
    t.date "departure_date", null: false
    t.bigint "destination_country_id", null: false
    t.boolean "has_boarding_pass", default: false
    t.boolean "manually_entered", default: false
    t.text "notes"
    t.bigint "origin_country_id"
    t.string "title"
    t.string "transport_type", default: "flight"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["departure_date"], name: "index_trips_on_departure_date"
    t.index ["destination_country_id"], name: "index_trips_on_destination_country_id"
    t.index ["origin_country_id"], name: "index_trips_on_origin_country_id"
    t.index ["user_id", "departure_date"], name: "index_trips_on_user_id_and_departure_date"
    t.index ["user_id"], name: "index_trips_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest"
    t.string "provider", default: "email", null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "airports", "countries"
  add_foreign_key "sessions", "users"
  add_foreign_key "tickets", "countries", column: "arrival_country_id"
  add_foreign_key "tickets", "countries", column: "departure_country_id"
  add_foreign_key "tickets", "trips"
  add_foreign_key "tickets", "users"
  add_foreign_key "trips", "countries", column: "destination_country_id"
  add_foreign_key "trips", "countries", column: "origin_country_id"
  add_foreign_key "trips", "users"
end
