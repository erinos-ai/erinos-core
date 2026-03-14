require "net/http"
require "json"
require "digest"
require "fileutils"
require "open3"
require "uri"

class SkillManager
  REGISTRY_URL = "https://skills.erinos.ai/index.json"
  DEFAULT_DIR  = File.expand_path("~/.erinos/skills")

  Error = Class.new(StandardError)

  def initialize(skills_dir: ENV.fetch("SKILLS_DIR", DEFAULT_DIR))
    @skills_dir = skills_dir
    FileUtils.mkdir_p(@skills_dir)
  end

  def list_installed
    Dir[File.join(@skills_dir, "*/provider.yml")].map do |path|
      provider = File.basename(File.dirname(path))
      sidecar = sidecar_path(provider)
      source = File.exist?(sidecar) ? "registry" : "local"
      { name: provider, source: source }
    end
  end

  def list_available
    index = fetch_index
    index["providers"].map do |name, info|
      installed = File.exist?(File.join(@skills_dir, name, "provider.yml"))
      { name: name, description: info["description"], installed: installed }
    end
  end

  def install(provider)
    index = fetch_index
    info = index.dig("providers", provider)
    raise Error, "Provider '#{provider}' not found in registry." unless info

    if File.exist?(File.join(@skills_dir, provider, "provider.yml"))
      return "Provider '#{provider}' is already installed."
    end

    download_and_extract(provider, info)
    "Installed '#{provider}' successfully."
  end

  def update(provider)
    sidecar = sidecar_path(provider)
    unless File.exist?(sidecar)
      return "Provider '#{provider}' is not a registry-installed skill (no update available)."
    end

    index = fetch_index
    info = index.dig("providers", provider)
    raise Error, "Provider '#{provider}' not found in registry." unless info

    current_sha = File.read(sidecar).strip
    if current_sha == info["sha256"]
      return "Provider '#{provider}' is already up to date."
    end

    FileUtils.rm_rf(File.join(@skills_dir, provider))
    download_and_extract(provider, info)
    "Updated '#{provider}' successfully."
  end

  def update_all
    results = []
    Dir[File.join(@skills_dir, ".*.sha256")].each do |sidecar|
      provider = File.basename(sidecar).delete_prefix(".").delete_suffix(".sha256")
      results << update(provider)
    end
    results.empty? ? "No registry-installed skills to update." : results.join("\n")
  end

  def remove(provider)
    dir = File.join(@skills_dir, provider)
    unless File.exist?(dir)
      return "Provider '#{provider}' is not installed."
    end

    FileUtils.rm_rf(dir)
    sidecar = sidecar_path(provider)
    FileUtils.rm_f(sidecar)
    "Removed '#{provider}'."
  end

  private

  def fetch_index
    uri = URI(REGISTRY_URL)
    response = Net::HTTP.get_response(uri)
    raise Error, "Failed to fetch registry: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def download_and_extract(provider, info)
    uri = URI(info["url"])
    response = Net::HTTP.get_response(uri)
    raise Error, "Failed to download '#{provider}': HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    tarball = response.body
    actual_sha = Digest::SHA256.hexdigest(tarball)
    if actual_sha != info["sha256"]
      raise Error, "Checksum mismatch for '#{provider}': expected #{info["sha256"]}, got #{actual_sha}"
    end

    tmp = File.join(@skills_dir, ".#{provider}.tar.gz")
    File.binwrite(tmp, tarball)

    stdout, stderr, status = Open3.capture3("tar", "-xzf", tmp, "-C", @skills_dir)
    FileUtils.rm_f(tmp)
    raise Error, "Failed to extract '#{provider}': #{stderr}" unless status.success?

    File.write(sidecar_path(provider), actual_sha)
  end

  def sidecar_path(provider)
    File.join(@skills_dir, ".#{provider}.sha256")
  end
end
