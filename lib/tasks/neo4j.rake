require 'yaml'
require 'neo4j-ruby-driver'

namespace :neo4j do
  desc 'Set up Neo4j schema from YAML definition'
  task setup_schema: :environment do
    puts "Setting up Neo4j schema..."
    
    # Load the schema definition
    schema_path = Rails.root.join('db', 'neo4j_seeds', 'schema', '01_core_schema.yml')
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
          next unless config.is_a?(Hash) && config['properties']
          
          puts "\n🔹 Processing node type: #{node_type}"
          
          begin
            # Create node type with properties
            config['properties'].each_with_index do |prop, index|
              property_name = prop['name']
              puts "  #{index + 1}. Processing property: #{property_name} (#{prop['type']})"
              
              begin
                # Skip property existence constraints (requires Enterprise Edition)
                if prop['required']
                  puts "    - Skipping NOT NULL constraint (requires Neo4j Enterprise Edition)"
                end
                
                # Create index if specified
                if prop['indexed']
                  index_name = "#{node_type.downcase}_#{property_name}_idx"
                  cypher = "CREATE INDEX #{index_name} IF NOT EXISTS " \
                          "FOR (n:#{node_type}) ON (n.#{property_name})"
                  puts "    - Creating index..."
                  begin
                    session.run(cypher)
                    puts "    ✓ Created index on #{node_type}.#{property_name}"
                  rescue StandardError => e
                    puts "    ❌ Error creating index: #{e.message}"
                    puts e.backtrace.join("\n") if ENV['DEBUG']
                  end
                end
              rescue StandardError => e
                puts "    ❌ Error processing property: #{e.message}"
                puts e.backtrace.join("\n") if ENV['DEBUG']
                next
              end
            end
          rescue StandardError => e
            puts "  ❌ Error processing #{node_type} properties: #{e.message}"
            puts e.backtrace.join("\n") if ENV['DEBUG']
            next
          end
        end
        
        # Process relationship types if defined in the schema
        if schema_definition['relationships'] && schema_definition['relationships'].is_a?(Array)
          puts "\n🔗 Processing relationship types..."
          schema_definition['relationships'].each_with_index do |rel_config, idx|
            begin
              rel_type = rel_config['type']
              from = rel_config['from']
              to = Array(rel_config['to']).join(', ')
              
              puts "  #{idx + 1}. Relationship: #{from} -[#{rel_type}]-> #{to}"
              
              # Note: Neo4j doesn't require explicit relationship type creation
              # We'll just log the relationship for documentation purposes
              
              # If there are properties, we could create a constraint on them
              if rel_config['properties'] && rel_config['properties'].any?
                puts "    - Has #{rel_config['properties'].size} properties"
              end
              
            rescue StandardError => e
              puts "  ❌ Error processing relationship: #{e.message}"
              puts e.backtrace.join("\n") if ENV['DEBUG']
              next
            end
          end
        end
        
        # Process composite indexes if defined
        if schema_definition['indexes']
          puts "\n🔧 Processing composite indexes..."
          schema_definition['indexes'].each_with_index do |index_config, idx|
            begin
              label = index_config['label']
              properties = index_config['properties']
              
              puts "  #{idx + 1}. Creating composite index on #{label}(#{properties.join(', ')})"
              
              index_name = "#{label.downcase}_#{properties.join('_')}_idx".gsub(/[^a-z0-9_]/, '_')
              props_str = properties.map { |p| "n.#{p}" }.join(', ')
              
              # Neo4j doesn't use index types like BTREE in the CREATE INDEX syntax
              cypher = "CREATE INDEX #{index_name} IF NOT EXISTS " \
                      "FOR (n:#{label}) ON (#{props_str})"
              puts "    - Executing: #{cypher}"
              begin
                session.run(cypher)
                puts "    ✓ Created composite index on #{label}(#{properties.join(', ')})"
              rescue StandardError => e
                puts "    ❌ Error creating composite index: #{e.message}"
                puts e.backtrace.join("\n") if ENV['DEBUG']
              end
            rescue StandardError => e
              puts "  ❌ Error creating index: #{e.message}"
              puts e.backtrace.join("\n") if ENV['DEBUG']
            end
          end
        end
      end
    rescue StandardError => e
      puts "\n❌ Error in Neo4j session: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
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
  
  private
  
  # Maps YAML property types to Neo4j property types
  # @param type [String] the property type from YAML
  # @return [String] the corresponding Neo4j type
  def self.map_property_type(type)
    case type.to_s.downcase
    when 'integer', 'int' then 'INTEGER'
    when 'float', 'double' then 'FLOAT'
    when 'boolean', 'bool' then 'BOOLEAN'
    when 'date' then 'DATE'
    when 'datetime', 'timestamp' then 'DATETIME'
    when 'point' then 'POINT'
    when 'map', 'hash' then 'MAP'
    when 'array', 'list' then 'LIST'
    else 'STRING' # Default to STRING for text/string and any unknown types
    end
  end
end
