# frozen_string_literal: true

# Migration to update the statements table for the V3 Knowledge Graph model
class UpdateStatementsForKnowledgeGraph < ActiveRecord::Migration[7.0]
  def change
    # Add new fields for the knowledge graph structure
    add_column :statements, :predicate, :string
    add_column :statements, :object, :string
    add_column :statements, :object_type, :string, default: "literal"
    
    # Add indexes to improve query performance
    add_index :statements, :predicate
    add_index :statements, :object_type
    
    # We'll need to migrate data from the text field to the new structure
    # This will be handled in a separate data migration task
    
    # Knowledge graph statements in subject-predicate-object format
    # Note: We would use set_table_comment in Rails 6.1+ but using a comment for now
    
    reversible do |dir|
      dir.up do
        # Add debug logging
        say_with_time "Adding knowledge graph fields to statements table" do
          # This is where we would add any complex data migration if needed
          execute "UPDATE statements SET object_type = 'entity' WHERE object_entity_id IS NOT NULL"
        end
      end
    end
  end
end
