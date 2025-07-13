# frozen_string_literal: true

module Neo4j
  module Import
    module NodeMatchers
      # Matcher for Address nodes
      class AddressNodeMatcher < BaseNodeMatcher
        # US state abbreviations mapping with common variations
        STATE_MAPPINGS = {
          # Full state names (uppercase)
          "ALABAMA" => "AL", "ALASKA" => "AK", "ARIZONA" => "AZ", "ARKANSAS" => "AR",
          "CALIFORNIA" => "CA", "COLORADO" => "CO", "CONNECTICUT" => "CT", "DELAWARE" => "DE",
          "FLORIDA" => "FL", "GEORGIA" => "GA", "HAWAII" => "HI", "IDAHO" => "ID",
          "ILLINOIS" => "IL", "INDIANA" => "IN", "IOWA" => "IA", "KANSAS" => "KS",
          "KENTUCKY" => "KY", "LOUISIANA" => "LA", "MAINE" => "ME", "MARYLAND" => "MD",
          "MASSACHUSETTS" => "MA", "MICHIGAN" => "MI", "MINNESOTA" => "MN", "MISSISSIPPI" => "MS",
          "MISSOURI" => "MO", "MONTANA" => "MT", "NEBRASKA" => "NE", "NEVADA" => "NV",
          "NEW HAMPSHIRE" => "NH", "NEW JERSEY" => "NJ", "NEW MEXICO" => "NM", "NEW YORK" => "NY",
          "NORTH CAROLINA" => "NC", "NORTH DAKOTA" => "ND", "OHIO" => "OH", "OKLAHOMA" => "OK",
          "OREGON" => "OR", "PENNSYLVANIA" => "PA", "RHODE ISLAND" => "RI", "SOUTH CAROLINA" => "SC",
          "SOUTH DAKOTA" => "SD", "TENNESSEE" => "TN", "TEXAS" => "TX", "UTAH" => "UT",
          "VERMONT" => "VT", "VIRGINIA" => "VA", "WASHINGTON" => "WA", "WEST VIRGINIA" => "WV",
          "WISCONSIN" => "WI", "WYOMING" => "WY",
          # US territories
          "AMERICAN SAMOA" => "AS", "DISTRICT OF COLUMBIA" => "DC", "GUAM" => "GU",
          "MARSHALL ISLANDS" => "MH", "FEDERATED STATES OF MICRONESIA" => "FM",
          "NORTHERN MARIANA ISLANDS" => "MP", "PALAU" => "PW", "PUERTO RICO" => "PR",
          "VIRGIN ISLANDS" => "VI", "U.S. VIRGIN ISLANDS" => "VI",
          # Common variations (title case, mixed case)
          "California" => "CA", "New York" => "NY", "Texas" => "TX", "Florida" => "FL",
          "Illinois" => "IL", "Pennsylvania" => "PA", "Ohio" => "OH", "Georgia" => "GA",
          "North Carolina" => "NC", "Michigan" => "MI", "New Jersey" => "NJ", "Virginia" => "VA",
          "Washington" => "WA", "Arizona" => "AZ", "Massachusetts" => "MA", "Tennessee" => "TN",
          "Indiana" => "IN", "Missouri" => "MO", "Maryland" => "MD", "Wisconsin" => "WI",
          "Minnesota" => "MN", "Colorado" => "CO", "Alabama" => "AL", "South Carolina" => "SC",
          "Louisiana" => "LA", "Kentucky" => "KY", "Oregon" => "OR", "Oklahoma" => "OK",
          "Connecticut" => "CT", "Utah" => "UT", "Iowa" => "IA", "Nevada" => "NV",
          "Arkansas" => "AR", "Mississippi" => "MS", "Kansas" => "KS", "New Mexico" => "NM",
          "Nebraska" => "NE", "West Virginia" => "WV", "Idaho" => "ID", "Hawaii" => "HI",
          "New Hampshire" => "NH", "Maine" => "ME", "Montana" => "MT", "Rhode Island" => "RI",
          "Delaware" => "DE", "South Dakota" => "SD", "North Dakota" => "ND", "Alaska" => "AK",
          "Vermont" => "VT", "Wyoming" => "WY", "District of Columbia" => "DC",
          "Puerto Rico" => "PR", "Guam" => "GU", "American Samoa" => "AS", "Virgin Islands" => "VI"
        }.freeze

        class << self
          def embedding_properties
            ["street", "city", "state", "country", "postalCode", "notes"]
          end

          def fuzzy_equality_methods
            [
              :normalized_address_match,
              :street_number_street_name_match,
              :city_state_zip_match,
              :coordinate_proximity_match
            ].tap do |methods|
              log_debug("\n=== Available fuzzy matching methods: #{methods.join(', ')} ===")
            end
          end

          def similarity_threshold
            0.75
          end

          private

          def normalized_address_match(props1, props2)
            log_debug("\n=== Normalized Address Match ===") if $debug_mode
            log_debug("Original Props 1: #{props1.inspect}") if $debug_mode
            log_debug("Original Props 2: #{props2.inspect}") if $debug_mode

            # Normalize both addresses
            norm1 = normalize_address(props1)
            norm2 = normalize_address(props2)

            log_debug("Normalized Address 1: #{norm1.inspect}") if $debug_mode
            log_debug("Normalized Address 2: #{norm2.inspect}") if $debug_mode

            # Check for exact match
            if norm1 == norm2
              log_debug("✅ Exact match on normalized addresses") if $debug_mode
              return true
            end

            # Check if one is a subset of the other (e.g., one has more components)
            if norm1.include?(norm2) || norm2.include?(norm1)
              log_debug("✅ One address is a subset of the other") if $debug_mode
              return true
            end

            # Check individual components for partial matches
            if city_state_zip_match(props1, props2)
              log_debug("✅ City/State/ZIP match") if $debug_mode
              return true
            end

            # Check similarity of normalized addresses
            similarity = string_similar?(norm1, norm2, 0.85) # Slightly lower threshold
            log_debug("Normalized address similarity: #{similarity ? 'high' : 'low'}") if $debug_mode

            unless similarity
              log_debug("❌ Addresses don't match:") if $debug_mode
              log_debug("  - Address 1: #{norm1}") if $debug_mode
              log_debug("  - Address 2: #{norm2}") if $debug_mode
            end

            similarity
          end

          def normalize_address(props)
            log_debug("\n=== Normalizing Address ===") if $debug_mode
            log_debug("Original props: #{props.inspect}") if $debug_mode

            # Extract and normalize components
            street = normalize_street(props["street"].to_s)
            city = normalize_city(props["city"].to_s)
            state = normalize_state(props["state"].to_s)
            zip = props["postalCode"].to_s.gsub(/\D/, "").first(5)
            country = normalize_country(props["country"].to_s)

            # Build normalized components array
            components = [
              street,
              [city, state, zip].reject(&:empty?).join(" "),
              country
            ].reject(&:empty?)

            normalized = components.join(", ").downcase

            log_debug("Normalized components:") if $debug_mode
            log_debug("- Street: #{street}") if $debug_mode
            log_debug("- City/State/ZIP: #{[city, state, zip].reject(&:empty?).join(' ')}") if $debug_mode
            log_debug("- Country: #{country}") if $debug_mode
            log_debug("Final normalized: #{normalized}") if $debug_mode

            normalized
          end

          def normalize_street(street)
            return "" if street.blank?

            normalized = street.downcase
                               .gsub(/[,\.]/, "") # Remove commas and periods
                               .gsub(/\s+/, " ") # Normalize whitespace
                               .strip

            # Standard street suffix replacements
            street_suffixes = {
              /\b(st|street)\b/ => "st",
              /\b(ave|avenue)\b/ => "ave",
              /\b(rd|road)\b/ => "rd",
              /\b(blvd|boulevard)\b/ => "blvd",
              /\b(ln|lane)\b/ => "ln",
              /\b(dr|drive)\b/ => "dr",
              /\b(ct|court)\b/ => "ct",
              /\b(pl|place)\b/ => "pl",
              /\b(terr|terrace)\b/ => "terr",
              /\b(pkwy|parkway)\b/ => "pkwy",
              /\b(hwy|highway)\b/ => "hwy"
            }

            # Directional replacements
            directions = {
              "north" => "n", "northeast" => "ne", "northwest" => "nw",
              "south" => "s", "southeast" => "se", "southwest" => "sw",
              "east" => "e", "west" => "w"
            }

            # Apply street suffix replacements
            street_suffixes.each do |pattern, replacement|
              normalized.gsub!(pattern, replacement)
            end

            # Apply directional replacements
            directions.each do |from, to|
              normalized.gsub!(/\b#{from}\b/, to)
            end

            # Remove any remaining non-word characters except spaces and numbers
            normalized.gsub(/[^\w\s\d]/, "").squeeze(" ").strip
          end

          def street_number_street_name_match(props1, props2)
            street1 = normalize_street(props1["street"].to_s)
            street2 = normalize_street(props2["street"].to_s)

            # If streets are identical, it's a match
            if street1 == street2
              log_debug("  Street names are identical: #{street1}")
              return true
            end

            # Extract street numbers and names
            num1, name1 = extract_street_components(street1)
            num2, name2 = extract_street_components(street2)

            log_debug("  Street 1 - Number: #{num1.inspect}, Name: #{name1.inspect}")
            log_debug("  Street 2 - Number: #{num2.inspect}, Name: #{name2.inspect}")

            # If either street is missing a number, just compare names
            if num1.blank? || num2.blank?
              similarity = string_similar?(name1, name2, 0.85) ? 1.0 : 0.0
              log_debug("  Missing street number, comparing names. Similarity: #{format('%.2f', similarity * 100)}%")
              return similarity >= 0.85
            end

            # Check if street numbers match
            numbers_match = num1 == num2
            log_debug("  Street numbers match: #{numbers_match} (#{num1} vs #{num2})")

            # Check name similarity
            names_similar = string_similar?(name1, name2, 0.8)
            log_debug("  Street name similarity: #{names_similar ? 'high' : 'low'}")

            # Match if street numbers are the same and names are similar
            result = numbers_match && names_similar
            log_debug("  Street match result: #{result}")
            result
          end

          def city_state_zip_match(props1, props2)
            log_debug("\n=== City/State/Zip Matching ===") if $debug_mode
            log_debug("Props1: #{props1.inspect}") if $debug_mode
            log_debug("Props2: #{props2.inspect}") if $debug_mode

            # Handle different property name conventions
            zip1 = props1["postalCode"] || props1["zip"]
            zip2 = props2["postalCode"] || props2["zip"]

            log_debug("\n[1/3] Checking city match:") if $debug_mode
            city1 = normalize_city(props1["city"].to_s)
            city2 = normalize_city(props2["city"].to_s)

            city_match = city1.downcase == city2.downcase

            log_debug("  City 1: #{props1['city'].inspect} -> #{city1.inspect}") if $debug_mode
            log_debug("  City 2: #{props2['city'].inspect} -> #{city2.inspect}") if $debug_mode
            log_debug("  City match: #{city_match}") if $debug_mode

            log_debug("\n[2/3] Checking state match:") if $debug_mode
            state1 = normalize_state(props1["state"].to_s)
            state2 = normalize_state(props2["state"].to_s)

            state_match = if state1.present? && state2.present?
                            exact_match = state1.downcase == state2.downcase
                            includes1 = state1.downcase.include?(state2.downcase)
                            includes2 = state2.downcase.include?(state1.downcase)

                            log_debug("  State comparison:") if $debug_mode
                            log_debug("    Exact match: #{exact_match}") if $debug_mode
                            log_debug("    State1 includes State2: #{includes1}") if $debug_mode
                            log_debug("    State2 includes State1: #{includes2}") if $debug_mode

                            exact_match || includes1 || includes2
                          else
                            false
                          end

            log_debug("  State 1: #{props1['state'].inspect} -> #{state1.inspect}") if $debug_mode
            log_debug("  State 2: #{props2['state'].inspect} -> #{state2.inspect}") if $debug_mode
            log_debug("  States match: #{state_match}") if $debug_mode

            log_debug("\n[3/3] Checking ZIP code match:") if $debug_mode
            original_zip1 = zip1
            original_zip2 = zip2
            zip1 = zip1.to_s.gsub(/\D/, "")[0..4] if zip1.present?
            zip2 = zip2.to_s.gsub(/\D/, "")[0..4] if zip2.present?
            zip_match = zip1.present? && zip2.present? && zip1 == zip2

            log_debug("  ZIP 1: #{original_zip1.inspect} -> #{zip1.inspect}") if $debug_mode
            log_debug("  ZIP 2: #{original_zip2.inspect} -> #{zip2.inspect}") if $debug_mode
            log_debug("  ZIPs match: #{zip_match}") if $debug_mode

            # Check combinations
            city_state_match = city_match && state_match
            zip_city_match = zip_match && city_match

            log_debug("\n[Combination Checks]:") if $debug_mode
            log_debug("  City && State match: #{city_state_match}") if $debug_mode
            log_debug("  ZIP && City match: #{zip_city_match}") if $debug_mode

            # If ZIP codes match, allow for some fuzziness in city and state names
            if zip_match
              log_debug("\n[Fuzzy Matching - ZIPs Match]")

              # Check city similarity if not already matched
              if !city_match && city1.present? && city2.present?
                similarity = string_similarity(city1, city2)
                city_similarity = similarity >= 0.7

                log_debug("  City similarity check:") if $debug_mode
                log_debug("    City1: #{city1}") if $debug_mode
                log_debug("    City2: #{city2}") if $debug_mode
                log_debug("    Similarity: #{format('%.2f', similarity * 100)}% (threshold: 70%)") if $debug_mode
                log_debug("    Similar enough: #{city_similarity}") if $debug_mode

                if city_similarity
                  city_state_match ||= true
                  zip_city_match = true
                  log_debug("  ✅ City names are similar enough") if $debug_mode
                end
              end

              # Check state similarity if not already matched and cities are similar
              if !state_match && state1.present? && state2.present? && (city_match || city_similarity)
                similarity = string_similarity(state1, state2)
                state_similarity = similarity >= 0.7

                log_debug("\n  State similarity check:") if $debug_mode
                log_debug("    State1: #{state1}") if $debug_mode
                log_debug("    State2: #{state2}") if $debug_mode
                log_debug("    Similarity: #{format('%.2f', similarity * 100)}% (threshold: 70%)") if $debug_mode
                log_debug("    Similar enough: #{state_similarity}") if $debug_mode

                if state_similarity
                  city_state_match = true
                  log_debug("  ✅ State names are similar enough") if $debug_mode
                end
              end
            end

            # Final result
            result = city_state_match || zip_city_match

            log_debug("\n[Final Result]:") if $debug_mode
            log_debug("  City/State match: #{city_state_match}") if $debug_mode
            log_debug("  ZIP/City match: #{zip_city_match}") if $debug_mode
            log_debug("  Overall match: #{result ? '✅ MATCH' : '❌ NO MATCH'}") if $debug_mode

            result
          end

          # Calculate string similarity score between 0.0 and 1.0
          # @param str1 [String] first string
          # @param str2 [String] second string
          # @return [Float] similarity score (0.0 to 1.0)
          def string_similarity(str1, str2)
            return 1.0 if str1 == str2
            return 0.0 if str1.blank? || str2.blank?

            # Simple similarity based on Jaro-Winkler distance
            max_length = [str1.length, str2.length].max.to_f
            distance = DidYouMean::Levenshtein.distance(str1.downcase, str2.downcase)
            1.0 - (distance / max_length)
          end

          def normalize_city(city)
            return "" if city.blank?

            # Common city name normalizations
            city = city.downcase.strip
                       .gsub(/\s+/, " ") # Normalize spaces
                       .gsub(/[^\w\s]/, "") # Remove punctuation
                       .gsub(/\b(st\.?|saint)\b/, "st") # Standardize 'saint' variations
                       .gsub(/\b(ft\.?|fort)\b/, "ft") # Standardize 'fort' variations
                       .gsub(/\b(mt\.?|mount)\b/, "mt") # Standardize 'mount' variations
                       .gsub(/\b(north|south|east|west)\b/) { |m| m[0] } # Abbreviate directions
                       .gsub(/\s+/, " ") # Normalize spaces again
                       .strip

            # Handle specific city name variations
            case city
            when "san fran", "sf", "s.f.", "san francisco ca"
              "san francisco"
            when "nyc", "new york city", "new york ny", "ny new york"
              "new york"
            when "la", "l.a.", "los angeles ca"
              "los angeles"
            when "chi", "chitown", "chicago il"
              "chicago"
            when "philly", "philadelphia pa"
              "philadelphia"
            when "san diego ca"
              "san diego"
            when "san jose ca"
              "san jose"
            when "austin tx"
              "austin"
            when "miami fl"
              "miami"
            when "seattle wa"
              "seattle"
            when "portland or", "portland me"
              "portland"
            when "washington dc", "washington d.c.", "washington district of columbia"
              "washington dc"
            else
              city
            end
          end

          def normalize_state(state)
            return "" if state.blank?

            normalized = state.to_s.strip

            # Try exact match first
            return STATE_MAPPINGS[normalized] if STATE_MAPPINGS.key?(normalized)

            # Try case-insensitive match
            upcased = normalized.upcase
            return STATE_MAPPINGS[upcased] if STATE_MAPPINGS.key?(upcased)

            # Try titleized match
            titleized = normalized.split.map(&:capitalize).join(" ")
            return STATE_MAPPINGS[titleized] if STATE_MAPPINGS.key?(titleized)

            # Try removing any trailing period (e.g., 'Calif.' -> 'Calif')
            no_period = normalized.gsub(/\.$/, "")
            return STATE_MAPPINGS[no_period] if STATE_MAPPINGS.key?(no_period)

            # Try common abbreviations without periods
            case normalized.downcase
            when "calif", "cal"
              "CA"
            when "colo", "col"
              "CO"
            when "conn", "ct"
              "CT"
            when "fla", "fl"
              "FL"
            when "ill", "il"
              "IL"
            when "mass", "ma"
              "MA"
            when "mich", "mi"
              "MI"
            when "minn", "mn"
              "MN"
            when "nebr", "neb", "ne"
              "NE"
            when "ore", "or"
              "OR"
            when "pa", "penn", "penna"
              "PA"
            when "tenn", "tn"
              "TN"
            when "tex", "tx"
              "TX"
            when "va", "virg"
              "VA"
            when "wash", "wa"
              "WA"
            when "wisc", "wis", "wi"
              "WI"
            when "wva", "w.va.", "w va", "west virginia"
              "WV"
            else
              normalized.upcase
            end
          end

          def normalize_country(country)
            return "usa" if country.blank?

            country = country.downcase.strip

            case country
            when "united states", "united states of america", "u.s.", "us", "usa", "u.s.a."
              "usa"
            when "united kingdom", "u.k.", "uk", "great britain", "gb", "g.b."
              "uk"
            when "canada", "ca", "can"
              "canada"
            when "australia", "aus", "au"
              "australia"
            when "germany", "de", "deu", "germany, federal republic of"
              "germany"
            when "france", "fr", "fra"
              "france"
            when "spain", "es", "esp"
              "spain"
            when "italy", "it", "ita"
              "italy"
            when "japan", "jp", "jpn"
              "japan"
            when "china", "cn", "chn"
              "china"
            else
              country
            end
          end

          def extract_street_components(street)
            return [nil, street] if street.blank?

            # Normalize the street string first
            normalized = street.downcase.strip.gsub(%r{[^\w\s\-/]}, "").gsub(/\s+/, " ")

            # Match various street number patterns:
            # - Simple number: "123 main st" -> ["123", "main st"]
            # - Number with letter: "123a main st" -> ["123a", "main st"]
            # - Fractional: "123 1/2 main st" -> ["123 1/2", "main st"]
            # - Hyphenated: "123-125 main st" -> ["123-125", "main st"]
            match = normalized.match(%r{^(\d+[\w\s\-/]*)\s+(.*)$})

            if match
              number = match[1].strip
              name = match[2].strip

              # If the number is a range (e.g., "123-125"), take the first number
              number = number.split("-").first.strip if number.include?("-")

              [number, name]
            else
              [nil, street]
            end
          end
        end
      end
    end
  end
end
