namespace :inventory do
  desc "Generate an inventory of all contents with their notes, responses, and entities"
  task content_entities: :environment do
    # This query will return all contents with their notes, responses, and entities
    contents_with_entities = Content.includes(:entities).map do |content|
      {
        id: content.id,
        note: content.note&.truncate(100),
        created_at: content.created_at,
        response: if content.openai_response.present?
                    {
                      description: content.openai_response["description"]&.truncate(100),
                      rating: content.openai_response["rating"]
                    }
                  end,
        entities: content.entities.map do |entity|
          {
            id: entity.id,
            type: entity.entity_type,
            value: entity.value
          }
        end,
        entity_count: content.entities.size,
        entity_types: content.entities.pluck(:entity_type).uniq
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
        puts "Rating: #{content[:response][:rating]}"
      else
        puts "Response: None"
      end

      puts "Entities (#{content[:entity_count]}):"
      puts "Types: #{content[:entity_types].join(', ')}"

      # Group entities by type for better readability
      entities_by_type = content[:entities].group_by { |e| e[:type] }

      entities_by_type.each do |type, entities|
        puts "  #{type} (#{entities.size}):"
        entities.each do |entity|
          puts "    - #{entity[:value]}"
        end
      end

      puts "\n#{'-' * 80}\n"
    end

    # Log completion
    puts "Inventory generation completed at #{Time.current}"
  end

  desc "Export content and entity inventory to a CSV file"
  task export_csv: :environment do
    require "csv"

    filename = Rails.root.join("tmp", "content_entity_inventory_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv")

    CSV.open(filename, "wb") do |csv|
      # Header row
      csv << ["Content ID", "Created At", "Note", "Entity ID", "Entity Type", "Entity Value"]

      # Data rows
      Content.includes(:entities).find_each do |content|
        if content.entities.empty?
          # Include content with no entities
          csv << [content.id, content.created_at, content.note&.truncate(100), nil, nil, nil]
        else
          # Include content with each of its entities
          content.entities.each do |entity|
            csv << [content.id, content.created_at, content.note&.truncate(100), entity.id, entity.entity_type, entity.value]
          end
        end
      end
    end

    puts "CSV export completed: #{filename}"
  end
end
