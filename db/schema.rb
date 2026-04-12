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

ActiveRecord::Schema[8.1].define(version: 2026_04_12_064147) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "books", force: :cascade do |t|
    t.string "author", null: false
    t.datetime "created_at", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.integer "stock", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "stock >= 0", name: "books_stock_non_negative"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.datetime "created_at", null: false
    t.string "order_number", null: false
    t.integer "quantity", null: false
    t.string "status", default: "pending", null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_orders_on_book_id"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.check_constraint "quantity >= 1", name: "orders_quantity_positive"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'confirmed'::character varying::text, 'shipped'::character varying::text])", name: "orders_status_valid"
  end

  add_foreign_key "orders", "books", on_delete: :restrict
end
