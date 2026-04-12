require "test_helper"

class OrderTest < ActiveSupport::TestCase
  test "auto-assigns order number on create" do
    book = books(:ruby_book)
    order = Order.create!(book: book, quantity: 1)
    assert_match(/\AORD-\d+\z/, order.order_number)
  end

  test "calculates total amount from book price and quantity" do
    book = books(:ruby_book)
    order = Order.create!(book: book, quantity: 3)
    assert_equal book.price * 3, order.total_amount
  end

  test "advance_status from pending to confirmed" do
    order = orders(:pending_order)
    order.advance_status!
    assert_equal "confirmed", order.status
  end

  test "advance_status from confirmed to shipped" do
    order = orders(:confirmed_order)
    order.advance_status!
    assert_equal "shipped", order.status
  end

  test "advance_status raises for shipped order" do
    order = orders(:shipped_order)
    assert_raises(ActiveRecord::RecordInvalid) { order.advance_status! }
  end

  test "can_advance? returns true for pending and confirmed" do
    assert orders(:pending_order).can_advance?
    assert orders(:confirmed_order).can_advance?
  end

  test "can_advance? returns false for shipped" do
    assert_not orders(:shipped_order).can_advance?
  end

  test "create_with_stock_deduction! deducts stock" do
    book = books(:ruby_book)
    initial_stock = book.stock

    order = Order.create_with_stock_deduction!(book: book, quantity: 2)

    assert_equal initial_stock - 2, book.reload.stock
    assert_equal "pending", order.status
    assert_equal book.price * 2, order.total_amount
  end

  test "create_with_stock_deduction! raises on insufficient stock" do
    book = books(:out_of_stock_book)

    error = assert_raises(Order::InsufficientStockError) do
      Order.create_with_stock_deduction!(book: book, quantity: 1)
    end

    assert_equal 0, error.remaining_stock
  end

  test "create_with_stock_deduction! does not deduct stock on insufficient stock" do
    book = books(:low_stock_book)

    assert_raises(Order::InsufficientStockError) do
      Order.create_with_stock_deduction!(book: book, quantity: 100)
    end

    assert_equal 3, book.reload.stock
  end
end
