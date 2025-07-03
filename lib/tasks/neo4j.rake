require "yaml"
require "neo4j-ruby-driver"

namespace :neo4j do
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
        if schema_definition["relationships"] && schema_definition["relationships"].is_a?(Array)
          puts "\n🔗 Processing relationship types..."
          schema_definition["relationships"].each_with_index do |rel_config, idx|
            rel_type = rel_config["type"]
            from = rel_config["from"]
            to = Array(rel_config["to"]).join(", ")

            puts "  #{idx + 1}. Relationship: #{from} -[#{rel_type}]-> #{to}"

            # NOTE: Neo4j doesn't require explicit relationship type creation
            # We'll just log the relationship for documentation purposes

            # If there are properties, we could create a constraint on them
            puts "    - Has #{rel_config['properties'].size} properties" if rel_config["properties"] && rel_config["properties"].any?
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
        driver&.close if driver
      rescue StandardError => e
        puts "\n⚠️ Error closing Neo4j driver: #{e.message}"
      end
    end

    puts "\n✅ Neo4j schema setup complete!"
  end

  desc "Seed Neo4j with initial data from YAML files"
  task seed_data: :environment do
    # Helper method to create a node in Neo4j from seed data
    def create_node(session, node_data, index)
      labels = node_data["labels"] || []
      properties = node_data["properties"] || {}

      # Convert Ruby hashes to Neo4j maps
      properties = convert_properties(properties)

      # Prepare the query with parameters
      label_str = labels.map { |l| ":#{l}" }.join

      # Build the properties part of the query
      set_statements = properties.keys.map { |k| "n.#{k} = $#{k}" }.join(", ")

      # Create a single-line query to avoid newline issues
      query = "MERGE (n#{label_str} {id: $id}) " \
              "ON CREATE SET #{set_statements} " \
              "ON MATCH SET #{set_statements} " \
              "RETURN n".squish

      # Prepare parameters with the ID included
      params = properties.merge(id: node_data["id"])

      begin
        session.write_transaction do |tx|
          # Execute the query with parameters properly formatted
          tx.run(query, **params)
        end
        puts "    ✓ Created/Updated #{labels.join(':')} #{index}: #{properties['name'] || properties['title'] || node_data['id']}"
      rescue StandardError => e
        puts "    ❌ Error creating/updating node: #{e.message}"
        puts "      Query: #{query}"
        puts "      Params: #{params.inspect}"
        puts e.backtrace.join("\n") if ENV["DEBUG"]
      end
    end

    # Helper method to convert Ruby objects to Neo4j-compatible types
    def convert_properties(properties)
      properties.each_with_object({}) do |(key, value), hash|
        hash[key] = case value
                    when Time, DateTime
                      value.iso8601
                    when Date
                      value.to_s
                    when Hash, Array
                      value.to_json
                    else
                      value
                    end
      end
    end

    puts "Seeding Neo4j with initial data..."

    # Initialize Neo4j driver
    driver = Neo4j::Driver::GraphDatabase.driver(
      NEO4J_CONFIG[:url],
      Neo4j::Driver::AuthTokens.basic(NEO4J_CONFIG[:username], NEO4J_CONFIG[:password]),
      encryption: NEO4J_CONFIG[:encryption]
    )

    begin
      driver.session do |session|
        # Load and process each seed file in order (alphabetically)
        seed_files = Dir[Rails.root.join("db", "neo4j_seeds", "*.yml")]

        seed_files.each do |file_path|
          puts "\n📝 Processing seed file: #{File.basename(file_path)}"
          seed_data = YAML.load_file(file_path)

          # Process users
          if seed_data["users"]
            puts "  👥 Seeding #{seed_data['users'].size} users..."
            seed_data["users"].each_with_index do |user_data, index|
              create_node(session, user_data, index + 1)
            end
          end

          # Process contacts
          if seed_data["contacts"]
            puts "  👥 Seeding #{seed_data['contacts'].size} contacts..."
            seed_data["contacts"].each_with_index do |contact_data, index|
              create_node(session, contact_data, index + 1)
            end
          end

          # Process possessions
          if seed_data["possessions"]
            puts "  🏠 Seeding #{seed_data['possessions'].size} possessions..."
            seed_data["possessions"].each_with_index do |possession_data, index|
              create_node(session, possession_data, index + 1)
            end
          end

          # Process events
          next unless seed_data["events"]

          puts "  🗓️  Seeding #{seed_data['events'].size} events..."
          seed_data["events"].each_with_index do |event_data, index|
            create_node(session, event_data, index + 1)
          end
        end

        puts "\n✅ Neo4j data seeding complete!"
      end
    rescue StandardError => e
      puts "\n❌ Error seeding Neo4j data: #{e.message}"
      puts e.backtrace.join("\n") if ENV["DEBUG"]
      raise
    ensure
      begin
        driver&.close
      rescue StandardError => e
        puts "\n⚠️ Error closing Neo4j driver: #{e.message}"
      end
    end
  end

  # Maps YAML property types to Neo4j property types
  # @param type [String] the property type from YAML
  # @return [String] the corresponding Neo4j type
  def self.map_property_type(type)
    case type.downcase
    when "string", "text" then "STRING"
    when "integer", "int" then "INTEGER"
    when "float", "double" then "FLOAT"
    when "boolean", "bool" then "BOOLEAN"
    when "date" then "DATE"
    when "datetime", "timestamp" then "DATETIME"
    when "point" then "POINT"
    when "node" then "NODE"
    when "relationship" then "RELATIONSHIP"
    when "path" then "PATH"
    when "map", "object" then "MAP"
    when "list", "array" then "LIST"
    else "STRING" # Default to string if type is unknown
    end
  end
end
