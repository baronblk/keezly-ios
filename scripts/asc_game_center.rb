# frozen_string_literal: true

# Creates Keezly's Game Center achievements in App Store Connect, through the
# REST API rather than a web form.
#
#   bundle exec ruby scripts/asc_game_center.rb [--dry-run]
#
# fastlane's spaceship has no model for these resources. That is a fact about
# spaceship and not about the API, and an earlier version of this work wrongly
# concluded from it that the achievements had to be made by hand. They do not.
# The shape, learned by asking Apple rather than by guessing:
#
#   POST /v1/gameCenterDetails                    once, tied to the app
#   POST /v2/gameCenterAchievements               with its first version inline
#   POST /v1/gameCenterAchievementLocalizations   tied to the achievement
#   POST /v1/gameCenterAchievementImages          tied to the localization
#
# Two things about the v2 create are worth writing down, because both cost a
# round trip to discover. It refuses without a `versions` relationship, so the
# first version travels with it in `included` under a placeholder id. And a
# localization placeholder nested inside that version is rejected — "an inline
# include id, which is not allowed for this request" — so localizations are
# separate calls afterwards.
#
# **Achievement ids are permanent.** `vendorIdentifier` comes from
# `App/Keezly/Stats/Achievement.swift` and from nowhere else, and every
# achievement is looked up by it before anything is created.

$LOAD_PATH.unshift File.expand_path(__dir__)

require "json"
require "asc_client"

DRY = ARGV.include?("--dry-run")
ROOT = File.expand_path("..", __dir__)
ART = File.join(ROOT, "build", "achievements")
APP_ID = "6814932630"

LOCALE_MAP = { "de" => "de-DE", "nl" => "nl-NL", "en" => "en-US" }.freeze

# ------------------------------------------------------- the source of truth

def achievements_from_code
  src = File.read(File.join(ROOT, "App/Keezly/Stats/Achievement.swift"), encoding: "UTF-8")
  cases = src.scan(/^\s*case\s+([a-zA-Z]+)\s*$/).flatten
  points = {}
  src.scan(/case\s+\.([a-zA-Z]+):\s*(\d+)/) { |n, v| points[n] = v.to_i }
  cases.map { |n| { key: n, vendor: "de.gcng.keezly.achievement.#{n}", points: points.fetch(n) } }
end

def text_from_catalogue
  data = JSON.parse(File.read(File.join(ROOT, "App/Keezly/Localizable.xcstrings"), encoding: "UTF-8"))["strings"]
  out = Hash.new { |h, k| h[k] = {} }
  data.each do |key, entry|
    next unless key.start_with?("achievement.")
    _, name, field = key.split(".")
    next unless %w[title detail].include?(field)
    (entry["localizations"] || {}).each do |lang, loc|
      value = loc.dig("stringUnit", "value")
      out[name][[LOCALE_MAP[lang], field]] = value if value && LOCALE_MAP[lang]
    end
  end
  out
end

# ------------------------------------------------------------------ validate

defs = achievements_from_code
texts = text_from_catalogue
total = defs.sum { |a| a[:points] }

puts "#{defs.size} achievements in code, #{total} points (Apple allows 1000)"
abort("total #{total} over Apple's limit") if total > 1000
seen = {}
defs.each do |a|
  abort("#{a[:key]}: #{a[:points]} points over Apple's per-achievement limit") if a[:points] > 100
  abort("duplicate vendor id #{a[:vendor]}") if seen[a[:vendor]]
  seen[a[:vendor]] = true
  LOCALE_MAP.values.each do |loc|
    %w[title detail].each do |f|
      abort("#{a[:key]}: no #{f} for #{loc}") unless texts[a[:key]][[loc, f]]
    end
  end
  abort("#{a[:key]}: no artwork") unless File.exist?(File.join(ART, "#{a[:key]}.png"))
end
puts "ids unique, points within limits, three locales each, artwork present"

if DRY
  defs.each { |a| puts format("  %-11s %-46s %3d", a[:key], a[:vendor], a[:points]) }
  puts "\n--dry-run: nothing sent"
  exit 0
end

# ---------------------------------------------------------------------- push

c = ASC::Client.new

detail = c.get("v1/apps/#{APP_ID}/gameCenterDetail")["data"]
unless detail
  puts "creating gameCenterDetail"
  detail = c.post("v1/gameCenterDetails", {
    "data" => {
      "type" => "gameCenterDetails",
      "relationships" => { "app" => { "data" => { "type" => "apps", "id" => APP_ID } } }
    }
  })["data"]
end
DETAIL_ID = detail["id"]
puts "gameCenterDetail #{DETAIL_ID}"

existing = c.all("v1/gameCenterDetails/#{DETAIL_ID}/gameCenterAchievements")
             .each_with_object({}) { |a, h| h[a.dig("attributes", "vendorIdentifier")] = a }
puts "already present: #{existing.size}"

report = []

defs.each do |a|
  english = texts[a[:key]][["en-US", "title"]]
  record = existing[a[:vendor]]

  if record
    puts "  #{a[:key]}: exists (#{record['id']})"
  else
    print "  #{a[:key]}: creating ... "
    record = c.post("v2/gameCenterAchievements", {
      "data" => {
        "type" => "gameCenterAchievements",
        "attributes" => {
          "referenceName" => english,
          "vendorIdentifier" => a[:vendor],
          "points" => a[:points],
          "showBeforeEarned" => true,
          "repeatable" => false,
        },
        "relationships" => {
          "gameCenterDetail" => { "data" => { "type" => "gameCenterDetails", "id" => DETAIL_ID } },
          "versions" => { "data" => [{ "type" => "gameCenterAchievementVersions", "id" => "${v}" }] }
        }
      },
      "included" => [{ "type" => "gameCenterAchievementVersions", "id" => "${v}" }]
    })["data"]
    puts record["id"]
  end

  ach_id = record["id"]
  have_locs = c.all("v1/gameCenterAchievements/#{ach_id}/localizations")
               .each_with_object({}) { |l, h| h[l.dig("attributes", "locale")] = l }

  LOCALE_MAP.values.each do |locale|
    name = texts[a[:key]][[locale, "title"]]
    detail_text = texts[a[:key]][[locale, "detail"]]
    loc = have_locs[locale]

    if loc
      print "      #{locale} exists"
    else
      loc = c.post("v1/gameCenterAchievementLocalizations", {
        "data" => {
          "type" => "gameCenterAchievementLocalizations",
          "attributes" => {
            "locale" => locale, "name" => name,
            "beforeEarnedDescription" => detail_text,
            "afterEarnedDescription" => detail_text
          },
          "relationships" => {
            "gameCenterAchievement" => { "data" => { "type" => "gameCenterAchievements", "id" => ach_id } }
          }
        }
      })["data"]
      print "      #{locale} created"
    end

    # Artwork hangs off the localization, and the upload is a three-step
    # dance: reserve, PUT the bytes at the URL Apple hands back, then mark it
    # uploaded. A successful reserve is not an upload.
    image = begin
      c.get("v1/gameCenterAchievementLocalizations/#{loc['id']}/gameCenterAchievementImage")["data"]
    rescue ASC::Error
      nil
    end

    if image && image.dig("attributes", "assetDeliveryState", "state") != "FAILED"
      puts " · image present"
    else
      path = File.join(ART, "#{a[:key]}.png")
      bytes = File.binread(path)
      begin
        reserved = c.post("v1/gameCenterAchievementImages", {
          "data" => {
            "type" => "gameCenterAchievementImages",
            "attributes" => { "fileName" => "#{a[:key]}.png", "fileSize" => bytes.bytesize },
            "relationships" => {
              "gameCenterAchievementLocalization" => {
                "data" => { "type" => "gameCenterAchievementLocalizations", "id" => loc["id"] }
              }
            }
          }
        })["data"]
        (reserved.dig("attributes", "uploadOperations") || []).each { |op| c.upload(op, bytes) }
        c.patch("v1/gameCenterAchievementImages/#{reserved['id']}", {
          "data" => {
            "type" => "gameCenterAchievementImages",
            "id" => reserved["id"],
            "attributes" => { "uploaded" => true }
          }
        })
        puts " · image uploaded"
      rescue ASC::Error => e
        puts " · image FAILED: #{e.message[0, 160]}"
      end
    end
  end

  report << { key: a[:key], id: ach_id, vendor: a[:vendor], points: a[:points] }
end

# -------------------------------------------------------------------- verify

puts "\n--- read back from App Store Connect ---"
final = c.all("v1/gameCenterDetails/#{DETAIL_ID}/gameCenterAchievements")
ok = true
final.sort_by { |a| a.dig("attributes", "vendorIdentifier").to_s }.each do |a|
  id = a["id"]
  attrs = a["attributes"]
  locs = c.all("v1/gameCenterAchievements/#{id}/localizations")
  by_locale = locs.each_with_object({}) { |l, h| h[l.dig("attributes", "locale")] = l }
  images = by_locale.map do |locale, l|
    img = begin
      c.get("v1/gameCenterAchievementLocalizations/#{l['id']}/gameCenterAchievementImage")["data"]
    rescue ASC::Error
      nil
    end
    [locale, img&.dig("attributes", "assetDeliveryState", "state") || "none"]
  end.to_h

  line = format("  %-46s %3d pts  %-38s  DE:%s NL:%s EN:%s",
                attrs["vendorIdentifier"], attrs["points"], id,
                by_locale["de-DE"] ? "y" : "n",
                by_locale["nl-NL"] ? "y" : "n",
                by_locale["en-US"] ? "y" : "n")
  puts line
  puts format("      images  de=%s nl=%s en=%s",
              images["de-DE"] || "none", images["nl-NL"] || "none", images["en-US"] || "none")
  ok = false unless %w[de-DE nl-NL en-US].all? { |l| by_locale[l] }
end

puts "\n#{final.size} achievements in App Store Connect"
puts(ok && final.size == defs.size ? "GAME CENTER METADATA = ASC VERIFIED" : "INCOMPLETE — see above")
puts "GAME CENTER E2E = NOT VERIFIED (needs two real accounts on real devices)"
exit(ok && final.size == defs.size ? 0 : 1)
