namespace :inventory do
  desc "Generate an inventory of all contents with their notes, responses, entities, and statements"
  task content_entities: :environment do
    # This query will return all contents with their notes, responses, entities, and statements
    contents_with_entities = Content.order(id: :desc).limit(5).includes(entities: :statements).map do |content|
      {
        id: content.id,
        note: content.note&.truncate(100),
        created_at: content.created_at,
        response: if content.openai_response.present?
                    {
                      description: content.openai_response["description"]&.truncate(100),
                      annotated_description: content.openai_response["annotated_description"]&.truncate(100),
                      rating: content.openai_response["rating"]
                    }
                  end,
        entities: content.entities.map do |entity|
          {
            id: entity.id,
            name: entity.name,
            statements: entity.statements.map do |statement|
              {
                id: statement.id,
                text: statement.text,
                confidence: statement.confidence,
                object_entity_name: statement.object_entity&.name
              }
            end
          }
        end,
        entity_count: content.entities.size,
        statement_count: content.entities.sum { |entity| entity.statements.size }
      }
    end

    # Print the results in a readable format with debug logging
    puts "=== CONTENT INVENTORY ==="
    puts "Total contents: #{contents_with_entities.size}"
    puts

    contents_with_entities.each do |content|
      puts "CONTENT ##{content[:id]} (#{content[:created_at]})"
      puts "Note: #{content[:note]}"

      if content[:response]
        puts "Response: #{content[:response][:description]}"
        puts "Annotated: #{content[:response][:annotated_description]}"
        puts "Rating: #{content[:response][:rating]}"
      else
        puts "Response: None"
      end

      puts "Entities (#{content[:entity_count]}) with Statements (#{content[:statement_count]}):"

      # Display entities and their statements
      content[:entities].each do |entity|
        puts "  Entity: #{entity[:name]} (ID: #{entity[:id]})"

        if entity[:statements].any?
          puts "    Statements:"
          entity[:statements].each do |statement|
            relation_info = statement[:object_entity_name] ? " -> #{statement[:object_entity_name]}" : ""
            puts "      - #{statement[:text]} (confidence: #{statement[:confidence]})#{relation_info}"
          end
        else
          puts "    No statements found"
        end
      end

      puts "\n#{'-' * 80}\n"
    end

    # Log completion
    puts "Inventory generation completed at #{Time.current}"
  end

  desc "Export content, entity, and statement inventory to a CSV file"
  task export_csv: :environment do
    require "csv"

    filename = Rails.root.join("tmp", "content_entity_inventory_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv")

    CSV.open(filename, "wb") do |csv|
      # Header row
      csv << ["Content ID", "Created At", "Note", "Entity ID", "Entity Name", "Statement ID", "Statement Text", "Confidence",
              "Related Entity"]

      # Data rows with comprehensive debug logging
      puts "Starting CSV export..."
      Content.includes(entities: :statements).find_each do |content|
        puts "Processing content ##{content.id}" if ENV["DEBUG"]

        if content.entities.empty?
          # Include content with no entities
          csv << [content.id, content.created_at, content.note&.truncate(100), nil, nil, nil, nil, nil, nil]
          puts "  No entities found for content ##{content.id}" if ENV["DEBUG"]
        else
          # Include content with each of its entities and statements
          content.entities.each do |entity|
            puts "  Processing entity ##{entity.id} (#{entity.name})" if ENV["DEBUG"]

            if entity.statements.empty?
              # Entity without statements
              csv << [content.id, content.created_at, content.note&.truncate(100), entity.id, entity.name, nil, nil, nil, nil]
              puts "    No statements found for entity ##{entity.id}" if ENV["DEBUG"]
            else
              # Entity with statements
              entity.statements.each do |statement|
                puts "    Processing statement ##{statement.id}" if ENV["DEBUG"]
                csv << [
                  content.id,
                  content.created_at,
                  content.note&.truncate(100),
                  entity.id,
                  entity.name,
                  statement.id,
                  statement.text,
                  statement.confidence,
                  statement.object_entity&.name
                ]
              end
            end
          end
        end
      end
    end

    # Count the total number of rows exported
    row_count = File.foreach(filename).count - 1 # Subtract 1 for the header row

    # Print detailed summary
    puts "CSV export completed: #{filename}"
    puts "Total rows exported: #{row_count}"
    puts "Content count: #{Content.count}"
    puts "Entity count: #{Entity.count}"
    puts "Statement count: #{Statement.count}"
    puts "Export completed at: #{Time.current}"
  end

  desc "Generate statistics about entities and statements"
  task stats: :environment do
    puts "=== ARCHIMEDES DATA STATISTICS ==="
    puts "Generated at: #{Time.current}"
    puts

    # Content statistics
    content_count = Content.count
    content_with_entities = Content.joins(:entities).distinct.count
    content_without_entities = content_count - content_with_entities

    puts "CONTENT STATISTICS:"
    puts "Total contents: #{content_count}"
    puts "Contents with entities: #{content_with_entities} (#{percentage(content_with_entities, content_count)}%)"
    puts "Contents without entities: #{content_without_entities} (#{percentage(content_without_entities, content_count)}%)"
    puts

    # Entity statistics
    entity_count = Entity.count
    entities_with_statements = Entity.joins(:statements).distinct.count
    entities_without_statements = entity_count - entities_with_statements

    puts "ENTITY STATISTICS:"
    puts "Total entities: #{entity_count}"
    puts "Entities with statements: #{entities_with_statements} (#{percentage(entities_with_statements, entity_count)}%)"
    puts "Entities without statements: #{entities_without_statements} (#{percentage(entities_without_statements, entity_count)}%)"
    puts "Average statements per entity: #{(Statement.count.to_f / entity_count).round(2)}" if entity_count.positive?
    puts

    # Statement statistics
    statement_count = Statement.count
    relationship_statements = Statement.relationships.count
    attribute_statements = Statement.attributes.count

    puts "STATEMENT STATISTICS:"
    puts "Total statements: #{statement_count}"
    puts "Relationship statements: #{relationship_statements} (#{percentage(relationship_statements, statement_count)}%)"
    puts "Attribute statements: #{attribute_statements} (#{percentage(attribute_statements, statement_count)}%)"
    puts
  end

  private

  # Helper method to calculate percentage
  def percentage(part, total)
    return 0 if total.zero?

    ((part.to_f / total) * 100).round(1)
  end
end
