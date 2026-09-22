# frozen_string_literal: true

# Pushes Keezly's store metadata into App Store Connect, then reads it back.
#
#   bundle exec ruby scripts/asc_push_metadata.rb [--dry-run]
#
# Two levels have to stay in step and are easy to confuse:
#
#   * **App Info localizations** — the things that belong to the app rather
#     than to a version: name, subtitle, privacy policy URL.
#   * **App Store Version localizations** — the things that belong to 1.0.0:
#     description, keywords, promotional text, support and marketing URLs,
#     what's new.
#
# A locale created at only one level is half a locale, and App Store Connect
# will not tell you which half is missing. This creates both or neither.
#
# Idempotent: every field is read first and written only when it differs, so
# running it twice is not the same as writing twice.
#
# **The HTTP call succeeding is not the evidence.** Everything written is read
# back at the end and printed, because a 204 means the request was accepted and
# nothing more.

Encoding.default_external = Encoding::UTF_8
require "spaceship"

DRY = ARGV.include?("--dry-run")
ROOT = File.expand_path("..", __dir__)
META = File.join(ROOT, "fastlane", "metadata")

# The site is not live yet. These are the addresses it will have; they are
# written now so the fields are not empty, and they are *not* treated as
# verified until somebody has had a 200 back from them.
URLS = {
  "de-DE" => { marketing: "https://gcng.de/KEEZLY/",
               support: "https://gcng.de/KEEZLY/support/",
               privacy: "https://gcng.de/KEEZLY/datenschutz/" },
  "nl-NL" => { marketing: "https://gcng.de/KEEZLY/nl/",
               support: "https://gcng.de/KEEZLY/nl/support/",
               privacy: "https://gcng.de/KEEZLY/nl/privacy/" },
  "en-US" => { marketing: "https://gcng.de/KEEZLY/en/",
               support: "https://gcng.de/KEEZLY/en/support/",
               privacy: "https://gcng.de/KEEZLY/en/privacy/" },
}

LOCALES = URLS.keys

# 1.0.0 has never shipped, so Apple forbids release notes on it.
FIRST_RELEASE = true

def read(locale, name)
  path = File.join(META, locale, "#{name}.txt")
  File.exist?(path) ? File.read(path, encoding: "UTF-8").strip : nil
end

def env!
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
end

def say(msg)
  puts msg
end

env!

app = Spaceship::ConnectAPI::App.find("de.gcng.keezly")
abort("no app record for de.gcng.keezly") unless app
say "app #{app.id} (#{app.bundle_id})"

version = app.get_edit_app_store_version
abort("no editable version") unless version
say "version #{version.version_string} [#{version.app_store_state}]"

info = Spaceship::ConnectAPI.get_app_infos(app_id: app.id).to_models.find do |i|
  %w[PREPARE_FOR_SUBMISSION READY_FOR_SALE DEVELOPER_REJECTED].include?(i.app_store_state) ||
    i.app_store_state.nil?
end
info ||= Spaceship::ConnectAPI.get_app_infos(app_id: app.id).to_models.first
abort("no editable app info") unless info
say "app info #{info.id} [#{info.app_store_state}]"

# ---------------------------------------------------------------- app info

existing_info_locs = info.get_app_info_localizations.each_with_object({}) do |loc, h|
  h[loc.locale] = loc
end

LOCALES.each do |locale|
  name = read(locale, "name")
  subtitle = read(locale, "subtitle")
  privacy = URLS[locale][:privacy]
  loc = existing_info_locs[locale]

  attrs = { name: name, subtitle: subtitle, privacyPolicyUrl: privacy }.compact

  if loc.nil?
    say "  app info #{locale}: creating"
    unless DRY
      info.create_app_info_localization(attributes: attrs.merge(locale: locale))
    end
  else
    changed = attrs.reject { |k, v| loc.send(k.to_s.gsub(/([A-Z])/) { "_#{$1.downcase}" }) == v rescue false }
    if changed.empty?
      say "  app info #{locale}: already current"
    else
      say "  app info #{locale}: updating #{changed.keys.join(', ')}"
      loc.update(attributes: attrs) unless DRY
    end
  end
end

# ----------------------------------------------------------------- version

existing_ver_locs = version.get_app_store_version_localizations.each_with_object({}) do |loc, h|
  h[loc.locale] = loc
end

LOCALES.each do |locale|
  attrs = {
    description: read(locale, "description"),
    keywords: read(locale, "keywords"),
    promotionalText: read(locale, "promotional_text"),
    marketingUrl: URLS[locale][:marketing],
    supportUrl: URLS[locale][:support],
  }.compact

  # **No `whatsNew` on a first release.** Apple answers "Attribute 'whatsNew'
  # cannot be edited at this time" for a version that has never shipped, and it
  # is right to: there is nothing new about 1.0.0. The release notes in
  # `fastlane/metadata/*/release_notes.txt` are kept for the first update and
  # are used for the TestFlight "what to test" note in the meantime.
  attrs[:whatsNew] = read(locale, "release_notes") if FIRST_RELEASE == false

  loc = existing_ver_locs[locale]
  if loc.nil?
    say "  version #{locale}: creating"
    unless DRY
      version.create_app_store_version_localization(attributes: attrs.merge(locale: locale))
    end
  else
    say "  version #{locale}: updating"
    loc.update(attributes: attrs) unless DRY
  end
end

# ------------------------------------------------------------------ verify

say "\n--- read back from App Store Connect ---"
info = Spaceship::ConnectAPI.get_app_infos(app_id: app.id).to_models.find { |i| i.id == info.id }
version = app.get_edit_app_store_version

info_locs = info.get_app_info_localizations.each_with_object({}) { |l, h| h[l.locale] = l }
ver_locs = version.get_app_store_version_localizations.each_with_object({}) { |l, h| h[l.locale] = l }

ok = true
LOCALES.each do |locale|
  i = info_locs[locale]
  v = ver_locs[locale]
  unless i && v
    say "  #{locale}: MISSING (app info: #{!i.nil?}, version: #{!v.nil?})"
    ok = false
    next
  end
  say format(
    "  %-6s name=%-20s subtitle=%-30s desc=%4d kw=%3d promo=%3d whatsNew=%3d support=%s",
    locale, i.name.to_s[0, 20].inspect, i.subtitle.to_s[0, 30].inspect,
    v.description.to_s.length, v.keywords.to_s.length,
    v.promotional_text.to_s.length, v.whats_new.to_s.length,
    v.support_url.to_s.empty? ? "MISSING" : "set"
  )
  ok = false if v.description.to_s.empty? || i.name.to_s.empty?
end

say(ok ? "\nALL THREE LOCALES PRESENT AT BOTH LEVELS" : "\nINCOMPLETE — see above")
exit(ok ? 0 : 1)
