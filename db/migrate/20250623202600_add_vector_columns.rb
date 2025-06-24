# frozen_string_literal: true

class AddVectorColumns < ActiveRecord::Migration[7.0]
  def up
    # Step 1: Add vector columns without indexes first
    execute <<-SQL
      ALTER TABLE entities ADD COLUMN value_embedding vector(1536);
      ALTER TABLE contents ADD COLUMN note_embedding vector(1536);
    SQL
    
    # Step 2: Create indexes for similarity searches
    # Using a smaller number of lists for better compatibility with smaller datasets
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS index_entities_on_value_embedding 
      ON entities USING ivfflat (value_embedding vector_l2_ops) 
      WITH (lists = 10);
      
      CREATE INDEX IF NOT EXISTS index_contents_on_note_embedding 
      ON contents USING ivfflat (note_embedding vector_l2_ops) 
      WITH (lists = 10);
    SQL
    
    # Add debug logging
    Rails.logger.debug { "[Migration] Successfully added vector columns and indexes" }
  end
  
  def down
    # Remove indexes first
    execute <<-SQL
      DROP INDEX IF EXISTS index_entities_on_value_embedding;
      DROP INDEX IF EXISTS index_contents_on_note_embedding;
    SQL
    
    # Then remove columns
    execute <<-SQL
      ALTER TABLE entities DROP COLUMN IF EXISTS value_embedding;
      ALTER TABLE contents DROP COLUMN IF EXISTS note_embedding;
    SQL
    
    Rails.logger.debug { "[Migration] Successfully removed vector columns and indexes" }
  end
end
