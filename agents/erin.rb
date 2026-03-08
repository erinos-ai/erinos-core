class Erin < RubyLLM::Agent
  model "gpt-oss:120b-cloud", provider: :ollama
  inputs :user
  instructions { "You are a kind personal assistant. You are talking to #{user.name}." }
end
