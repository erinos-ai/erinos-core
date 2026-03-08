class User < ActiveRecord::Base
  validates :name, presence: true, uniqueness: true
  validates :pin, presence: true, uniqueness: true
  validates :telegram_id, uniqueness: true, allow_nil: true
end
