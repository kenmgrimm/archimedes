# frozen_string_literal: true

class CreateV3KnowledgeGraphSchema < ActiveRecord::Migration[7.0]
  def change
    # Update statements table with additional indexes for knowledge graph structure
    # Note: predicate, object, and object_type were added in the previous migration
    change_table :statements do |t|
      # Add compound indexes for efficient querying
      t.index [:entity_id, :predicate]
      t.index [:object_entity_id, :predicate]
    end
    
    # Create a verification_requests table to track entity verification workflow
    create_table :verification_requests do |t|
      t.references :content, null: false, foreign_key: true
      t.string :candidate_name, null: false
      t.string :status, default: 'pending'
      t.json :similar_entities
      t.json :pending_statements
      t.references :verified_entity, foreign_key: { to_table: :entities }
      t.timestamps
      
      t.index [:content_id, :candidate_name], unique: true
    end
    
    # Create entity_merges table to track merge history
    create_table :entity_merges do |t|
      t.references :source_entity, foreign_key: { to_table: :entities }
      t.references :target_entity, null: false, foreign_key: { to_table: :entities }
      t.integer :transferred_statements_count
      t.string :initiated_by
      t.timestamps
    end
    
    # Add verification status to entities
    add_column :entities, :verification_status, :string, default: 'verified'
    add_column :entities, :verified_at, :datetime
    add_column :entities, :verified_by, :string
    
    # Add metadata to statements
    add_column :statements, :source, :string
    add_column :statements, :extraction_method, :string, default: 'ai'
    
    # Add timestamps to statements if they don't exist
    unless column_exists?(:statements, :created_at)
      add_column :statements, :created_at, :datetime
    end
    
    unless column_exists?(:statements, :updated_at)
      add_column :statements, :updated_at, :datetime
    end
  end
end
