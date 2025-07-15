#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple command-line interface for human review of asset deduplication decisions

unless defined?(Rails)
  puts "This script must be run in a Rails environment. Please use: bundle exec rails runner #{__FILE__}"
  exit 1
end

require "json"
require "io/console"

class HumanReviewInterface
  def initialize
    @reviews_file = Rails.root.join("tmp", "human_reviews.json")
    ensure_reviews_file_exists
  end

  def run
    puts "🔍 Asset Deduplication Human Review Interface"
    puts "=" * 50

    loop do
      pending_reviews = load_pending_reviews

      if pending_reviews.empty?
        puts "\n✅ No pending reviews! All caught up."
        break
      end

      puts "\n📋 Found #{pending_reviews.size} pending review(s)"

      pending_reviews.each_with_index do |review, index|
        puts "\n#{'=' * 60}"
        puts "Review #{index + 1} of #{pending_reviews.size}"
        puts "Review ID: #{review['id']}"
        puts "Confidence Score: #{review['confidence_score'].round(3)}"
        puts "Created: #{review['created_at']}"

        display_asset_comparison(review["existing_asset"], review["new_asset"])

        decision = get_human_decision

        if decision == "skip"
          puts "⏭️  Skipping this review"
          next
        elsif decision == "quit"
          puts "👋 Goodbye!"
          return
        end

        notes = get_review_notes

        # Update the review record
        update_review_record(review["id"], decision, notes)

        puts "✅ Review saved: #{decision}"
      end

      puts "\n🎉 All reviews completed!"
      break
    end
  end

  private

  def ensure_reviews_file_exists
    return if File.exist?(@reviews_file)

    File.write(@reviews_file, "[]")
  end

  def load_pending_reviews
    reviews = JSON.parse(File.read(@reviews_file))
    reviews.select { |review| review["status"] == "pending" }
  end

  def display_asset_comparison(existing_asset, new_asset)
    puts "\n📊 Asset Comparison:"
    puts "\n#{' ' * 20}EXISTING ASSET#{' ' * 20}│#{' ' * 20}NEW ASSET"
    puts "─" * 60

    # Get all unique property keys
    all_keys = (existing_asset.keys + new_asset.keys).uniq.sort

    all_keys.each do |key|
      existing_val = existing_asset[key].to_s
      new_val = new_asset[key].to_s

      # Truncate long values
      existing_display = existing_val.length > 25 ? "#{existing_val[0..22]}..." : existing_val
      new_display = new_val.length > 25 ? "#{new_val[0..22]}..." : new_val

      # Highlight differences
      if existing_val != new_val && existing_val.present? && new_val.present?
        existing_display = "⚠️  #{existing_display}"
        new_display = "⚠️  #{new_display}"
      elsif existing_val.blank? && new_val.present?
        new_display = "✨ #{new_display}"
      elsif existing_val.present? && new_val.blank?
        existing_display = "✨ #{existing_display}"
      end

      printf "%-12s │ %-30s │ %-30s\n",
             key,
             existing_display.ljust(30),
             new_display.ljust(30)
    end

    puts "─" * 60
  end

  def get_human_decision
    puts "\n🤔 Should these assets be merged?"
    puts "  [y] Yes, merge them"
    puts "  [n] No, keep separate"
    puts "  [s] Skip this review (decide later)"
    puts "  [q] Quit interface"

    loop do
      print "\nYour decision [y/n/s/q]: "
      input = $stdin.gets.chomp.downcase

      case input
      when "y", "yes"
        return "merge"
      when "n", "no"
        return "separate"
      when "s", "skip"
        return "skip"
      when "q", "quit"
        return "quit"
      else
        puts "❌ Invalid input. Please enter y, n, s, or q."
      end
    end
  end

  def get_review_notes
    puts "\n📝 Optional notes about this decision:"
    print "Notes: "
    notes = $stdin.gets.chomp
    notes.empty? ? nil : notes
  end

  def update_review_record(review_id, decision, notes)
    reviews = JSON.parse(File.read(@reviews_file))

    review = reviews.find { |r| r["id"] == review_id }
    return unless review

    review["status"] = "completed"
    review["decision"] = decision
    review["notes"] = notes
    review["reviewed_at"] = Time.current.iso8601
    review["reviewer"] = ENV["USER"] || "unknown"

    File.write(@reviews_file, JSON.pretty_generate(reviews))
  end
end

# Run the interface
if __FILE__ == $PROGRAM_NAME
  interface = HumanReviewInterface.new
  interface.run
end
