# frozen_string_literal: true

require_relative "config/application"

namespace :db do
  desc "Drop the database"
  task :drop do
    db_path = File.expand_path("db/data/erinos.sqlite3", __dir__)
    FileUtils.rm_f(db_path)
    FileUtils.rm_f("#{db_path}-shm")
    FileUtils.rm_f("#{db_path}-wal")
    ActiveRecord::Base.connection_handler.clear_all_connections!
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: db_path)
    puts "Dropped."
  end

  desc "Run pending migrations"
  task :migrate do
    ActiveRecord::MigrationContext.new("db/migrate").migrate
    puts "Migrated."
  end

  desc "Seed the database"
  task :seed do
    load File.expand_path("db/seeds.rb", __dir__)
    puts "Seeded."
  end

  desc "Drop the database, re-run all migrations, and seed"
  task reset: %i[drop migrate seed]
end

desc "Open an IRB console with the app loaded"
task :console do
  ARGV.clear
  require "irb"
  IRB.start
end