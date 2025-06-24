class AddOpenAIResponseToContents < ActiveRecord::Migration[7.1]
  def change
    add_column :contents, :openai_response, :jsonb
  end
end
