# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Validations
  validates :full_name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :given_name, presence: true
  validates :family_name, presence: true
  validates :phone, format: { with: /\A\+?[\d\s-]+\z/, allow_blank: true }

  # No need to serialize JSONB columns - they handle serialization natively
  # The database column is defined as JSONB which handles arrays natively

  # Class method to get the current user (for use in services)
  def self.current
    # In a real app, you'd get this from the current request context
    # For now, we'll just return the first user or create a default one
    user = first_or_initialize

    if user.new_record?
      user.full_name = "Kenneth Grimm"
      user.given_name = "Kenneth"
      user.family_name = "Grimm"
      user.email = "kenneth.grimm@example.com"
      user.aliases = ["Ken", "Kenny"]
      user.password = "password123" # Change this in production!
      user.save!
    end

    user
  end

  # All possible names and references for this user
  def all_references
    [full_name, given_name, "#{given_name} #{family_name}", *aliases].compact.uniq
  end

  # Returns a string describing the user for use in prompts
  def prompt_description
    refs = all_references
    if refs.size > 1
      "the current user (#{refs[0]}, also known as #{refs[1..-1].join(', ')})"
    else
      "the current user (#{refs.first})"
    end
  end
end
