class AddUserDetailsToUsers < ActiveRecord::Migration[7.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :full_name, null: false
      t.string :given_name, null: false
      t.string :family_name, null: false
      t.string :phone
      t.date :birth_date
      t.jsonb :aliases, null: false, default: []
    end

    # Add indexes for faster lookups
    add_index :users, :given_name
    add_index :users, :family_name
    add_index :users, :aliases, using: :gin
  end
end
