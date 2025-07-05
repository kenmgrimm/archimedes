# frozen_string_literal: true

module Neo4j
  module Importers
    module Entities
      # Importer for Person entities
      class PersonImporter < BaseEntityImporter
        def self.handles
          "Person"
        end

        def required_properties
          [:name]
        end

        def property_mappings
          {
            givenName: :first_name,
            familyName: :last_name,
            email: :email,
            telephone: :phone,
            birthDate: :birth_date,
            jobTitle: :job_title,
            worksFor: :employer,
            sameAs: :external_ids
          }
        end

        private

        def validate_entity_specific_rules
          # Ensure email is valid if present
          if @entity_data["email"].present? && !valid_email?(@entity_data["email"])
            return add_error("Invalid email format: #{@entity_data['email']}", @entity_data)
          end

          # Ensure birth date is valid if present
          if @entity_data["birthDate"].present? && !valid_date?(@entity_data["birthDate"])
            return add_error("Invalid birth date format: #{@entity_data['birthDate']}", @entity_data)
          end

          true
        end

        def find_existing_entity(properties)
          # First try to find by email if available
          if properties[:email].present?
            existing = Person.find_by(email: properties[:email].downcase)
            return existing if existing
          end

          # Then try to find by name and birth date if available
          if properties[:first_name].present? && properties[:last_name].present?
            query = Person.where(
              first_name: properties[:first_name].strip,
              last_name: properties[:last_name].strip
            )

            query = query.where(birth_date: properties[:birth_date]) if properties[:birth_date].present?

            return query.first
          end

          nil
        end

        def valid_email?(email)
          email =~ URI::MailTo::EMAIL_REGEXP
        end

        def valid_date?(date_str)
          Date.parse(date_str)
        rescue StandardError
          false
        end
      end
    end
  end
end
