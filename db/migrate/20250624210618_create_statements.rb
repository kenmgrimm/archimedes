class CreateStatements < ActiveRecord::Migration[7.1]
  def change
    # Add debug logging
    say_with_time "Creating Statements table for V2 data model" do
      # Enable pgvector extension if not already enabled
      enable_extension 'vector' unless extension_enabled?('vector')
      
      # Debug logging
      say "Using pgvector extension for vector columns"
      
      create_table :statements do |t|
        # References
        t.references :entity, null: false, index: true, comment: 'Subject entity'
        t.references :object_entity, null: true, index: true, comment: 'Optional object entity for relationships'
        t.references :content, null: false, index: true, comment: 'Source content'
        
        # Content
        t.text :text, null: false, comment: 'The statement text'
        
        # Vector embedding - using execute for proper pgvector syntax
        # We'll add this after the table is created
        
        # Metadata
        t.float :confidence, default: 1.0, comment: 'Confidence score (0-1)'
        
        t.timestamps
      end
      
      # Add vector column using proper SQL syntax
      execute "ALTER TABLE statements ADD COLUMN text_embedding vector(1536)"
      
      # Add index for vector search
      execute "CREATE INDEX statements_text_embedding_idx ON statements USING ivfflat (text_embedding vector_cosine_ops)"
      
      say "Statements table created successfully"
    end
  end
end
