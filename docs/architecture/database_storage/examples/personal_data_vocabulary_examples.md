# Personal Data Examples Using Standard Vocabularies

## Schema.org Examples

### Personal Profile
```json
{
  "@context": "https://schema.org",
  "@type": "Person",
  "@id": "https://ken.example.com/person/ken-grimm",
  "name": "Ken Grimm",
  "givenName": "Ken",
  "familyName": "Grimm",
  "email": "ken@example.com",
  "jobTitle": "Software Developer",
  "worksFor": {
    "@type": "Organization",
    "name": "Tech Company",
    "url": "https://company.com"
  },
  "alumniOf": {
    "@type": "EducationalOrganization",
    "name": "University of Technology"
  },
  "knowsAbout": [
    "Artificial Intelligence",
    "Knowledge Graphs", 
    "Software Development",
    "Machine Learning"
  ],
  "address": {
    "@type": "PostalAddress",
    "addressLocality": "San Francisco",
    "addressRegion": "CA",
    "addressCountry": "US"
  },
  "birthDate": "1985-03-15",
  "nationality": "American"
}
```

### Entertainment Consumption
```json
{
  "@context": "https://schema.org",
  "@type": "WatchAction",
  "@id": "https://ken.example.com/activity/watch-breaking-bad-2024-01-15",
  "agent": {
    "@type": "Person",
    "@id": "https://ken.example.com/person/ken-grimm"
  },
  "object": {
    "@type": "TVSeries",
    "name": "Breaking Bad",
    "genre": ["Drama", "Crime"],
    "numberOfSeasons": 5,
    "startDate": "2008-01-20",
    "endDate": "2013-09-29",
    "creator": {
      "@type": "Person",
      "name": "Vince Gilligan"
    }
  },
  "startTime": "2024-01-15T20:00:00-08:00",
  "endTime": "2024-01-15T21:00:00-08:00",
  "location": {
    "@type": "Place",
    "name": "Home"
  },
  "result": {
    "@type": "Review",
    "reviewRating": {
      "@type": "Rating",
      "ratingValue": 9,
      "bestRating": 10
    },
    "reviewBody": "Amazing character development and storytelling"
  }
}
```

### Travel and Places
```json
{
  "@context": "https://schema.org",
  "@type": "TravelAction",
  "@id": "https://ken.example.com/activity/visit-paris-2024-03-10",
  "agent": {
    "@type": "Person",
    "@id": "https://ken.example.com/person/ken-grimm"
  },
  "toLocation": {
    "@type": "City",
    "name": "Paris",
    "addressCountry": "France",
    "geo": {
      "@type": "GeoCoordinates",
      "latitude": 48.8566,
      "longitude": 2.3522
    }
  },
  "startDate": "2024-03-10",
  "endDate": "2024-03-17",
  "purpose": "Vacation",
  "result": {
    "@type": "Review",
    "reviewBody": "Incredible architecture and food culture",
    "reviewRating": {
      "@type": "Rating",
      "ratingValue": 10
    }
  }
}
```

### Ideas and Goals
```json
{
  "@context": "https://schema.org",
  "@type": "CreativeWork",
  "@id": "https://ken.example.com/idea/ai-assistant-project",
  "name": "Personal AI Assistant Project",
  "description": "Build a knowledge graph-based AI assistant that understands personal context",
  "creator": {
    "@type": "Person",
    "@id": "https://ken.example.com/person/ken-grimm"
  },
  "dateCreated": "2024-01-15",
  "about": [
    "Artificial Intelligence",
    "Knowledge Graphs",
    "Personal Productivity"
  ],
  "isPartOf": {
    "@type": "Goal",
    "name": "Learn Advanced AI Technologies",
    "targetDate": "2024-12-31",
    "status": "In Progress"
  }
}
```

### Books and Learning
```json
{
  "@context": "https://schema.org",
  "@type": "ReadAction",
  "@id": "https://ken.example.com/activity/read-ai-book-2024-02-01",
  "agent": {
    "@type": "Person",
    "@id": "https://ken.example.com/person/ken-grimm"
  },
  "object": {
    "@type": "Book",
    "name": "Artificial Intelligence: A Modern Approach",
    "author": [
      {
        "@type": "Person",
        "name": "Stuart Russell"
      },
      {
        "@type": "Person", 
        "name": "Peter Norvig"
      }
    ],
    "isbn": "9780134610993",
    "genre": "Computer Science",
    "numberOfPages": 1152
  },
  "startDate": "2024-02-01",
  "endDate": "2024-03-15",
  "result": {
    "@type": "Review",
    "reviewRating": {
      "@type": "Rating",
      "ratingValue": 8
    },
    "reviewBody": "Comprehensive overview of AI fundamentals and techniques"
  }
}
```

## FOAF Examples

### Social Relationships
```turtle
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix : <https://ken.example.com/> .

:ken a foaf:Person ;
    foaf:name "Ken Grimm" ;
    foaf:mbox <mailto:ken@example.com> ;
    foaf:homepage <https://ken.example.com> ;
    foaf:knows :alice, :bob, :charlie ;
    foaf:interest :ai, :programming, :travel ;
    foaf:currentProject :archimedes_project ;
    foaf:pastProject :mobile_app_project ;
    foaf:weblog <https://ken.example.com/blog> ;
    foaf:depiction <https://ken.example.com/photos/profile.jpg> .

:alice a foaf:Person ;
    foaf:name "Alice Johnson" ;
    foaf:knows :ken .

:archimedes_project a foaf:Project ;
    foaf:name "Archimedes Knowledge Graph" ;
    dc:description "Personal AI assistant with knowledge graph backend" .
```

## Dublin Core Examples

### Content Metadata
```turtle
@prefix dc: <http://purl.org/dc/terms/> .
@prefix : <https://ken.example.com/> .

:blog_post_ai_future a dc:Text ;
    dc:title "The Future of Personal AI Assistants" ;
    dc:creator :ken ;
    dc:date "2024-01-20" ;
    dc:subject "Artificial Intelligence", "Personal Productivity" ;
    dc:description "Exploring how AI assistants will evolve to understand personal context" ;
    dc:type "Blog Post" ;
    dc:format "text/html" ;
    dc:language "en" .

:photo_paris_trip a dc:Image ;
    dc:title "Eiffel Tower at Sunset" ;
    dc:creator :ken ;
    dc:date "2024-03-12" ;
    dc:spatial "Paris, France" ;
    dc:description "Beautiful sunset view from Trocadéro" ;
    dc:format "image/jpeg" .
```

## Activity Streams Examples

### Daily Activities
```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "@type": "Create",
  "@id": "https://ken.example.com/activity/create-code-2024-01-16",
  "actor": {
    "@type": "Person",
    "@id": "https://ken.example.com/person/ken-grimm"
  },
  "object": {
    "@type": "Document",
    "name": "Knowledge Graph Service",
    "mediaType": "text/x-ruby",
    "content": "Ruby service for processing RDF triples"
  },
  "published": "2024-01-16T14:30:00Z",
  "location": {
    "@type": "Place",
    "name": "Home Office"
  }
}
```

## Hybrid RDF/JSON-LD Example

### Complete Personal Event
```json
{
  "@context": {
    "@vocab": "https://schema.org/",
    "foaf": "http://xmlns.com/foaf/0.1/",
    "dc": "http://purl.org/dc/terms/"
  },
  "@type": "Event",
  "@id": "https://ken.example.com/event/conference-2024-04-15",
  "name": "AI Conference 2024",
  "startDate": "2024-04-15T09:00:00-07:00",
  "endDate": "2024-04-15T17:00:00-07:00",
  "location": {
    "@type": "Place",
    "name": "Convention Center",
    "address": {
      "@type": "PostalAddress",
      "addressLocality": "San Francisco",
      "addressRegion": "CA"
    }
  },
  "attendee": {
    "@type": "Person",
    "@id": "https://ken.example.com/person/ken-grimm"
  },
  "about": ["Artificial Intelligence", "Machine Learning"],
  "foaf:interest": "AI Research",
  "dc:subject": "Technology Conference",
  "result": {
    "@type": "Review",
    "reviewBody": "Learned about latest developments in transformer architectures",
    "reviewRating": {
      "@type": "Rating",
      "ratingValue": 9
    }
  },
  "potentialAction": {
    "@type": "FollowAction",
    "object": "Apply learnings to Archimedes project"
  }
}
```

## Complex Relationship Example

### Interconnected Personal Data
```turtle
@prefix schema: <https://schema.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix : <https://ken.example.com/> .

# Person
:ken a schema:Person, foaf:Person ;
    schema:name "Ken Grimm" ;
    foaf:currentProject :archimedes ;
    schema:knowsAbout "Knowledge Graphs" .

# Project influenced by book
:archimedes a foaf:Project ;
    schema:name "Archimedes AI Assistant" ;
    schema:isBasedOn :ai_book ;
    schema:creator :ken .

# Book that inspired project
:ai_book a schema:Book ;
    schema:name "Knowledge Graphs in Practice" ;
    schema:influencedBy :conference_talk .

# Conference talk that led to book discovery
:conference_talk a schema:PresentationDigitalDocument ;
    schema:name "Building Personal AI Systems" ;
    schema:presentedAt :ai_conference .

# Conference attended
:ai_conference a schema:Event ;
    schema:name "AI Summit 2024" ;
    schema:attendee :ken ;
    schema:location :san_francisco .

# Location with personal significance
:san_francisco a schema:City ;
    schema:name "San Francisco" ;
    :personal_significance "Favorite city for tech events" .
```

This structure allows for rich queries like:
- "What projects were influenced by books I read?"
- "Which conferences led to new ideas?"
- "How are my interests connected to my activities?"
- "What locations have influenced my thinking?"

The vocabulary examples show how standard ontologies can capture complex personal relationships while maintaining interoperability and semantic richness.
