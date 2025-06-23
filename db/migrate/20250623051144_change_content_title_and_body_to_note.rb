class ChangeContentTitleAndBodyToNote < ActiveRecord::Migration[7.1]
  def change
    remove_column :contents, :title, :string
    remove_column :contents, :body, :text
    add_column :contents, :note, :text
  end
end
