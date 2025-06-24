class MigrateEntitiesToV2Model < ActiveRecord::Migration[7.1]
  # This migration requires both up and down methods since it's a data migration
  def up
    # Add debug logging
    say_with_time "Migrating entities from V1 to V2 model" do
      # Get all entities
      execute("SELECT id, name, content_id FROM entities").each do |entity|
        entity_id = entity['id']
        entity_name = entity['name']
        content_id = entity['content_id']
        
        # For each entity, create a statement with its type information (if available from previous data)
        # We'll use a direct SQL approach to avoid model validation issues during migration
        say "Creating statements for entity #{entity_id}: #{entity_name}"
        
        # Create a basic statement for each entity
        execute(<<~SQL)
          INSERT INTO statements 
            (entity_id, content_id, text, confidence, created_at, updated_at)
          VALUES 
            (#{entity_id}, #{content_id}, 'This is #{entity_name}', 1.0, NOW(), NOW())
        SQL
        
        # If we had previous entity_type data, we could create statements like:
        # "#{entity_name} is a #{entity_type}"
        # But since we've already removed the type column, we can't do this
        # This would be the place to add that logic if we still had access to the type data
      end
      
      say "Successfully migrated entities to V2 model"
    end
  end
  
  def down
    # Remove all statements created during migration
    say_with_time "Rolling back entity migration from V2 to V1 model" do
      execute("DELETE FROM statements")
      say "Removed all statements"
    end
  end
end
