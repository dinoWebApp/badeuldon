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

ActiveRecord::Schema[8.1].define(version: 2026_11_20_000000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_sessions", force: :cascade do |t|
    t.integer "admin_id", null: false
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_activity_at", null: false
    t.string "ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_admin_sessions_on_admin_id"
    t.index ["token"], name: "index_admin_sessions_on_token", unique: true
  end

  create_table "admins", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 1, null: false
    t.text "otp_secret"
    t.datetime "otp_confirmed_at"
    t.integer "otp_last_used_counter"
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.datetime "last_login_at"
    t.string "last_login_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
  end

  create_table "audit_logs", force: :cascade do |t|
    t.integer "admin_id"
    t.string "action", null: false
    t.string "target_type"
    t.integer "target_id"
    t.text "detail"
    t.string "ip", limit: 45
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["admin_id"], name: "index_audit_logs_on_admin_id"
  end

  create_table "blog_posts", force: :cascade do |t|
    t.integer "admin_id", null: false
    t.string "title", null: false
    t.string "slug", null: false
    t.text "body_md", null: false
    t.text "body_html", null: false
    t.integer "category", default: 0, null: false
    t.string "tags"
    t.integer "status", default: 0, null: false
    t.datetime "publish_at"
    t.datetime "published_at"
    t.string "meta_title"
    t.string "meta_description"
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_blog_posts_on_admin_id"
    t.index ["slug"], name: "index_blog_posts_on_slug", unique: true
    t.index ["status", "published_at"], name: "index_blog_posts_on_status_and_published_at"
  end

  create_table "blog_slug_redirects", force: :cascade do |t|
    t.string "old_slug", null: false
    t.integer "blog_post_id", null: false
    t.datetime "created_at", null: false
    t.index ["blog_post_id"], name: "index_blog_slug_redirects_on_blog_post_id"
    t.index ["old_slug"], name: "index_blog_slug_redirects_on_old_slug", unique: true
  end

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
    t.datetime "reminders_suspended_at"
    t.datetime "refused_at"
    t.string "ceo_name"
    t.string "corp_addr"
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "coupons", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.integer "discount_type", default: 0, null: false
    t.integer "discount_value", null: false
    t.integer "max_redemptions", null: false
    t.integer "used_count", default: 0, null: false
    t.date "expires_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_coupons_on_code", unique: true
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
    t.datetime "reminders_suspended_at"
    t.datetime "sequence_finished_at"
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

  create_table "message_logs", force: :cascade do |t|
    t.integer "invoice_id"
    t.integer "user_id", null: false
    t.integer "recipient_role", default: 0, null: false
    t.string "template_key", null: false
    t.integer "origin", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "phone"
    t.text "variables"
    t.string "provider_message_id"
    t.string "error_code"
    t.text "error_message"
    t.datetime "scheduled_at"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ticket_id"
    t.boolean "digest", default: false, null: false
    t.index ["invoice_id", "template_key"], name: "idx_message_logs_debtor_pending_uniq", unique: true, where: "recipient_role = 0 AND status = 0"
    t.index ["invoice_id"], name: "index_message_logs_on_invoice_id"
    t.index ["provider_message_id"], name: "index_message_logs_on_provider_message_id"
    t.index ["ticket_id"], name: "index_message_logs_on_ticket_id"
    t.index ["user_id", "template_key", "scheduled_at"], name: "idx_message_logs_digest_period_uniq", unique: true, where: "digest = 1"
    t.index ["user_id"], name: "index_message_logs_on_user_id"
  end

  create_table "notice_reads", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "notice_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notice_id"], name: "index_notice_reads_on_notice_id"
    t.index ["user_id", "notice_id"], name: "index_notice_reads_on_user_id_and_notice_id", unique: true
    t.index ["user_id"], name: "index_notice_reads_on_user_id"
  end

  create_table "notices", force: :cascade do |t|
    t.string "title", null: false
    t.text "body", null: false
    t.integer "importance", default: 0, null: false
    t.datetime "published_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["importance"], name: "index_notices_on_importance"
    t.index ["published_at"], name: "index_notices_on_published_at"
  end

  create_table "orders", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "product", null: false
    t.integer "amount", null: false
    t.integer "status", default: 0, null: false
    t.string "pg_order_id", null: false
    t.string "pg_payment_id"
    t.string "pg_billing_key"
    t.datetime "paid_at"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "refunded_at"
    t.text "refund_reason"
    t.integer "item_type", default: 0, null: false
    t.index ["pg_order_id"], name: "index_orders_on_pg_order_id", unique: true
    t.index ["pg_payment_id"], name: "index_orders_on_pg_payment_id"
    t.index ["user_id", "item_type"], name: "index_orders_on_user_id_and_item_type"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "payment_passes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "total_uses", default: 10, null: false
    t.integer "remaining_uses", default: 10, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_payment_passes_on_user_id"
    t.check_constraint "remaining_uses >= 0", name: "payment_passes_remaining_uses_non_negative"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "invoice_id", null: false
    t.integer "amount", null: false
    t.date "paid_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "note"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.check_constraint "amount > 0", name: "payments_amount_positive"
  end

  create_table "phone_verifications", force: :cascade do |t|
    t.string "phone", null: false
    t.string "code", null: false
    t.datetime "expires_at", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["phone", "created_at"], name: "index_phone_verifications_on_phone_and_created_at"
  end

  create_table "promises", force: :cascade do |t|
    t.integer "invoice_id", null: false
    t.integer "kind", null: false
    t.date "promised_on"
    t.text "memo"
    t.text "answer"
    t.datetime "answered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_promises_on_invoice_id"
  end

  create_table "recurring_invoice_items", force: :cascade do |t|
    t.integer "recurring_invoice_id", null: false
    t.string "name", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recurring_invoice_id"], name: "index_recurring_invoice_items_on_recurring_invoice_id"
  end

  create_table "recurring_invoices", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "client_id", null: false
    t.integer "last_invoice_id"
    t.integer "day_of_month", null: false
    t.integer "tax_mode", default: 0, null: false
    t.boolean "withholding_enabled", default: false, null: false
    t.boolean "hold_if_unpaid", default: false, null: false
    t.integer "status", default: 0, null: false
    t.date "last_issued_on"
    t.date "next_issue_on", null: false
    t.string "last_skip_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_recurring_invoices_on_client_id"
    t.index ["last_invoice_id"], name: "index_recurring_invoices_on_last_invoice_id"
    t.index ["user_id", "next_issue_on"], name: "index_recurring_invoices_on_user_id_and_next_issue_on"
    t.index ["user_id"], name: "index_recurring_invoices_on_user_id"
  end

  create_table "sales_commissions", force: :cascade do |t|
    t.integer "sales_rep_id", null: false
    t.integer "year", null: false
    t.integer "month", null: false
    t.integer "base_amount", default: 0, null: false
    t.integer "rate", null: false
    t.integer "amount", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "paid_at"
    t.datetime "settled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sales_rep_id", "year", "month"], name: "index_sales_commissions_on_rep_year_month", unique: true
    t.index ["sales_rep_id"], name: "index_sales_commissions_on_sales_rep_id"
  end

  create_table "sales_referral_codes", force: :cascade do |t|
    t.integer "sales_rep_id", null: false
    t.string "code", null: false
    t.date "valid_from", null: false
    t.date "valid_until", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_sales_referral_codes_on_code", unique: true
    t.index ["sales_rep_id", "valid_until"], name: "index_sales_referral_codes_on_sales_rep_id_and_valid_until"
    t.index ["sales_rep_id"], name: "index_sales_referral_codes_on_sales_rep_id"
  end

  create_table "sales_rep_sessions", force: :cascade do |t|
    t.string "token", null: false
    t.integer "sales_rep_id", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_activity_at", null: false
    t.string "ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sales_rep_id"], name: "index_sales_rep_sessions_on_sales_rep_id"
    t.index ["token"], name: "index_sales_rep_sessions_on_token", unique: true
  end

  create_table "sales_reps", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.string "title"
    t.integer "role", default: 0, null: false
    t.integer "commission_rate"
    t.integer "status", default: 0, null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_sales_reps_on_email", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "plan", default: 0, null: false
    t.integer "status", default: 1, null: false
    t.datetime "trial_ends_at"
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.string "pg_customer_key"
    t.string "pg_billing_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "used_trial", default: false, null: false
    t.integer "coupon_id"
    t.integer "dunning_stage", default: 0, null: false
    t.datetime "next_retry_at"
    t.datetime "last_payment_failed_at"
    t.index ["coupon_id"], name: "index_subscriptions_on_coupon_id"
    t.index ["pg_customer_key"], name: "idx_subscriptions_on_pg_customer_key_uniq", unique: true, where: "pg_customer_key IS NOT NULL"
    t.index ["user_id"], name: "index_subscriptions_on_user_id", unique: true
  end

  create_table "tax_invoices", force: :cascade do |t|
    t.integer "invoice_id", null: false
    t.integer "user_id", null: false
    t.string "mgt_num", null: false
    t.integer "status", default: 0, null: false
    t.integer "barobill_state"
    t.integer "nts_send_state"
    t.string "nts_send_key"
    t.date "write_date"
    t.integer "supply_total", null: false
    t.integer "tax_total", null: false
    t.integer "grand_total", null: false
    t.integer "order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_tax_invoices_on_invoice_id", unique: true
    t.index ["mgt_num"], name: "index_tax_invoices_on_mgt_num", unique: true
    t.index ["order_id"], name: "index_tax_invoices_on_order_id"
    t.index ["status"], name: "index_tax_invoices_on_status"
    t.index ["user_id"], name: "index_tax_invoices_on_user_id"
  end

  create_table "ticket_messages", force: :cascade do |t|
    t.integer "ticket_id", null: false
    t.integer "sender", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_ticket_messages_on_ticket_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "category", default: 4, null: false
    t.string "title", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_tickets_on_status"
    t.index ["user_id"], name: "index_tickets_on_user_id"
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
    t.integer "status", default: 0, null: false
    t.string "corp_num"
    t.string "corp_name"
    t.string "ceo_name"
    t.string "corp_addr"
    t.string "contact_name"
    t.integer "tax_type", default: 0, null: false
    t.string "barobill_id"
    t.boolean "barobill_cert_registered", default: false, null: false
    t.string "remind_allowed_wdays", default: "1,2,3,4,5", null: false
    t.integer "remind_start_hour", default: 9, null: false
    t.integer "remind_end_hour", default: 18, null: false
    t.boolean "noti2_digest_enabled", default: true, null: false
    t.string "referral_code_snapshot"
    t.integer "referred_by_sales_rep_id"
    t.index ["barobill_id"], name: "index_users_on_barobill_id", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["phone"], name: "index_users_on_phone_when_present", unique: true, where: "phone IS NOT NULL"
    t.index ["referred_by_sales_rep_id"], name: "index_users_on_referred_by_sales_rep_id"
  end

  create_table "view_events", force: :cascade do |t|
    t.integer "invoice_id", null: false
    t.boolean "first", default: false, null: false
    t.string "device", null: false
    t.string "ip", limit: 45, null: false
    t.datetime "viewed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "ip", "viewed_at"], name: "index_view_events_on_invoice_ip_viewed_at"
    t.index ["invoice_id"], name: "index_view_events_on_invoice_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_sessions", "admins", on_delete: :cascade
  add_foreign_key "audit_logs", "admins", on_delete: :cascade
  add_foreign_key "blog_posts", "admins"
  add_foreign_key "blog_slug_redirects", "blog_posts", on_delete: :cascade
  add_foreign_key "clients", "users"
  add_foreign_key "invoice_items", "invoices"
  add_foreign_key "invoices", "clients"
  add_foreign_key "invoices", "users"
  add_foreign_key "items", "users"
  add_foreign_key "message_logs", "invoices", on_delete: :cascade
  add_foreign_key "message_logs", "tickets", on_delete: :cascade
  add_foreign_key "message_logs", "users", on_delete: :cascade
  add_foreign_key "notice_reads", "notices", on_delete: :cascade
  add_foreign_key "notice_reads", "users", on_delete: :cascade
  add_foreign_key "orders", "users", on_delete: :cascade
  add_foreign_key "payment_passes", "users", on_delete: :cascade
  add_foreign_key "payments", "invoices"
  add_foreign_key "promises", "invoices"
  add_foreign_key "recurring_invoice_items", "recurring_invoices", on_delete: :cascade
  add_foreign_key "recurring_invoices", "clients", on_delete: :cascade
  add_foreign_key "recurring_invoices", "invoices", column: "last_invoice_id", on_delete: :restrict
  add_foreign_key "recurring_invoices", "users", on_delete: :cascade
  add_foreign_key "sales_commissions", "sales_reps"
  add_foreign_key "sales_referral_codes", "sales_reps"
  add_foreign_key "sales_rep_sessions", "sales_reps"
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "coupons"
  add_foreign_key "subscriptions", "users", on_delete: :cascade
  add_foreign_key "tax_invoices", "invoices"
  add_foreign_key "tax_invoices", "orders"
  add_foreign_key "tax_invoices", "users"
  add_foreign_key "ticket_messages", "tickets", on_delete: :cascade
  add_foreign_key "tickets", "users", on_delete: :cascade
  add_foreign_key "users", "sales_reps", column: "referred_by_sales_rep_id"
  add_foreign_key "view_events", "invoices"
end
