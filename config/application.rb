# frozen_string_literal: true

require "bundler/setup"
Bundler.require
require "dotenv/load"
require "open3"

module Connectors; end

loader = Zeitwerk::Loader.new
loader.push_dir(File.expand_path("../agents", __dir__))
loader.push_dir(File.expand_path("../channels", __dir__))
loader.push_dir(File.expand_path("../connectors", __dir__), namespace: Connectors)
loader.push_dir(File.expand_path("../entities", __dir__))
loader.push_dir(File.expand_path("../services", __dir__))
loader.push_dir(File.expand_path("../tools", __dir__))
loader.setup

Dir[File.expand_path("initializers/**/*.rb", __dir__)].each { |f| require f }

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: File.expand_path("../db/data/erinos.sqlite3", __dir__)
)

