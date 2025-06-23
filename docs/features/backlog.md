
# Backlog

## MVP
The MVP will include the following features:

- ability to process a document, image, video, audio, text file and extract information from it
- attempts to identify how to categorize the information
  - contact
  - calendar event
  - reminder
  - possession (photo of license plate, vehicle, vehicle door sticker)
  - location (home, work, gym, Home Depot, parent's house, Montrose)
  - receipt (photo of receipt of vehicle purchase or sale)
  - note
  - interest (artist, song, movie, book, hiking, biking, etc)
  - todo
  - goal
  - web link (article, video, podcast, etc)
  - shopping list
    - item (almonds)
  - recipe
  - financial information
  - project (repair the garage)
    - task (paint the garage)
      - subtask (buy paint)
  - task (register vehicle and get new state license / license plate)
    - subtask (fill out paperwork)
- stores the information as a document in pg + pg_vector with a link to the original file stored in ActiveStorage
- Upload interface is a text area as well as multi-file upload
- after upload or paste, show a preview of what was extracted/categorized and let the user correct it if needed (instant feedback loop)
- background job processes the file and stores the information
- web app has ability to search for anything using plain english queries and returns results with a confidence score
- examples of queries:
  - "what are my goals?"
  - "what are my todos?"
  - "when does my car registration expire?"
  - "how much did I pay for car registration for the last 5 years?"
  - "what are some of the priority tasks that I must do today?"
  - "what is my license plate number?"
  - "what are my contacts?"
  - "what are my possessions?"
  - "what are my receipts?"
  - "what are my notes?"
  - "what are my shopping lists?"
  - "what are my recipes?"
  - "what are my financial information?"
  - "what are my projects?"

  
## Phase 2
Able to perform actions based on the information stored in the database

- example actions:
  - "remind me to call my mom tomorrow at 10am"
  - "add buy paint from Home Depot to the garage project"
  - "add almonds to my Amazon shopping list"
  - "remove everything from my Amazon shopping list"
  - "show me all of my shopping lists"
  - "give me my schedule for today"
  - "give me my schedule for this week"
  - "find me something I'd be interested in to listen to on the car ride to skiing"
  - 
