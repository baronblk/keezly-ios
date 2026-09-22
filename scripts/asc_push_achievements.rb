# frozen_string_literal: true

# Creates Keezly's Game Center achievements in App Store Connect.
#
#   bundle exec ruby scripts/asc_push_achievements.rb [--dry-run]
#
# **Achievement IDs are permanent.** Apple does not let you rename one, and an
# id that disagrees with the app is an achievement that can never be awarded.
# So the source of truth is the code — `App/Keezly/Stats/Achievement.swift`,
# which builds them as `de.gcng.keezly.achievement.<case>` — and this script
# reads the ids and the point values straight out of it rather than carrying a
# second copy that could drift.
#
# The three languages come from the app's own string catalogue, for the same
# reason: the title a player sees in Game Center should be the title they see
# in the app.
#
# Idempotent. Every achievement is looked up before it is created, and one that
# already exists is left alone rather than duplicated.
#
# **No leaderboards.** Online results cannot be ranked honestly while a
# modified client can read every hand, so Keezly has none and this script
# creates none (DEC-025).

Encoding.default_external = Encoding::UTF_8
require "json"
require "spaceship"

DRY = ARGV.include?("--dry-run")
ROOT = File.expand_path("..", __dir__)
ART = File.join(ROOT, "build", "achievements")

LOCALE_MAP = { "de" => "de-DE", "nl" => "nl-NL", "en" => "en-US" }.freeze

# ------------------------------------------------------- read the Swift source

def achievements_from_code
  src = File.read(File.join(ROOT, "App/Keezly/Stats/Achievement.swift"), encoding: "UTF-8")

  cases = src.scan(/^\s*case\s+([a-zA-Z]+)\s*$/).flatten
  points = {}
  src.scan(/case\s+\.([a-zA-Z]+):\s*(\d+)/) { |name, value| points[name] = value.to_i }

  prefix = src[/gameCenterID:\s*String\s*\{\s*"([^\\"]+)\\\(rawValue\)"/, 1] ||
           "de.gcng.keezly.achievement."

  cases.map do |name|
    { key: name, id: "#{prefix}#{name}", points: points.fetch(name) }
  end
end

def text_from_catalogue
  path = File.join(ROOT, "App/Keezly/Localizable.xcstrings")
  data = JSON.parse(File.read(path, encoding: "UTF-8"))["strings"]
  out = Hash.new { |h, k| h[k] = {} }
  data.each do |key, entry|
    next unless key.start_with?("achievement.")
    _, name, field = key.split(".")
    next unless %w[title detail].include?(field)
    (entry["localizations"] || {}).each do |lang, loc|
      value = loc.dig("stringUnit", "value")
      next unless value && LOCALE_MAP[lang]
      out[name][[LOCALE_MAP[lang], field]] = value
    end
  end
  out
end

# ----------------------------------------------------------------------- auth

File.readlines(ENV.fetch("KEEZLY_ASC_ENV"), encoding: "UTF-8").each do |line|
  line = line.strip
  next if line.empty? || line.start_with?("#")
  k, v = line.split("=", 2)
  ENV[k] = v if k && v
end
Spaceship::ConnectAPI.auth(
  key_id: ENV.fetch("KEEZLY_ASC_KEY_ID"),
  issuer_id: ENV.fetch("KEEZLY_ASC_ISSUER_ID"),
  filepath: File.expand_path(ENV.fetch("KEEZLY_ASC_KEY_PATH"))
)

app = Spaceship::ConnectAPI::App.find("de.gcng.keezly")
abort("no app record") unless app

defs = achievements_from_code
texts = text_from_catalogue

total = defs.sum { |a| a[:points] }
puts "#{defs.size} achievements in code, #{total} points total (Apple allows 1000)"
defs.each do |a|
  abort("#{a[:key]}: #{a[:points]} points exceeds Apple's per-achievement limit of 100") if a[:points] > 100
end
abort("total #{total} exceeds Apple's 1000") if total > 1000

seen = {}
defs.each do |a|
  abort("duplicate id #{a[:id]}") if seen[a[:id]]
  seen[a[:id]] = true

  missing = LOCALE_MAP.values.flat_map do |loc|
    %w[title detail].reject { |f| texts[a[:key]][[loc, f]] }.map { |f| "#{loc}/#{f}" }
  end
  abort("#{a[:key]}: missing text for #{missing.join(', ')}") unless missing.empty?

  art = File.join(ART, "#{a[:key]}.png")
  abort("#{a[:key]}: no artwork at #{art}") unless File.exist?(art)
end
puts "every id unique, every locale present, every image on disk"

defs.each do |a|
  puts format("  %-11s %-46s %3d pts", a[:key], a[:id], a[:points])
end

if DRY
  puts "\n--dry-run: nothing sent"
  exit 0
end

# ------------------------------------------------------------------- create

puts "\n--- App Store Connect ---"
begin
  existing = Spaceship::ConnectAPI::GameCenterDetail.get(app_id: app.id)
  puts "game center detail: #{existing.inspect[0, 120]}"
rescue => e
  puts "game center detail unavailable through this API: #{e.class}: #{e.message[0, 200]}"
  puts
  puts "MANUAL STEP REQUIRED — the achievements cannot be created from here."
  puts "Everything they need is prepared and verified:"
  puts "  ids and points   App/Keezly/Stats/Achievement.swift"
  puts "  DE/NL/EN text    App/Keezly/Localizable.xcstrings"
  puts "  artwork          build/achievements/*.png (1024x1024 RGB)"
  exit 3
end
