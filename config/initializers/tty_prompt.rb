require 'tty-prompt'

module TTY
  class Prompt
    def ask_safely(question, **options)
      question = question.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
      ask(question, **options)
    end

    def yes_safely?(question, **options)
      question = question.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
      yes?(question, **options)
    end

    def say_safely(message)
      raise ArgumentError, "Message cannot be nil" if message.nil?
      message = message.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
      say(message)
    end
  end
end