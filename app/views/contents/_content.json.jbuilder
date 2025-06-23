json.extract! content, :id, :title, :body, :created_at, :updated_at
json.url content_url(content, format: :json)
