# frozen_string_literal: true

namespace :data_migration do
  desc "Migrate statement data to V3 knowledge graph format"
  task statements_to_knowledge_graph: :environment do
    # This task migrates existing statement data to the new knowledge graph format
    # It extracts subject-predicate-object triples from the text field

    # Add comprehensive debug logging
    puts "Starting migration of statements to knowledge graph format"
    puts "Total statements to process: #{Statement.count}"

    # Track statistics
    stats = {
      processed: 0,
      updated: 0,
      skipped: 0,
      errors: 0
    }

    # Process statements in batches to avoid memory issues
    Statement.find_each(batch_size: 100) do |statement|
      begin
        Rails.logger.debug { "Processing statement ##{statement.id}: #{statement.text&.truncate(50)}" } if ENV["DEBUG"]
        stats[:processed] += 1

        # Skip statements that already have predicate and object set
        if statement.predicate.present? && statement.object.present?
          Rails.logger.debug { "Statement ##{statement.id} already has predicate and object, skipping" } if ENV["DEBUG"]
          stats[:skipped] += 1
          next
        end

        # Extract predicate and object from text
        # This is a simplified approach - in production you might want to use NLP
        # or a more sophisticated parsing approach
        text = statement.text.to_s

        # Try to extract subject-predicate-object pattern
        # Look for common patterns like "X is Y", "X has Y", etc.
        if text.include?(" is ")
          predicate = "is"
          object = text.split(" is ").last.strip
        elsif text.include?(" has ")
          predicate = "has"
          object = text.split(" has ").last.strip
        elsif text.include?(" was ")
          predicate = "was"
          object = text.split(" was ").last.strip
        elsif text.include?(" contains ")
          predicate = "contains"
          object = text.split(" contains ").last.strip
        else
          # Default case - use the whole text as object with a generic predicate
          predicate = "has attribute"
          object = text.strip
        end

        # Determine object type based on object_entity_id
        object_type = statement.object_entity_id.present? ? "entity" : "literal"

        # Update the statement
        statement.update(
          predicate: predicate,
          object: object,
          object_type: object_type
        )

        if ENV["DEBUG"]
          Rails.logger.debug do
            "Updated statement ##{statement.id} with predicate: '#{predicate}', object: '#{object}', type: #{object_type}"
          end
        end
        stats[:updated] += 1
      rescue StandardError => e
        Rails.logger.error "Error processing statement ##{statement.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        stats[:errors] += 1
      end

      # Print progress every 100 statements
      if (stats[:processed] % 100).zero?
        puts "Processed #{stats[:processed]} statements (Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]})"
      end
    end

    # Print final statistics
    puts "\nMigration completed!"
    puts "Total processed: #{stats[:processed]}"
    puts "Updated: #{stats[:updated]}"
    puts "Skipped: #{stats[:skipped]}"
    puts "Errors: #{stats[:errors]}"
  end

  desc "Analyze entity duplication and suggest merges"
  task analyze_entity_duplication: :environment do
    require "csv"

    puts "Analyzing entity duplication..."

    # Find entities with similar names
    entities = Entity.all.to_a
    similar_entities = []

    # Generate a CSV file with potential duplicates
    filename = Rails.root.join("tmp", "entity_duplicates_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv")

    CSV.open(filename, "wb") do |csv|
      # Header row
      csv << ["Entity 1 ID", "Entity 1 Name", "Entity 2 ID", "Entity 2 Name", "Name Similarity", "Statement Count 1", "Statement Count 2"]

      # Compare each entity with every other entity
      # This is O(n²) but fine for a one-time analysis
      entities.each_with_index do |entity1, i|
        Rails.logger.debug { "Analyzing entity ##{entity1.id}: #{entity1.name}" } if ENV["DEBUG"] && (i % 100).zero?

        entities[(i + 1)..].each do |entity2|
          # Skip if entities are identical
          next if entity1.id == entity2.id

          # Calculate name similarity (simple case-insensitive comparison)
          # In production, you would use a more sophisticated similarity metric
          name1 = entity1.name.to_s.downcase
          name2 = entity2.name.to_s.downcase

          # Calculate Levenshtein distance or other similarity metric
          # Here we use a simple approach - in production use vector similarity
          similarity = calculate_similarity(name1, name2)

          # If similarity is above threshold, add to potential duplicates
          next unless similarity > 0.8

          csv << [
            entity1.id,
            entity1.name,
            entity2.id,
            entity2.name,
            similarity.round(2),
            entity1.statements.count,
            entity2.statements.count
          ]

          similar_entities << [entity1, entity2, similarity]
        end
      end
    end

    # Print results
    puts "Found #{similar_entities.size} potential duplicate entity pairs"
    puts "Results saved to #{filename}"
    puts "Top 10 most similar entities:"

    similar_entities.sort_by { |pair| -pair[2] }.first(10).each do |entity1, entity2, similarity|
      puts "#{entity1.name} (ID: #{entity1.id}) <-> #{entity2.name} (ID: #{entity2.id}): #{(similarity * 100).round(1)}% similar"
    end
  end

  private

  # Simple string similarity calculation
  # In production, use vector embeddings for better results
  def calculate_similarity(str1, str2)
    # Jaccard similarity of character trigrams
    return 0 if str1.empty? || str2.empty?

    # Generate character trigrams
    trigrams1 = (0..(str1.length - 3)).to_set { |i| str1[i, 3] }
    trigrams2 = (0..(str2.length - 3)).to_set { |i| str2[i, 3] }

    # Calculate Jaccard similarity
    intersection = trigrams1 & trigrams2
    union = trigrams1 | trigrams2

    return 0 if union.empty?

    intersection.size.to_f / union.size
  end
end
