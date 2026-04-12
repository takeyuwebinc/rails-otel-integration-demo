class OrdersController < ApplicationController
  before_action :set_order, only: %i[show advance]

  # GET /orders
  def index
    @orders = Order.includes(:book).order(created_at: :desc)
  end

  # GET /orders/1
  def show
  end

  # GET /orders/new
  def new
    @order = Order.new
    @order.book_id = params[:book_id] if params[:book_id]
    @books = Book.where("stock > 0").order(:title)
  end

  # POST /orders
  def create
    book = Book.find(params[:book_id])
    quantity = params[:quantity].to_i

    @order = Order.create_with_stock_deduction!(book: book, quantity: quantity)
    OrderConfirmationJob.perform_later(@order.id)
    redirect_to @order, notice: "注文を作成しました（注文番号: #{@order.order_number}）"
  rescue Order::InsufficientStockError => e
    redirect_to new_order_path(book_id: book.id), alert: e.message
  end

  # PATCH /orders/1/advance
  def advance
    previous_status = @order.status
    @order.advance_status!
    redirect_to orders_path, notice: "注文 #{@order.order_number} のステータスを #{previous_status} → #{@order.status} に変更しました"
  rescue ActiveRecord::RecordInvalid
    redirect_to orders_path, alert: "この注文は既に出荷済みです"
  end

  private

  def set_order
    @order = Order.find(params.expect(:id))
  end
end
