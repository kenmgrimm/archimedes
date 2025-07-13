#!/usr/bin/env ruby
require_relative "../config/environment"

# Enable debug mode for detailed output
$debug_mode = true

# Test the AddressNodeMatcher
matcher = Neo4j::Import::NodeMatchers::AddressNodeMatcher

puts "Testing AddressNodeMatcher..."

# Test normalize_street
puts "\n=== Testing normalize_street ==="
test_cases = [
  "123 Main Street",
  "456 Oak Avenue",
  "789 Park Road",
  "101 Elm Blvd.",
  "123 North Main Street",
  "456 South West 5th Ave",
  "123 Main St., Apt. 4B",
  "100  -  200  Main   St"
]

test_cases.each do |street|
  puts "#{street} => #{matcher.send(:normalize_street, street)}"
end

# Test normalize_city
puts "\n=== Testing normalize_city ==="
test_cases = [
  "San Francisco",
  "New York City",
  "Los Angeles, CA",
  "St. Louis",
  "Fort Worth",
  "Mount Vernon"
]

test_cases.each do |city|
  puts "#{city} => #{matcher.send(:normalize_city, city)}"
end

# Test normalize_state
puts "\n=== Testing normalize_state ==="
test_cases = [
  "California",
  "new york",
  "tx",
  "Unknown State"
]

test_cases.each do |state|
  puts "#{state} => #{matcher.send(:normalize_state, state)}"
end

# Test address matching
puts "\n=== Testing address matching ==="
address1 = {
  "street" => "123 Main St",
  "city" => "San Francisco",
  "state" => "CA",
  "postalCode" => "94105",
  "country" => "USA"
}

address2 = {
  "street" => "123 Main Street", # St vs Street
  "city" => "San Francisco",
  "state" => "CA",
  "postalCode" => "94105",
  "country" => "USA"
}

address3 = {
  "street" => "456 Oak Ave",
  "city" => "San Francisco",
  "state" => "CA",
  "postalCode" => "94105",
  "country" => "USA"
}

puts "Address 1: #{address1}"
puts "Address 2: #{address2}"
puts "Address 3: #{address3}"

puts "\nMatching address1 with address2 (should match): #{matcher.send(:normalized_address_match, address1, address2)}"
puts "Matching address1 with address3 (should not match): #{matcher.send(:normalized_address_match, address1, address3)}"
