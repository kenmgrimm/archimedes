class AddDescriptionToEntities < ActiveRecord::Migration[7.1]
  def change
    add_column :entities, :description, :text
  end
end
