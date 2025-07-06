require "yaml"
require "neo4j-ruby-driver"
require "neo4j_seeder"

namespace :neo4j do
  desc "Clear all data from Neo4j database (use with caution!)"
  task clear: :environment do
    puts "Clearing all data from Neo4j database..."

    driver = Neo4j::Driver::GraphDatabase.driver(
      NEO4J_CONFIG[:url],
      Neo4j::Driver::AuthTokens.basic(NEO4J_CONFIG[:username], NEO4J_CONFIG[:password]),
      encryption: NEO4J_CONFIG[:encryption]
    )

    begin
      driver.session do |session|
        # Delete all nodes and relationships
        puts "Deleting all nodes and relationships..."
        session.run("MATCH (n) DETACH DELETE n")
        puts "Deleted all nodes and relationships"

        # Reset any auto-increment counters
        begin
          puts "Resetting indexes..."
          session.run("CALL db.indexes() YIELD indexName CALL db.awaitIndex(indexName) YIELD success RETURN count(*)")
          puts "Indexes reset complete"
        rescue StandardError => e
          puts "Note: Could not reset indexes - #{e.message}"
        end
      end

      puts "✅ Neo4j database cleared successfully"
    rescue StandardError => e
      puts "❌ Error clearing Neo4j database: #{e.message}"
      puts e.backtrace.join("\n") if ENV["DEBUG"]
      raise
    ensure
      driver&.close
    end
  end
  desc "Set up Neo4j schema from YAML definition"
  task setup_schema: :environment do
    puts "Setting up Neo4j schema..."

    # Load the schema definition
    schema_path = Rails.root.join("db", "neo4j_seeds", "schema", "01_core_schema.yml")
    schema_definition = YAML.load_file(schema_path)

    # Initialize Neo4j driver
    driver = Neo4j::Driver::GraphDatabase.driver(
      NEO4J_CONFIG[:url],
      Neo4j::Driver::AuthTokens.basic(NEO4J_CONFIG[:username], NEO4J_CONFIG[:password]),
      encryption: NEO4J_CONFIG[:encryption]
    )

    begin
      driver.session do |session|
        # Drop all existing constraints and indexes (be careful with this in production!)
        puts "Dropping existing constraints and indexes..."

        # Get all constraints and drop them
        begin
          result = session.run("SHOW CONSTRAINTS")
          constraints = result.to_a
          if constraints.any?
            puts "  Found #{constraints.size} constraints to drop..."
            constraints.each do |record|
              name = record[:name]
              begin
                puts "  - Dropping constraint: #{name}"
                session.run("DROP CONSTRAINT #{name}")
                puts "    ✓ Dropped constraint: #{name}"
              rescue StandardError => e
                puts "    ⚠️ Error dropping constraint #{name}: #{e.message}"
              end
            end
          else
            puts "  No constraints found to drop"
          end
        rescue StandardError => e
          puts "  ⚠️ Error listing constraints: #{e.message}"
        end

        # Get all indexes and drop them
        begin
          result = session.run("SHOW INDEXES")
          indexes = result.to_a
          if indexes.any?
            puts "  Found #{indexes.size} indexes to drop..."
            indexes.each do |record|
              name = record[:name]
              begin
                puts "  - Dropping index: #{name}"
                session.run("DROP INDEX #{name}")
                puts "    ✓ Dropped index: #{name}"
              rescue StandardError => e
                puts "    ⚠️ Error dropping index #{name}: #{e.message}"
              end
            end
          else
            puts "  No indexes found to drop"
          end
        rescue StandardError => e
          puts "  ⚠️ Error listing indexes: #{e.message}"
        end

        # Create node types and their properties
        schema_definition.each do |node_type, config|
          next unless config.is_a?(Hash) && config["properties"]

          puts "\n🔹 Processing node type: #{node_type}"

          begin
            # Create node type with properties
            config["properties"].each_with_index do |prop, index|
              property_name = prop["name"]
              puts "  #{index + 1}. Processing property: #{property_name} (#{prop['type']})"

              begin
                # Skip property existence constraints (requires Enterprise Edition)
                puts "    - Skipping NOT NULL constraint (requires Neo4j Enterprise Edition)" if prop["required"]

                # Create index if specified
                if prop["indexed"]
                  index_name = "#{node_type.downcase}_#{property_name}_idx"
                  cypher = "CREATE INDEX #{index_name} IF NOT EXISTS " \
                           "FOR (n:#{node_type}) ON (n.#{property_name})"
                  puts "    - Creating index..."
                  begin
                    session.run(cypher)
                    puts "    ✓ Created index on #{node_type}.#{property_name}"
                  rescue StandardError => e
                    puts "    ❌ Error creating index: #{e.message}"
                    puts e.backtrace.join("\n") if ENV["DEBUG"]
                  end
                end
              rescue StandardError => e
                puts "    ❌ Error processing property: #{e.message}"
                puts e.backtrace.join("\n") if ENV["DEBUG"]
                next
              end
            end
          rescue StandardError => e
            puts "  ❌ Error processing #{node_type} properties: #{e.message}"
            puts e.backtrace.join("\n") if ENV["DEBUG"]
            next
          end
        end

        # Process relationship types if defined in the schema
        if schema_definition["relationships"].is_a?(Array)
          puts "\n🔗 Processing relationship types..."
          schema_definition["relationships"].each_with_index do |rel_config, idx|
            rel_type = rel_config["type"]
            from = rel_config["from"]
            to = Array(rel_config["to"]).join(", ")

            puts "  #{idx + 1}. Relationship: #{from} -[#{rel_type}]-> #{to}"

            # NOTE: Neo4j doesn't require explicit relationship type creation
            # We'll just log the relationship for documentation purposes

            # If there are properties, we could create a constraint on them
            puts "    - Has #{rel_config['properties'].size} properties" if rel_config["properties"]&.any?
          rescue StandardError => e
            puts "  ❌ Error processing relationship: #{e.message}"
            puts e.backtrace.join("\n") if ENV["DEBUG"]
            next
          end
        end

        # Process composite indexes if defined
        if schema_definition["indexes"]
          puts "\n🔧 Processing composite indexes..."
          schema_definition["indexes"].each_with_index do |index_config, idx|
            label = index_config["label"]
            properties = index_config["properties"]

            puts "  #{idx + 1}. Creating composite index on #{label}(#{properties.join(', ')})"

            index_name = "#{label.downcase}_#{properties.join('_')}_idx".gsub(/[^a-z0-9_]/, "_")
            props_str = properties.map { |p| "n.#{p}" }.join(", ")

            # Neo4j doesn't use index types like BTREE in the CREATE INDEX syntax
            cypher = "CREATE INDEX #{index_name} IF NOT EXISTS " \
                     "FOR (n:#{label}) ON (#{props_str})"
            puts "    - Executing: #{cypher}"
            begin
              session.run(cypher)
              puts "    ✓ Created composite index on #{label}(#{properties.join(', ')})"
            rescue StandardError => e
              puts "    ❌ Error creating composite index: #{e.message}"
              puts e.backtrace.join("\n") if ENV["DEBUG"]
            end
          rescue StandardError => e
            puts "  ❌ Error creating index: #{e.message}"
            puts e.backtrace.join("\n") if ENV["DEBUG"]
          end
        end
      end
    rescue StandardError => e
      puts "\n❌ Error in Neo4j session: #{e.message}"
      puts e.backtrace.join("\n") if ENV["DEBUG"]
      raise
    ensure
      begin
        driver&.close
      rescue StandardError => e
        puts "\n⚠️ Error closing Neo4j driver: #{e.message}"
      end
    end

    puts "\n✅ Neo4j schema setup complete!"
  end

  # Neo4jSeeder class is now in lib/neo4j_seeder.rb

  desc "Seed Neo4j with initial data from YAML files in db/neo4j_seeds/"
  task seed_data: :environment do
    puts "Seeding Neo4j with initial data..."

    # Load environment variables
    require "dotenv/load"

    # Manually set Neo4j configuration
    neo4j_config = {
      url: ENV.fetch("NEO4J_HTTP_URL"),
      username: ENV.fetch("NEO4J_USERNAME"),
      password: ENV.fetch("NEO4J_PASSWORD"),
      encryption: false
    }

    # Initialize Neo4j driver
    driver = Neo4j::Driver::GraphDatabase.driver(
      neo4j_config[:url],
      Neo4j::Driver::AuthTokens.basic(neo4j_config[:username], neo4j_config[:password]),
      encryption: neo4j_config[:encryption]
    )

    begin
      driver.session do |session|
        # Load seed data from YAML files
        seed_data = {}
        seed_files = Rails.root.glob("db/neo4j_seeds/*.yml")
        puts "Found #{seed_files.size} seed files"

        seed_files.each do |file|
          file_name = File.basename(file, ".yml")
          puts "Loading seed file: #{file}"

          # Load YAML with aliases support
          yaml_content = File.read(file)
          seed_data[file_name] = YAML.safe_load(yaml_content, aliases: true, permitted_classes: [Date, Time, Symbol])

          puts "  - Loaded #{seed_data[file_name].keys.size} top-level keys"

          # Debug: Show the structure of the loaded data
          next unless ENV["DEBUG"]

          puts "  - Data structure:"
          pp seed_data[file_name].keys

          # Check if relationships exist and show a sample
          next unless seed_data[file_name]["relationships"]

          puts "  - Found #{seed_data[file_name]['relationships'].size} relationships"
          if seed_data[file_name]["relationships"].any?
            puts "  - Sample relationship: #{seed_data[file_name]['relationships'].first.inspect}"
          end
        end

        # Process each entity type
        entity_types = {
          "users" => "👥",
          "contacts" => "👥",
          "possessions" => "🏠",
          "events" => "🗓️",
          "documents" => "📄",
          "projects" => "📂",
          "tasks" => "✅",
          "media_assets" => "🖼️"
        }

        # First, process all nodes from each seed file
        seed_data.each do |file_name, file_data|
          puts "\n📂 Processing seed file: #{file_name}"

          # Process nodes for each entity type
          entity_types.each do |type, icon|
            next unless file_data[type].is_a?(Array)

            puts "  #{icon} Seeding #{file_data[type].size} #{type}..."
            file_data[type].each_with_index do |entity_data, index|
              if ENV["DEBUG"]
                puts "    - Processing #{type.singularize} #{index + 1}: #{entity_data['id']}"
                puts "      Labels: #{entity_data['labels']}" if entity_data["labels"]
              end
              Neo4jSeeder.create_node(session, entity_data, index + 1)
            end
          end

          # Process relationships for this file
          if file_data["relationships"].is_a?(Array)
            puts "  🔗 Creating #{file_data['relationships'].size} relationships..."
            file_data["relationships"].each_with_index do |rel_data, index|
              if ENV["DEBUG"]
                to_nodes = Array(rel_data["to"]).join(", ")
                puts "    - Relationship #{index + 1}: #{rel_data['type']} from #{rel_data['from']} to #{to_nodes}"
                puts "      Properties: #{rel_data['properties'].inspect}" if rel_data["properties"]
              end
              Neo4jSeeder.create_relationships(session, rel_data)
            end
          else
            puts "  ℹ️ No relationships found in this file"
          end
        end
      end
    ensure
      begin
        driver&.close
      rescue StandardError => e
        puts "\n⚠️ Error closing Neo4j driver: #{e.message}"
      end
    end
  end

  desc "List all nodes and relationships in Neo4j database"
  task list_nodes: :environment do
    puts "Connecting to Neo4j at #{NEO4J_CONFIG[:url]}..."

    driver = Neo4j::Driver::GraphDatabase.driver(
      NEO4J_CONFIG[:url],
      Neo4j::Driver::AuthTokens.basic(NEO4J_CONFIG[:username], NEO4J_CONFIG[:password]),
      encryption: NEO4J_CONFIG[:encryption]
    )

    begin
      driver.session do |session|
        puts "\n📊 Current nodes in the database:"

        # Get all node labels
        result = session.run("MATCH (n) RETURN DISTINCT labels(n) as labels, count(*) as count")
        puts "\n📋 Node counts by label:"
        result.each do |record|
          puts "  - #{record['labels']}: #{record['count']} nodes"
        end

        # Get sample nodes
        puts "\n🔍 Sample nodes (up to 10):"
        result = session.run("MATCH (n) RETURN labels(n) as labels, n.id as id, n.name as name LIMIT 10")
        result.each_with_index do |record, index|
          puts "  #{index + 1}. #{record['labels']} - ID: #{record['id']}, Name: #{record['name'] || 'N/A'}"
        end

        # Get relationship types
        puts "\n🤝 Relationship types:"
        result = session.run("MATCH ()-[r]->() RETURN DISTINCT type(r) as type, count(*) as count")
        if result.any?
          result.each do |record|
            puts "  - #{record['type']}: #{record['count']} relationships"
          end
        else
          puts "  No relationships found in the database."
        end

        # Get sample relationships
        puts "\n🔗 Sample relationships (up to 10):"
        result = session.run("
          MATCH (a)-[r]->(b)
          RETURN
            type(r) as type,
            labels(a) as from_labels,
            a.id as from_id,
            labels(b) as to_labels,
            b.id as to_id,
            properties(r) as props
          LIMIT 10
        ")

        if result.any?
          result.each_with_index do |record, index|
            puts "  #{index + 1}. (#{record['from_labels']}:#{record['from_id']})-" \
                 "[#{record['type']} #{record['props'].to_s.gsub(/[{}]/, '')}]->" \
                 "(#{record['to_labels']}:#{record['to_id']})"
          end
        else
          puts "  No relationships found in the database."
        end
      end
    ensure
      driver&.close
    end
  end
end
