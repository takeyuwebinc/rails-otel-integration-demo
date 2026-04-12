class Book < ApplicationRecord
  has_many :orders, dependent: :restrict_with_error

  validates :title, presence: true
  validates :author, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
end
