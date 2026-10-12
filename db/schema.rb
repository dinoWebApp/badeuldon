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

ActiveRecord::Schema[8.1].define(version: 2026_10_12_000005) do
  create_table "clients", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "contact_name", null: false
    t.string "phone", null: false
    t.string "email"
    t.string "business_number"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "invoice_items", force: :cascade do |t|
    t.integer "invoice_id", null: false
    t.string "description", null: false
    t.integer "quantity", null: false
    t.integer "unit_price", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_invoice_items_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "client_id", null: false
    t.string "issue_number"
    t.integer "status", default: 0, null: false
    t.date "due_on", null: false
    t.integer "tax_mode", default: 0, null: false
    t.boolean "withholding_enabled", default: false, null: false
    t.string "issuer_display_name", null: false
    t.string "bank_name", null: false
    t.string "account_number", null: false
    t.string "account_holder", null: false
    t.integer "subtotal", default: 0, null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "withholding_amount", default: 0, null: false
    t.integer "total_amount", default: 0, null: false
    t.integer "net_amount", default: 0, null: false
    t.string "token"
    t.datetime "token_expires_at"
    t.datetime "issued_at"
    t.datetime "voided_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_invoices_on_client_id"
    t.index ["issue_number"], name: "index_invoices_on_issue_number", unique: true
    t.index ["token"], name: "index_invoices_on_token", unique: true
    t.index ["user_id", "due_on"], name: "index_invoices_on_user_id_and_due_on"
    t.index ["user_id"], name: "index_invoices_on_user_id"
  end

  create_table "items", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.integer "unit_price", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_items_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "display_name"
    t.integer "business_type"
    t.string "bank_name"
    t.string "account_number"
    t.string "account_holder"
    t.string "phone"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "view_events", force: :cascade do |t|
    t.integer "invoice_id", null: false
    t.boolean "first", default: false, null: false
    t.string "device", null: false
    t.string "ip", limit: 45, null: false
    t.datetime "viewed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_view_events_on_invoice_id"
  end

  add_foreign_key "clients", "users"
  add_foreign_key "invoice_items", "invoices"
  add_foreign_key "invoices", "clients"
  add_foreign_key "invoices", "users"
  add_foreign_key "items", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "view_events", "invoices"
end
