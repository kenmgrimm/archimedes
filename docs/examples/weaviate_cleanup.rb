#!/usr/bin/env ruby

require "weaviate"
require "net/http"
require "json"

# Initialize Weaviate client
client = Weaviate::Client.new(url: "http://localhost:8080")

puts "🧹 Cleaning up Weaviate database..."

# Method 1: Delete all objects (keeps schema)
def delete_all_objects(client)
  classes = ["Person", "Pet", "Place", "Project", "Document", "List", "ListItem"]

  classes.each do |class_name|
    puts "Deleting all #{class_name} objects..."

    # Get all objects of this class
    response = client.objects.list(class_name: class_name)
    objects = response["objects"] || []

    # Delete each object individually
    objects.each do |obj|
      client.objects.delete(class_name: class_name, id: obj["id"])
      puts "  ✓ Deleted #{class_name} #{obj['id'][0..7]}..."
    rescue StandardError => e
      puts "  ✗ Failed to delete #{obj['id']}: #{e.message}"
    end

    puts "  Finished cleaning #{class_name} (#{objects.length} objects)"
  end
end

# Method 2: Delete entire schema classes (nuclear option)
def delete_schema_classes(client)
  classes = ["Person", "Pet", "Place", "Project", "Document", "List", "ListItem"]

  classes.each do |class_name|
    puts "Deleting schema class: #{class_name}"
    client.schema.delete(class_name: class_name)
    puts "  ✓ Deleted #{class_name} schema"
  rescue StandardError => e
    puts "  ✗ Failed to delete #{class_name} schema: #{e.message}"
  end
end

# Choose cleanup method
puts "\nChoose cleanup method:"
puts "1. Delete all objects (keeps schema structure)"
puts "2. Delete entire schema classes (nuclear option)"
print "Enter choice (1 or 2): "

choice = gets.chomp

case choice
when "1"
  delete_all_objects(client)
  puts "\n✅ All objects deleted. Schema structure preserved."
when "2"
  delete_schema_classes(client)
  puts "\n✅ All schema classes deleted. Database completely reset."
else
  puts "Invalid choice. Exiting."
  exit 1
end

puts "\n🎉 Weaviate cleanup complete!"
