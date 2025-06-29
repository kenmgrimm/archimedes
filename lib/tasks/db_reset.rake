# frozen_string_literal: true

namespace :db do
  desc "Reset database and set up with new schema for V3 knowledge graph"
  task reset_for_v3: :environment do
    Rails.logger.info "Starting database reset for V3 knowledge graph..."

    # Confirm in development environment
    unless Rails.env.development?
      puts "This task can only be run in development environment!"
      exit 1
    end

    # Drop all tables and recreate
    Rake::Task["db:drop"].invoke
    Rake::Task["db:create"].invoke
    Rake::Task["db:migrate"].invoke

    # Seed with basic data
    Rake::Task["db:seed"].invoke

    Rails.logger.info "Database reset complete. New schema is ready for V3 knowledge graph."
    puts "Database has been reset with the V3 knowledge graph schema."
  end

  desc "Truncate all tables but keep the schema"
  task truncate_all: :environment do
    Rails.logger.info "Truncating all tables..."

    # Confirm in development environment
    unless Rails.env.development?
      puts "This task can only be run in development environment!"
      exit 1
    end

    # Get all tables except schema_migrations and ar_internal_metadata
    tables = ActiveRecord::Base.connection.tables - ["schema_migrations", "ar_internal_metadata"]

    # Disable foreign key checks temporarily
    if ActiveRecord::Base.connection.adapter_name.downcase.include?("mysql")
      ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 0")
    end
    if ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")
      ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL DEFERRED")
    end

    # Truncate all tables
    tables.each do |table|
      Rails.logger.debug { "Truncating table: #{table}" } if ENV["DEBUG"]
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{table} CASCADE")
    end

    # Re-enable foreign key checks
    if ActiveRecord::Base.connection.adapter_name.downcase.include?("mysql")
      ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 1")
    end
    if ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")
      ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    end

    Rails.logger.info "All tables truncated successfully."
    puts "All tables have been truncated. Schema remains intact."
  end
end
