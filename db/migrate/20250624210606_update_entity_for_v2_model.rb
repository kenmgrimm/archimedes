class UpdateEntityForV2Model < ActiveRecord::Migration[7.1]
  def change
    # Add debug logging
    say_with_time "Updating Entity model for V2" do
      # Rename 'value' column to 'name'
      rename_column :entities, :value, :name
      
      # Remove 'type' column as it's no longer needed (will be in statements)
      remove_column :entities, :type, :string
      
      # Remove 'value_embedding' column as embeddings will be on statements
      remove_column :entities, :value_embedding, :vector
      
      # Add index on name for faster lookups
      add_index :entities, :name
      
      say "Entity model updated for V2"
    end
  end
end
