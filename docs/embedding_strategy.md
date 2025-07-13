# Node Type Embedding Strategy

This document outlines which properties should be used for generating embeddings for each node type in the Archimedes knowledge graph taxonomy. Properties marked with `*` are recommended for embedding generation to enable semantic similarity matching.

## Implementation Architecture

Each node type should have a dedicated class that defines:
1. **Embedding Properties**: Which properties to combine for semantic embedding generation
2. **Fuzzy Equality Methods**: Alternative matching strategies when embeddings aren't available or sufficient
3. **Similarity Thresholds**: Type-specific thresholds for embedding similarity matching

### Example Class Structure

```ruby
class PersonNodeMatcher
  def self.embedding_properties
    %w[name notes]
  end
  
  def self.generate_embedding_text(properties)
    [properties['name'], properties['notes']].compact.join('. ')
  end
  
  def self.fuzzy_equality_methods
    [
      :exact_email_match,
      :last_name_first_initial_match,
      :full_name_similarity
    ]
  end
  
  def self.similarity_threshold
    0.85
  end
  
  private
  
  def self.exact_email_match(props1, props2)
    props1['email'].present? && props1['email'] == props2['email']
  end
  
  def self.last_name_first_initial_match(props1, props2)
    # Match on last name + first initial
    # Implementation details...
  end
end
```

## Core Entity Types

### Address
**Purpose**: Physical locations where someone lives, works, or visits.

**Properties**:
- `street` * - Street name and number
- `street2` - Additional address line
- `city` * - City or town name
- `state` * - State, province, or region
- `postalCode` - Postal or ZIP code
- `country` * - Full country name
- `type` - Type of address (home, work, vacation, other)
- `primary` - Whether this is the primary address of this type
- `notes` * - Additional context or special instructions

**Embedding Strategy**: Combine address components for geographic similarity matching
**Rationale**: Addresses need fuzzy matching for abbreviations ("St" vs "Street", "CA" vs "California")

**Fuzzy Equality Methods**:
- `normalized_address_match`: Normalize street abbreviations, state codes, and postal formatting
- `street_number_street_name_match`: Match on street number + normalized street name only
- `city_state_zip_match`: Match on city + state + zip when street differs
- `coordinate_proximity_match`: Match based on geographic coordinates if available

**Similarity Threshold**: 0.75 (lower due to address variations)

---

### Person
**Purpose**: Human beings with whom the user interacts.

**Properties**:
- `name` * - Full name in display format
- `givenName` - First/given name
- `familyName` - Last/family name
- `middleName` - Middle name(s) or initial(s)
- `prefix` - Name prefix (Mr., Mrs., Dr., Prof.)
- `suffix` - Name suffix (Jr., Sr., III, PhD)
- `birthDate` - Date of birth
- `email` - Primary email address
- `phone` - Primary phone number
- `notes` * - Personal notes or reminders about this person

**Embedding Strategy**: Combine name variations with contextual notes
**Rationale**: Names can have variations, notes contain relationship context

**Fuzzy Equality Methods**:
- `exact_email_match`: Match on identical email addresses
- `exact_phone_match`: Match on identical phone numbers (normalized format)
- `last_name_first_initial_match`: Match on family name + first letter of given name
- `full_name_similarity`: Fuzzy string matching on full name with nickname handling
- `name_components_match`: Match on given name + family name separately

**Similarity Threshold**: 0.85 (higher due to name importance)

---

### ContactMethod
**Purpose**: Ways to contact someone.

**Properties**:
- `type` - Type of contact (email, phone, social, address)
- `value` - The contact information
- `label` - Label like "work", "home", "mobile"
- `preferred` - Whether this is the preferred method

**Embedding Strategy**: Not recommended for embeddings
**Rationale**: Structured data where exact matching is preferred

---

## Time-based Entities

### Event
**Purpose**: Scheduled occurrences with specific times.

**Properties**:
- `title` * - Event title
- `description` * - Event description
- `startTime` - When the event starts
- `endTime` - When the event ends
- `allDay` - Whether it's an all-day event
- `location` - Event location
- `status` - Event status (scheduled, tentative, confirmed, cancelled)
- `priority` - Event priority (high, medium, low)

**Embedding Strategy**: Combine title and description for thematic similarity
**Rationale**: Events have descriptive content that benefits from semantic matching

**Fuzzy Equality Methods**:
- `title_exact_match`: Match on identical event titles
- `title_similarity_match`: Fuzzy string matching on event titles
- `time_location_match`: Match on same time + location combination
- `recurring_event_match`: Match recurring events by pattern and title

**Similarity Threshold**: 0.80

---

## Productivity Entities

### List
**Purpose**: Collections of related items (shopping lists, to-do lists, checklists).

**Properties**:
- `name` * - Short, descriptive name for the list
- `description` * - Detailed explanation of the list's purpose
- `type` - Type of list (todo, shopping, checklist, inventory, other)
- `isShared` - Whether the list is shared with others
- `isArchived` - Whether the list is archived

**Embedding Strategy**: Combine name and description for purpose-based similarity
**Rationale**: Lists can have similar purposes and themes

---

### ListItem
**Purpose**: Individual entries in lists.

**Properties**:
- `name` * - Short description of the item
- `description` * - Additional details about the item
- `quantity` - How many of this item
- `unit` - Unit of measurement
- `isCompleted` - Whether the item is checked off
- `dueDate` - When this item is due
- `priority` - Item priority

**Embedding Strategy**: Combine name and description for item similarity
**Rationale**: Items can have variations in naming (e.g., "milk" vs "2% milk")

---

### Task
**Purpose**: Units of work that need to be completed.

**Properties**:
- `title` * - Short, action-oriented description
- `description` * - Detailed explanation of the task
- `status` - Task status (not_started, in_progress, on_hold, in_review, completed, cancelled)
- `priority` - Task priority (critical, high, medium, low)
- `dueDate` - When the task should be completed
- `startDate` - When work should begin
- `timeEstimate` - Estimated time required
- `timeSpent` - Actual time spent
- `completionPercentage` - Progress toward completion
- `isRecurring` - Whether the task repeats
- `recurrenceRule` - RRULE string for recurring tasks

**Embedding Strategy**: Combine title and description for work similarity
**Rationale**: Tasks have descriptive text and benefit from semantic matching for similar work

**Fuzzy Equality Methods**:
- `title_exact_match`: Match on identical task titles
- `title_similarity_match`: Fuzzy string matching on task titles with action verb normalization
- `description_keyword_match`: Match on key terms in task descriptions
- `recurring_task_match`: Match recurring tasks by pattern and title
- `project_task_match`: Match tasks within the same project context

**Similarity Threshold**: 0.82

---

### Reminder
**Purpose**: Notifications to be shown at specific times or conditions.

**Properties**:
- `message` * - The content of the reminder (only if substantial)
- `dueAt` - When the reminder should be triggered
- `status` - Reminder status (pending, completed, snoozed, dismissed)
- `method` - Reminder method (notification, email, sms, call, other)
- `isRecurring` - Whether the reminder repeats
- `recurrenceRule` - RRULE string for recurring reminders

**Embedding Strategy**: Use message only if substantial content
**Rationale**: Most reminders are short, but some may have detailed messages

---

## Project Management

### Project
**Purpose**: Collections of related tasks, resources, and milestones working toward common goals.

**Properties**:
- `name` * - Short, descriptive name for the project
- `description` * - Detailed explanation of purpose and scope
- `status` - Project status (planning, active, on_hold, completed, abandoned)
- `startDate` - Official start date
- `targetDate` - Expected completion date
- `actualEndDate` - When actually completed
- `budget` - Total budget
- `priority` - Project priority
- `isTemplate` - Whether this is a reusable template
- `settings` - Project-specific configuration

**Embedding Strategy**: Combine name and description for thematic similarity
**Rationale**: Projects have detailed descriptions and benefit from thematic similarity

**Fuzzy Equality Methods**:
- `name_exact_match`: Match on identical project names
- `name_similarity_match`: Fuzzy string matching on project names
- `description_theme_match`: Match on thematic keywords in descriptions
- `template_match`: Match projects created from the same template
- `scope_similarity_match`: Match projects with similar scope and goals

**Similarity Threshold**: 0.83

---

### Milestone
**Purpose**: Significant points or events in project timelines.

**Properties**:
- `name` * - Short, descriptive name
- `description` * - Detailed explanation (only if substantial)
- `dueDate` - When the milestone should be achieved
- `completedDate` - When actually achieved
- `isCritical` - Whether this is a critical path milestone

**Embedding Strategy**: Use name and description only if description is substantial
**Rationale**: Usually brief, but some may have detailed descriptions

---

## Knowledge Management

### Note
**Purpose**: Information or documentation, typically in free-form text.

**Properties**:
- `title` * - Brief summary of the note's content
- `content` * - The main text content (can include markdown)
- `createdAt` - When the note was created
- `updatedAt` - When last modified
- `visibility` - Visibility level (private, shared, public)
- `isPinned` - Whether the note is pinned/starred

**Embedding Strategy**: Combine title and content for comprehensive semantic search
**Rationale**: Notes contain rich text content and are frequently searched/referenced

**Fuzzy Equality Methods**:
- `title_exact_match`: Match on identical note titles
- `title_similarity_match`: Fuzzy string matching on note titles
- `content_hash_match`: Match on content hash for exact duplicates
- `content_similarity_match`: Match on similar content themes and topics
- `creation_time_title_match`: Match notes created around same time with similar titles

**Similarity Threshold**: 0.88 (higher due to rich content)

---

### Document
**Purpose**: Files or documents, either physical or digital.

**Properties**:
- `title` * - Name of the document
- `description` * - Brief summary of the document's content
- `filePath` - Path to the actual file
- `fileType` - File extension
- `mimeType` - Internet media type
- `fileSize` - Size in bytes
- `url` - Direct URL if stored online
- `content` * - Extracted text content (for search/indexing)
- `language` - Document language
- `pageCount` - Number of pages
- `processedAt` - When content was last extracted
- `expiresAt` - When document is no longer valid

**Embedding Strategy**: Combine title, description, and extracted content
**Rationale**: Documents often have extracted text content and need semantic search

**Fuzzy Equality Methods**:
- `title_exact_match`: Match on identical document titles
- `file_hash_match`: Match on file content hash for exact duplicates
- `title_filetype_match`: Match on title + file type combination
- `content_similarity_match`: Match on extracted text content similarity
- `version_match`: Match different versions of the same document

**Similarity Threshold**: 0.85

---

### Photo
**Purpose**: Digital images or photographs.

**Properties**:
- `url` - Direct URL to the image file
- `thumbnailUrl` - URL to smaller version
- `description` * - Caption or description (only if present)
- `altText` * - Alternative text for accessibility (only if present)
- `width` - Image width in pixels
- `height` - Image height in pixels
- `fileSize` - File size in bytes
- `format` - Image format/extension
- `takenAt` - When the photo was taken
- `location` - Geographic coordinates or place name
- `cameraMake` - Camera manufacturer
- `cameraModel` - Camera model
- `aperture` - Camera aperture setting
- `exposure` - Exposure time
- `iso` - ISO speed
- `focalLength` - Focal length in mm
- `isFavorite` - Whether marked as favorite

**Embedding Strategy**: Use description and altText only if present and substantial
**Rationale**: Most photos lack substantial text, but some may have rich descriptions

---

## Assets & Properties

### Asset
**Purpose**: Valuable items owned by someone, either physical or digital.

**Properties**:
- `name` * - Common name of the asset
- `description` * - Detailed description and features
- `category` - Asset category (vehicle, electronic, furniture, etc.)
- `make` * - Manufacturer or brand
- `model` * - Model name or number
- `serialNumber` - Unique identifier from manufacturer
- `purchaseDate` - When acquired
- `purchasePrice` - Original purchase price
- `purchaseLocation` - Where purchased
- `currentValue` - Current estimated value
- `valueDate` - When current value was assessed
- `condition` - Current physical condition
- `status` - Asset status (active, in_use, in_storage, etc.)
- `warrantyExpires` - When warranty ends
- `insurancePolicyNumber` - Related insurance policy ID
- `notes` * - Additional information

**Embedding Strategy**: Combine name, description, make, model, and notes
**Rationale**: Assets can have similar descriptions, brand variations (e.g., "iPhone" vs "Apple iPhone")

**Fuzzy Equality Methods**:
- `serial_number_exact_match`: Match on identical serial numbers
- `make_model_match`: Match on manufacturer + model combination
- `name_category_match`: Match on asset name + category combination
- `brand_variation_match`: Handle brand name variations ("Apple" vs "Apple Inc.")
- `description_feature_match`: Match on key features in descriptions

**Similarity Threshold**: 0.80

---

### Property
**Purpose**: Real estate, including land and structures.

**Properties**:
- `name` * - Informal name (e.g., "Beach House", "Downtown Office")
- `propertyType` - Type of property (single_family, multi_family, etc.)
- `address` - Property address (Address type)
- `yearBuilt` - Year construction was completed
- `squareFeet` - Total livable area
- `lotSize` - Total land area
- `bedrooms` - Number of bedrooms
- `bathrooms` - Number of bathrooms
- `purchaseDate` - When acquired
- `purchasePrice` - Purchase price
- `currentValue` - Current market value estimate
- `valueDate` - When current value was assessed
- `mortgageBalance` - Remaining mortgage principal
- `mortgageRate` - Interest rate on mortgage
- `mortgageTerm` - Loan term in years
- `propertyTax` - Annual property tax amount
- `hoaFee` - Monthly HOA or condo fee
- `isRental` - Whether rented to others
- `isPrimaryResidence` - Whether owner's primary home
- `notes` * - Additional information

**Embedding Strategy**: Use name and notes for descriptive similarity
**Rationale**: Properties may have informal names and descriptive notes

---

## Implementation Priority

### High Priority (Rich Text Content)
1. **Note** - `title` + `content`
2. **Document** - `title` + `description` + `content`
3. **Task** - `title` + `description`
4. **Project** - `name` + `description`
5. **Event** - `title` + `description`

### Medium Priority (Structured Content with Names)
6. **Person** - `name` + `notes`
7. **Asset** - `name` + `description` + `make` + `model` + `notes`
8. **Property** - `name` + `notes`
9. **List** - `name` + `description`
10. **ListItem** - `name` + `description`

### Lower Priority (Location/Address Data)
11. **Address** - `street` + `city` + `state` + `country` + `notes`

### Minimal Priority (Simple Entities)
12. **Reminder** - `message` (only if substantial)
13. **Milestone** - `name` + `description` (only if description is substantial)
14. **Photo** - `description` + `altText` (only if present and substantial)

### Not Recommended
- **ContactMethod** - Too structured, exact matching preferred

## Implementation Plan

### Class-Based Architecture

Each node type should have a dedicated matcher class following this pattern:

```ruby
module Neo4j
  module Import
    module NodeMatchers
      class AddressNodeMatcher
        def self.embedding_properties
          %w[street city state country notes]
        end
        
        def self.generate_embedding_text(properties)
          [
            properties['street'],
            properties['city'], 
            properties['state'],
            properties['country'],
            properties['notes']
          ].compact.join(', ')
        end
        
        def self.fuzzy_equality_methods
          [
            :normalized_address_match,
            :street_number_street_name_match,
            :city_state_zip_match,
            :coordinate_proximity_match
          ]
        end
        
        def self.similarity_threshold
          0.75
        end
        
        def self.match_nodes(props1, props2)
          fuzzy_equality_methods.each do |method|
            return true if send(method, props1, props2)
          end
          false
        end
        
        private
        
        def self.normalized_address_match(props1, props2)
          normalize_address(props1) == normalize_address(props2)
        end
        
        def self.street_number_street_name_match(props1, props2)
          normalize_street(props1['street']) == normalize_street(props2['street'])
        end
        
        def self.city_state_zip_match(props1, props2)
          props1['city'] == props2['city'] && 
          normalize_state(props1['state']) == normalize_state(props2['state']) &&
          props1['postalCode'] == props2['postalCode']
        end
        
        def self.coordinate_proximity_match(props1, props2)
          # Implementation for geographic coordinate matching
          false # Placeholder
        end
        
        def self.normalize_address(props)
          # Normalize street abbreviations, state codes, etc.
        end
        
        def self.normalize_street(street)
          return '' unless street
          street.gsub(/\bSt\b/, 'Street')
                .gsub(/\bAve\b/, 'Avenue')
                .gsub(/\bRd\b/, 'Road')
                .gsub(/\bBlvd\b/, 'Boulevard')
                .strip.downcase
        end
        
        def self.normalize_state(state)
          return '' unless state
          # Convert state abbreviations to full names or vice versa
          STATE_MAPPINGS[state.upcase] || state
        end
        
        STATE_MAPPINGS = {
          'CA' => 'California',
          'NY' => 'New York',
          'TX' => 'Texas',
          # ... more mappings
        }.freeze
      end
    end
  end
end
```

### Node Matcher Registry

```ruby
module Neo4j
  module Import
    class NodeMatcherRegistry
      MATCHERS = {
        'Address' => NodeMatchers::AddressNodeMatcher,
        'Person' => NodeMatchers::PersonNodeMatcher,
        'Task' => NodeMatchers::TaskNodeMatcher,
        'Project' => NodeMatchers::ProjectNodeMatcher,
        'Note' => NodeMatchers::NoteNodeMatcher,
        'Document' => NodeMatchers::DocumentNodeMatcher,
        'Event' => NodeMatchers::EventNodeMatcher,
        'Asset' => NodeMatchers::AssetNodeMatcher,
        'Property' => NodeMatchers::PropertyNodeMatcher,
        'List' => NodeMatchers::ListNodeMatcher,
        'ListItem' => NodeMatchers::ListItemNodeMatcher
      }.freeze
      
      def self.matcher_for(node_type)
        MATCHERS[node_type.to_s] || NodeMatchers::DefaultNodeMatcher
      end
      
      def self.embedding_properties_for(node_type)
        matcher_for(node_type).embedding_properties
      end
      
      def self.generate_embedding_text(node_type, properties)
        matcher_for(node_type).generate_embedding_text(properties)
      end
      
      def self.similarity_threshold_for(node_type)
        matcher_for(node_type).similarity_threshold
      end
      
      def self.fuzzy_match(node_type, props1, props2)
        matcher_for(node_type).match_nodes(props1, props2)
      end
    end
  end
end
```

### Updated VectorSearch Integration

```ruby
# In vector_search.rb
def add_embedding(props, node_type)
  return props unless @embedding_service
  
  text = NodeMatcherRegistry.generate_embedding_text(node_type, props)
  
  if text.present? && !text.strip.empty?
    log_debug("  + Generating embedding for #{node_type} text")
    begin
      embedding = @embedding_service.generate_embedding(text)
      if embedding&.any?
        props["embedding"] = embedding
        log_debug("  + Added embedding (length: #{embedding.length})")
      else
        log_warn("  + Empty embedding returned")
      end
    rescue StandardError => e
      log_error("  + Error generating embedding: #{e.message}")
      log_error(e.backtrace.join("\n")) if @debug
    end
  else
    log_debug("  + No text available for embedding")
  end
  
  props
end

def find_similar_nodes(tx, type, embedding, threshold: nil)
  return [] unless @embedding_service && embedding.is_a?(Array)
  
  threshold ||= NodeMatcherRegistry.similarity_threshold_for(type)
  
  # ... rest of the method
end
```

## Implementation Steps

### Phase 1: Core Infrastructure
1. **Create NodeMatcher base class** with common interface
2. **Implement NodeMatcherRegistry** for centralized matcher management
3. **Update VectorSearch class** to use type-aware embedding generation
4. **Create DefaultNodeMatcher** for fallback behavior

### Phase 2: High Priority Matchers
5. **Implement AddressNodeMatcher** (fixes current test failures)
6. **Implement PersonNodeMatcher** with email/name matching
7. **Implement NoteNodeMatcher** for rich text content
8. **Implement TaskNodeMatcher** for work similarity
9. **Implement DocumentNodeMatcher** for file-based matching

### Phase 3: Medium Priority Matchers
10. **Implement ProjectNodeMatcher** for thematic similarity
11. **Implement EventNodeMatcher** for time-based matching
12. **Implement AssetNodeMatcher** with make/model handling
13. **Implement PropertyNodeMatcher** for real estate
14. **Implement List/ListItemNodeMatchers** for collections

### Phase 4: Integration & Testing
15. **Update NodeImporter** to pass node type to VectorSearch
16. **Update test suite** to validate type-specific matching
17. **Add fuzzy matching fallbacks** when embeddings fail
18. **Performance optimization** and caching strategies
19. **Documentation updates** for new architecture

### Phase 5: Advanced Features
20. **Implement coordinate-based matching** for addresses
21. **Add nickname handling** for person names
22. **Implement version detection** for documents
23. **Add brand normalization** for assets
24. **Create matching confidence scores** for better debugging

## File Structure

```
app/services/neo4j/import/
├── node_matchers/
│   ├── base_node_matcher.rb
│   ├── default_node_matcher.rb
│   ├── address_node_matcher.rb
│   ├── person_node_matcher.rb
│   ├── note_node_matcher.rb
│   ├── task_node_matcher.rb
│   ├── document_node_matcher.rb
│   ├── project_node_matcher.rb
│   ├── event_node_matcher.rb
│   ├── asset_node_matcher.rb
│   ├── property_node_matcher.rb
│   ├── list_node_matcher.rb
│   └── list_item_node_matcher.rb
├── node_matcher_registry.rb
├── vector_search.rb (updated)
└── node_importer.rb (updated)
```

## Testing Strategy

1. **Unit tests** for each NodeMatcher class
2. **Integration tests** for NodeMatcherRegistry
3. **End-to-end tests** with real data scenarios
4. **Performance benchmarks** for embedding generation
5. **Fuzzy matching accuracy tests** with known duplicates

## Benefits of This Architecture

1. **Type-specific logic**: Each node type can have custom embedding and matching strategies
2. **Maintainable**: Clear separation of concerns with dedicated classes
3. **Extensible**: Easy to add new node types or modify existing ones
4. **Testable**: Each matcher can be unit tested independently
5. **Configurable**: Thresholds and methods can be tuned per node type
6. **Fallback support**: Multiple matching strategies when embeddings aren't sufficient

This architecture will solve the current Address matching issue and provide a robust foundation for semantic similarity across all node types in the knowledge graph.
