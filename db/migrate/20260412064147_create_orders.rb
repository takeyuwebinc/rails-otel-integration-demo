class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :order_number, null: false
      t.references :book, null: false, foreign_key: { on_delete: :restrict }
      t.integer :quantity, null: false
      t.decimal :total_amount, null: false, precision: 10, scale: 2
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :orders, :order_number, unique: true
    add_check_constraint :orders, "quantity >= 1", name: "orders_quantity_positive"
    add_check_constraint :orders, "status IN ('pending', 'confirmed', 'shipped')", name: "orders_status_valid"
  end
end
