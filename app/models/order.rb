class Order < ApplicationRecord
  belongs_to :book

  STATUSES = %w[pending confirmed shipped].freeze
  NEXT_STATUS = { "pending" => "confirmed", "confirmed" => "shipped" }.freeze

  validates :order_number, presence: true, uniqueness: true
  validates :quantity, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :total_amount, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  before_validation :assign_order_number, on: :create
  before_validation :calculate_total_amount, on: :create

  def advance_status!
    next_status = NEXT_STATUS[status]
    raise ActiveRecord::RecordInvalid, self unless next_status

    previous_status = status
    update!(status: next_status)

    Rails.event.notify("order.status_changed",
      order_number: order_number,
      from_status: previous_status,
      to_status: next_status
    )
  end

  def can_advance?
    NEXT_STATUS.key?(status)
  end

  def self.create_with_stock_deduction!(book:, quantity:)
    transaction do
      locked_book = Book.lock.find(book.id)

      if locked_book.stock < quantity
        raise InsufficientStockError.new(locked_book.stock)
      end

      order = create!(book: locked_book, quantity: quantity)
      locked_book.update!(stock: locked_book.stock - quantity)

      Rails.event.notify("order.created",
        order_number: order.order_number,
        book_id: locked_book.id,
        quantity: quantity,
        total_amount: order.total_amount
      )

      ORDERS_CREATED_COUNTER.add(1)
      ORDERS_AMOUNT_HISTOGRAM.record(order.total_amount.to_f)

      remaining_stock = locked_book.stock
      if remaining_stock <= 5
        Rails.event.notify("inventory.low",
          book_id: locked_book.id,
          remaining_stock: remaining_stock
        )
      end

      order
    end
  end

  class InsufficientStockError < StandardError
    attr_reader :remaining_stock

    def initialize(remaining_stock)
      @remaining_stock = remaining_stock
      super("在庫が不足しています。現在の在庫数: #{remaining_stock}")
    end
  end

  private

  def assign_order_number
    return if order_number.present?

    max_num = Order.where("order_number LIKE 'ORD-%'")
                   .pick(Arel.sql("MAX(CAST(SUBSTRING(order_number FROM 5) AS INTEGER))")) || 0
    self.order_number = "ORD-#{max_num + 1}"
  end

  def calculate_total_amount
    return if total_amount.present? || book.nil?

    self.total_amount = book.price * quantity
  end
end
