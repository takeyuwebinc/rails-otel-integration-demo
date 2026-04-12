require "test_helper"

class BooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @book = books(:ruby_book)
  end

  test "should get index" do
    get books_url
    assert_response :success
  end

  test "should get new" do
    get new_book_url
    assert_response :success
  end

  test "should create book" do
    assert_difference("Book.count") do
      post books_url, params: { book: { author: @book.author, price: @book.price, stock: @book.stock, title: @book.title } }
    end

    assert_redirected_to book_url(Book.last)
  end

  test "should show book" do
    get book_url(@book)
    assert_response :success
  end

  test "should get edit" do
    get edit_book_url(@book)
    assert_response :success
  end

  test "should update book" do
    patch book_url(@book), params: { book: { author: @book.author, price: @book.price, stock: @book.stock, title: @book.title } }
    assert_redirected_to book_url(@book)
  end

  test "should destroy book without orders" do
    book = Book.create!(title: "Temp", author: "Author", price: 100, stock: 1)
    assert_difference("Book.count", -1) do
      delete book_url(book)
    end

    assert_redirected_to books_url
  end

  test "should not destroy book with orders" do
    assert_no_difference("Book.count") do
      delete book_url(@book)
    end

    assert_redirected_to book_url(@book)
  end
end
