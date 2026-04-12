class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.string :title, null: false
      t.string :author, null: false
      t.decimal :price, null: false, precision: 10, scale: 2
      t.integer :stock, null: false, default: 0

      t.timestamps
    end

    add_check_constraint :books, "stock >= 0", name: "books_stock_non_negative"
  end
end
