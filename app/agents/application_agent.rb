class ApplicationAgent < ActiveAgent::Base
  # Claude via ANTHROPIC_API_KEY (see .env), or OpenAI if only that key is
  # present. No local inference — Ollama is deliberately not wired up.
  generate_with ENV["OPENAI_API_KEY"].present? && ENV["ANTHROPIC_API_KEY"].blank? ? :openai : :anthropic
end
