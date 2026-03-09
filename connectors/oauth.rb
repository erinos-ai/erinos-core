class Connectors::Oauth
  def self.env_for(data, env_mapping:)
    env_mapping.each_with_object({}) do |(env_var, field_key), env|
      env[env_var] = data[field_key]
    end
  end
end
