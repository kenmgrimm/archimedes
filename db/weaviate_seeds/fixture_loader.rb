module WeaviateSeeds
  class FixtureLoader
    attr_reader :people_data, :pets_data, :places_data, :projects_data, :documents_data, :vehicles_data, :lists_data 

    def initialize
      @people_data = YAML.load_file(Rails.root.join('test/fixtures/winnie_the_pooh/people.yml')).with_indifferent_access
      @pets_data = YAML.load_file(Rails.root.join('test/fixtures/winnie_the_pooh/pets.yml')).with_indifferent_access
      @places_data = YAML.load_file(Rails.root.join('test/fixtures/winnie_the_pooh/places.yml')).with_indifferent_access
      @projects_data = YAML.load_file(Rails.root.join('test/fixtures/winnie_the_pooh/projects.yml')).with_indifferent_access
      @documents_data = YAML.load_file(Rails.root.join('test/fixtures/winnie_the_pooh/documents.yml')).with_indifferent_access
      @vehicles_data = YAML.load_file(Rails.root.join('test/fixtures/winnie_the_pooh/vehicles.yml')).with_indifferent_access
      @lists_data = YAML.load_file(Rails.root.join('test/fixtures/winnie_the_pooh/lists.yml')).with_indifferent_access
    end

    def fixture_by_key(class_name, key)
      case class_name
      when 'Person'
        @people_data[key]
      when 'Pet'
        @pets_data[key]
      when 'Place'
        @places_data[key]
      when 'Project'
        @projects_data[key]
      when 'Document'
        @documents_data[key]
      when 'Vehicle'
        @vehicles_data[key]
      when 'List'
        @lists_data[key]
      else
        raise "Unknown class name: #{class_name}"
      end
    end
  end
end