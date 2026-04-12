require "test_helper"

class BookTest < ActiveSupport::TestCase
  test "validates presence of required fields" do
    book = Book.new
    assert_not book.valid?
    assert_includes book.errors[:title], "can't be blank"
    assert_includes book.errors[:author], "can't be blank"
    assert_includes book.errors[:price], "can't be blank"
  end

  test "validates stock is non-negative" do
    book = books(:ruby_book)
    book.stock = -1
    assert_not book.valid?
  end

  test "validates price is positive" do
    book = books(:ruby_book)
    book.price = 0
    assert_not book.valid?
  end

  test "restricts deletion when orders exist" do
    book = books(:ruby_book)
    assert_not book.destroy
    assert book.errors[:base].any? { |e| e.include?("Cannot delete") }
  end
end
