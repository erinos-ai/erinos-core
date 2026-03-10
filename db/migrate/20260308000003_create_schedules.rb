class CreateSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :schedules do |t|
      t.references :user, null: false, foreign_key: true
      t.text :prompt, null: false
      t.string :cron
      t.string :channel, null: false, default: "telegram"
      t.datetime :next_run_at, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :schedules, [:active, :next_run_at]
  end
end
