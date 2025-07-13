# Rapid Information Onboarding Feature

## Problem Statement

Archimedes currently supports basic content upload and analysis but lacks comprehensive mechanisms for users to quickly import their existing personal information from various sources. Users need efficient ways to onboard their entire digital life into the system without manual, file-by-file uploads.

## Current State Analysis

### Existing Capabilities
- **Single File Upload**: PDF, text, and image files via web interface
- **Basic Analysis**: OpenAI-powered entity extraction and knowledge graph creation
- **Neo4j Import**: Bulk import from JSON extractions via rake task
- **Vector Similarity**: Deduplication using OpenAI embeddings
- **Entity Types**: Comprehensive taxonomy covering personal, productivity, and knowledge entities

### Current Limitations
- **Manual Process**: Requires individual file uploads and analysis triggers
- **Limited File Formats**: Missing Office documents, audio, video, and structured data
- **No API Integrations**: No direct connections to personal data sources
- **Single Source Processing**: No batch directory processing or recursive scanning
- **No Migration Tools**: Lacks import wizards for common personal data exports

## Proposed Solution: Rapid Information Onboarding System

### Core Components

#### 1. Bulk Import Engine
```
rails archimedes:import:bulk [source_path] [options]
```

**Features:**
- Recursive directory scanning with configurable depth limits
- Parallel processing with progress tracking and error recovery
- Resume capability for interrupted imports
- File type detection and appropriate processing pipeline routing
- Configurable batch sizes and memory management

**File Format Support:**
- **Documents**: .pdf, .docx, .xlsx, .pptx, .pages, .numbers, .keynote, .rtf, .odt
- **Text**: .txt, .md, .html, .csv, .json, .xml
- **Images**: .jpg, .png, .gif, .webp, .tiff, .bmp, .heic
- **Media**: .mp3, .wav, .m4a, .mp4, .mov, .avi (metadata and transcript extraction)
- **Archives**: .zip, .tar, .7z (automatic extraction and processing)

#### 2. Personal Data Source Integrations

**Email Integration:**
```ruby
# app/services/import/email_import_service.rb
class Import::EmailImportService
  def import_gmail_takeout(archive_path)
  def import_mbox_files(mbox_directory)
  def extract_contacts_from_emails
  def process_email_attachments
end
```

**Cloud Storage Integration:**
```ruby
# app/services/import/cloud_storage_service.rb
class Import::CloudStorageService
  def import_google_drive_export
  def import_dropbox_export
  def import_icloud_export
  def process_file_metadata
end
```

**Contact and Calendar Integration:**
```ruby
# app/services/import/personal_data_service.rb
class Import::PersonalDataService
  def import_vcard_files(directory)
  def import_ics_calendar_files(directory)
  def import_google_contacts_csv
  def import_apple_contacts_export
end
```

#### 3. Structured Data Import Pipeline

**CSV/Spreadsheet Import:**
```ruby
# app/services/import/structured_data_service.rb
class Import::StructuredDataService
  def import_csv_with_mapping(file_path, column_mappings)
  def auto_detect_entity_types(headers, sample_data)
  def create_import_template(entity_type)
  def validate_structured_import(data)
end
```

**JSON Bulk Import:**
```ruby
# Enhanced Neo4j import for structured personal data
rails archimedes:import:json [file_or_directory] --entity-type=auto|person|task|note
```

#### 4. Migration and Export Tools

**Data Export Formats:**
```ruby
# app/services/export/personal_data_service.rb
class Export::PersonalDataService
  def export_to_json(filter_options = {})
  def export_to_csv(entity_type)
  def create_backup_archive
  def export_knowledge_graph(format: 'graphml')
end
```

**Legacy Data Converters:**
```ruby
# app/services/import/legacy_converter_service.rb
class Import::LegacyConverterService
  def convert_evernote_export(enex_files)
  def convert_notion_export(zip_file)
  def convert_obsidian_vault(vault_directory)
  def convert_apple_notes_export(folder)
end
```

### Implementation Roadmap

#### Phase 1: Enhanced Bulk Processing (2-3 weeks)
1. **Batch File Processor**: Recursive directory scanning with parallel processing
2. **Extended File Format Support**: Add Office documents and structured data formats
3. **Progress Tracking**: Real-time import progress with detailed logging
4. **Error Recovery**: Robust error handling with retry mechanisms and partial imports

#### Phase 2: Personal Data Sources (3-4 weeks)
1. **Email Import**: MBOX and Gmail Takeout processing with contact extraction
2. **Cloud Storage**: Google Drive, Dropbox, and iCloud export processing
3. **Contact/Calendar**: vCard and iCalendar file processing
4. **Social Media**: Basic photo and text extraction from common export formats

#### Phase 3: API Integrations (4-6 weeks)
1. **Google APIs**: Drive, Gmail, Contacts, Calendar integration
2. **Apple APIs**: CloudKit, Photos, Contacts integration (where available)
3. **Microsoft APIs**: OneDrive, Outlook, Office 365 integration
4. **Webhook System**: Real-time sync capabilities for supported platforms

#### Phase 4: Advanced Features (2-3 weeks)
1. **Migration Wizards**: Step-by-step import guidance for common scenarios
2. **Data Archaeology**: Tools for processing old, fragmented, or corrupted data
3. **Smart Deduplication**: Enhanced cross-source entity matching
4. **Import Monitoring**: Analytics and insights on import success rates

### Quick Win Implementation Ideas

#### 1. Directory Scanner (1-2 days)
```bash
# Immediate implementation
rails archimedes:scan [directory] --preview
rails archimedes:scan [directory] --import --batch-size=10
```

**Benefits:**
- Process entire photo libraries, document folders, or download directories
- Automatic file type detection and appropriate processing
- Preview mode to estimate processing time and costs

#### 2. Contact Import (2-3 days)
```ruby
# app/models/contact_importer.rb
class ContactImporter
  def self.import_vcf_file(file_path)
  def self.import_csv_contacts(file_path, mapping = {})
  def self.import_apple_addressbook_export(folder)
end
```

**Benefits:**
- Immediately populate Person entities from existing contact lists
- Cross-reference with email analysis for enhanced person profiles
- Foundation for relationship mapping

#### 3. Photo Metadata Extraction (1-2 days)
```ruby
# Enhance existing image processing
class ContentAnalysisService
  def extract_photo_metadata(image_file)
    # EXIF data: location, timestamp, camera settings
    # Face detection and recognition
    # Scene classification
  end
end
```

**Benefits:**
- Location entities from GPS data
- Timeline construction from photo timestamps
- Enhanced context for image analysis

#### 4. Email Archive Processing (3-5 days)
```ruby
# app/services/import/email_archive_service.rb
class Import::EmailArchiveService
  def process_mbox_file(mbox_path)
  def extract_email_entities(email)
  def process_email_attachments(email)
  def build_communication_graph
end
```

**Benefits:**
- Massive entity extraction from email history
- Communication relationship mapping
- Document attachment processing

### Configuration and Customization

#### Import Configuration
```yaml
# config/import_settings.yml
bulk_import:
  max_file_size: 100MB
  batch_size: 50
  max_parallel_jobs: 4
  supported_formats:
    documents: [pdf, docx, xlsx, pptx]
    images: [jpg, png, gif, webp, heic]
    text: [txt, md, csv, json]
  
entity_extraction:
  confidence_threshold: 0.8
  auto_merge_threshold: 0.95
  require_review_threshold: 0.6

processing_limits:
  daily_openai_calls: 10000
  max_import_duration: 6h
  memory_limit: 2GB
```

#### User Import Preferences
```ruby
# app/models/user_import_preferences.rb
class UserImportPreferences < ApplicationRecord
  belongs_to :user
  
  # Auto-processing settings
  attribute :auto_analyze_uploads, :boolean, default: true
  attribute :auto_merge_high_confidence, :boolean, default: true
  attribute :notify_on_import_complete, :boolean, default: true
  
  # Privacy and filtering
  attribute :exclude_file_patterns, :text # .git, node_modules, etc.
  attribute :include_hidden_files, :boolean, default: false
  attribute :max_file_age_days, :integer # Only process recent files
end
```

### Security and Privacy Considerations

#### Data Protection
- **Local Processing**: All file analysis happens locally, only embeddings sent to OpenAI
- **Encryption**: Sensitive data encrypted at rest in PostgreSQL
- **Access Control**: User-specific data isolation with proper authorization
- **Audit Logging**: Complete import history and data lineage tracking

#### Content Filtering
- **Sensitive Data Detection**: Automatic detection and flagging of SSNs, credit cards, passwords
- **File Type Restrictions**: Configurable blacklist for executable files and system files
- **Size Limits**: Configurable per-file and per-import size restrictions
- **Privacy Mode**: Option to disable OpenAI processing for sensitive content

### Success Metrics

#### Adoption Metrics
- **Import Volume**: Total files and data processed per user
- **Format Coverage**: Percentage of user's data successfully imported
- **Time to Value**: Average time from first import to meaningful knowledge graph

#### Technical Metrics
- **Processing Speed**: Files per hour, entities extracted per minute
- **Accuracy**: Entity extraction quality and deduplication success rate
- **Reliability**: Import success rate and error recovery effectiveness

#### User Experience Metrics
- **Completion Rate**: Percentage of users who complete full data import
- **Feature Usage**: Most and least used import sources
- **Support Requests**: Common issues and pain points during import

### Future Enhancements

#### Advanced AI Features
- **Content Summarization**: Automatic summarization of large documents and email threads
- **Relationship Inference**: AI-powered relationship discovery between entities
- **Timeline Reconstruction**: Automatic chronological organization of personal history
- **Intelligent Categorization**: AI-assisted entity type classification and tagging

#### Real-time Sync
- **Live Monitoring**: Watch folders for new files and process automatically
- **API Webhooks**: Real-time updates from connected services
- **Incremental Updates**: Efficient processing of changes rather than full re-import
- **Conflict Resolution**: Smart handling of updates to existing entities

This rapid information onboarding system would transform Archimedes from a manual upload tool into a comprehensive personal data ingestion platform, dramatically reducing the barrier to entry and time-to-value for new users.