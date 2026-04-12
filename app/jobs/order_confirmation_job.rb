class OrderConfirmationJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)
    OrderConfirmationMailer.confirmation(order).deliver_now
  end
end
