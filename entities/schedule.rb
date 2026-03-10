require "fugit"

class Schedule < ActiveRecord::Base
  belongs_to :user

  validates :prompt, presence: true
  validates :channel, presence: true
  validates :next_run_at, presence: true

  def advance!
    if cron
      update!(next_run_at: Fugit::Cron.parse(cron).next_time.to_t)
    else
      update!(active: false)
    end
  end
end
