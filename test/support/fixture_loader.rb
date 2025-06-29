# test/support/fixture_loader.rb
module FixtureLoader
  def self.load_fixture(namespace, fixture_name)
    fixture_path = Rails.root.join("test/fixtures/#{namespace}/#{fixture_name}.yml")
    YAML.load_file(fixture_path, aliases: true)[fixture_name]
  end
  
  def self.load_winnie_the_pooh_fixture(fixture_name)
    load_fixture('winnie_the_pooh', fixture_name)
  end
end
