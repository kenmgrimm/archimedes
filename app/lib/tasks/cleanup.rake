namespace :cleanup do
  desc "Remove duplicate entities with the same entity_type and value"
  task deduplicate_entities: :environment do
    puts "Starting entity deduplication..."

    # Find all entity types and values that have duplicates
    duplicates = Entity.select(:entity_type, :value)
                       .group(:entity_type, :value)
                       .having("COUNT(*) > 1")

    puts "Found #{duplicates.length} unique entity type/value combinations with duplicates"

    # For each duplicate set, keep the first one and delete the rest
    duplicates.each do |dup|
      entities = Entity.where(entity_type: dup.entity_type, value: dup.value).order(:id)

      # Keep the first one (oldest by ID)
      keeper = entities.first

      # Get the rest to delete
      to_delete = entities.where.not(id: keeper.id)

      puts "Keeping entity ##{keeper.id} (#{keeper.entity_type}: #{keeper.value})"
      puts "Deleting #{to_delete.count} duplicate entities: #{to_delete.pluck(:id).join(', ')}"

      # Delete the duplicates
      to_delete.destroy_all
    end

    puts "Entity deduplication complete!"
  end
end
