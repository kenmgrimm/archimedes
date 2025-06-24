class UpdateEntityForV2Model < ActiveRecord::Migration[7.1]
  def change
    # Add debug logging
    say_with_time "Updating Entity model for V2" do
      # Rename 'value' column to 'name' if it exists
      if column_exists?(:entities, :value)
        rename_column :entities, :value, :name
      end
      
      # Remove 'entity_type' column if it exists
      if column_exists?(:entities, :entity_type)
        remove_column :entities, :entity_type, :string
      end
      
      # Rename 'value_embedding' to 'name_embedding' if it exists
      if column_exists?(:entities, :value_embedding)
        rename_column :entities, :value_embedding, :name_embedding
      end
      
      # Add index on name for faster lookups if it doesn't already exist
      unless index_exists?(:entities, :name)
        add_index :entities, :name
      end
      
      say "Entity model updated for V2"
    end
  end
end
