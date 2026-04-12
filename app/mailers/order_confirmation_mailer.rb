class OrderConfirmationMailer < ApplicationMailer
  def confirmation(order)
    @order = order
    Rails.logger.info "[DEMO] 注文確認メール送信（実際には送信しません）: #{order.order_number}"
    mail(to: "demo@example.com", subject: "注文確認: #{order.order_number}")
  end
end
