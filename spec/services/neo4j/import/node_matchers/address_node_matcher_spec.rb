require 'rails_helper'

RSpec.describe Neo4j::Import::NodeMatchers::AddressNodeMatcher do
  let(:matcher) { described_class }
  
  describe '.normalize_street' do
    it 'normalizes street names with common suffixes' do
      expect(matcher.normalize_street('123 Main Street')).to eq('123 main st')
      expect(matcher.normalize_street('456 Oak Avenue')).to eq('456 oak ave')
      expect(matcher.normalize_street('789 Park Road')).to eq('789 park rd')
      expect(matcher.normalize_street('101 Elm Blvd.')).to eq('101 elm blvd')
    end
    
    it 'handles directional indicators' do
      expect(matcher.normalize_street('123 North Main Street')).to eq('123 n main st')
      expect(matcher.normalize_street('456 South West 5th Ave')).to eq('456 s w 5th ave')
    end
    
    it 'removes punctuation and normalizes whitespace' do
      expect(matcher.normalize_street('123 Main St., Apt. 4B')).to eq('123 main st apt 4b')
      expect(matcher.normalize_street('100  -  200  Main   St')).to eq('100 200 main st')
    end
  end
  
  describe '.normalize_city' do
    it 'normalizes common city name variations' do
      expect(matcher.normalize_city('San Francisco')).to eq('san francisco')
      expect(matcher.normalize_city('New York City')).to eq('new york')
      expect(matcher.normalize_city('Los Angeles, CA')).to eq('los angeles')
    end
    
    it 'handles special cases' do
      expect(matcher.normalize_city('St. Louis')).to eq('st louis')
      expect(matcher.normalize_city('Fort Worth')).to eq('ft worth')
      expect(matcher.normalize_city('Mount Vernon')).to eq('mt vernon')
    end
  end
  
  describe '.normalize_state' do
    it 'normalizes state names to abbreviations' do
      expect(matcher.normalize_state('California')).to eq('CA')
      expect(matcher.normalize_state('new york')).to eq('NY')
      expect(matcher.normalize_state('tx')).to eq('TX')
    end
    
    it 'returns the original string if no mapping found' do
      expect(matcher.normalize_state('Unknown State')).to eq('Unknown State')
    end
  end
  
  describe '.normalized_address_match' do
    let(:address1) do
      {
        'street' => '123 Main St',
        'city' => 'San Francisco',
        'state' => 'CA',
        'postalCode' => '94105',
        'country' => 'USA'
      }
    end
    
    it 'matches identical addresses' do
      address2 = address1.dup
      expect(matcher.normalized_address_match(address1, address2)).to be true
    end
    
    it 'matches addresses with minor variations' do
      address2 = {
        'street' => '123 Main Street',  # St vs Street
        'city' => 'San Francisco',
        'state' => 'CA',
        'postalCode' => '94105',
        'country' => 'USA'
      }
      expect(matcher.normalized_address_match(address1, address2)).to be true
    end
    
    it 'does not match different addresses' do
      address2 = {
        'street' => '456 Oak Ave',
        'city' => 'San Francisco',
        'state' => 'CA',
        'postalCode' => '94105',
        'country' => 'USA'
      }
      expect(matcher.normalized_address_match(address1, address2)).to be false
    end
  end
  
  describe '.street_number_street_name_match' do
    it 'matches addresses with the same street number and name' do
      props1 = { 'street' => '123 Main St', 'city' => 'San Francisco' }
      props2 = { 'street' => '123 Main Street', 'city' => 'San Francisco' }
      expect(matcher.street_number_street_name_match(props1, props2)).to be true
    end
    
    it 'does not match different street numbers' do
      props1 = { 'street' => '123 Main St', 'city' => 'San Francisco' }
      props2 = { 'street' => '124 Main St', 'city' => 'San Francisco' }
      expect(matcher.street_number_street_name_match(props1, props2)).to be false
    end
  end
  
  describe '.city_state_zip_match' do
    it 'matches addresses with same city, state and zip' do
      props1 = { 'city' => 'San Francisco', 'state' => 'CA', 'postalCode' => '94105' }
      props2 = { 'city' => 'San Francisco', 'state' => 'CA', 'postalCode' => '94105' }
      expect(matcher.city_state_zip_match(props1, props2)).to be true
    end
    
    it 'handles zip code variations' do
      props1 = { 'city' => 'San Francisco', 'state' => 'CA', 'postalCode' => '94105-1234' }
      props2 = { 'city' => 'San Francisco', 'state' => 'CA', 'postalCode' => '94105' }
      expect(matcher.city_state_zip_match(props1, props2)).to be true
    end
  end
end
