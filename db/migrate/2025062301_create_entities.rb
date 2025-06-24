class CreateEntities < ActiveRecord::Migration[7.1]
  def change
    create_table :entities do |t|
      t.integer :content_id, null: false
      t.string :entity_type, null: false
      t.string :value, null: false

      t.references :canonical_entity, foreign_key: false
      t.timestamps
    end
  end
end
