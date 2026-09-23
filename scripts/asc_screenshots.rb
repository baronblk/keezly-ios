# frozen_string_literal: true

# Uploads Keezly's store screenshots to App Store Connect, and proves they
# arrived.
#
#   bundle exec ruby scripts/asc_screenshots.rb [--dry-run]
#
# Apple's asset upload is three steps and a successful reserve is not an
# upload: reserve the asset, PUT the bytes at the URL Apple hands back, then
# mark it uploaded with the file's MD5. Anything less and the screenshot sits
# in App Store Connect as a grey box.
#
# Idempotent per set: a display type that already holds exactly the images we
# want is left alone; one that holds anything else is emptied and rebuilt,
# because a half-replaced series is worse than either.
#
# The order matters. App Store Connect shows screenshots in the order they were
# uploaded, so the files are numbered and uploaded in that order, and the order
# is read back afterwards.

$LOAD_PATH.unshift File.expand_path(__dir__)
require "digest"
require "json"
require "asc_client"

DRY = ARGV.include?("--dry-run")
ROOT = File.expand_path("..", __dir__)
FOLDER = File.join(ROOT, "artifacts", "store-screenshots")
VERSION = "6a82ef5c-f5bf-4a85-9cce-71858cf32903"

# Apple's names for the two sizes Keezly ships.
DISPLAY_TYPE = {
  "iphone" => "APP_IPHONE_67",
  "ipad" => "APP_IPAD_PRO_3GEN_129",
}.freeze

LOCALE = { "de" => "de-DE", "nl" => "nl-NL", "en" => "en-US" }.freeze

manifest = JSON.parse(File.read(File.join(FOLDER, "selection.json"), encoding: "UTF-8"))
c = ASC::Client.new

localizations = c.all("v1/appStoreVersions/#{VERSION}/appStoreVersionLocalizations")
                 .each_with_object({}) { |l, h| h[l.dig("attributes", "locale")] = l["id"] }
puts "version localizations: #{localizations.keys.sort.join(', ')}"

if DRY
  manifest.each do |series, entries|
    device, locale = series.split("-")
    puts format("  %-10s -> %-6s %-22s %d images", series, LOCALE[locale], DISPLAY_TYPE[device], entries.size)
  end
  puts "\n--dry-run: nothing sent"
  exit 0
end

manifest.sort.each do |series, entries|
  device, locale = series.split("-")
  display = DISPLAY_TYPE.fetch(device)
  localization = localizations.fetch(LOCALE.fetch(locale))

  sets = c.all("v1/appStoreVersionLocalizations/#{localization}/appScreenshotSets")
  set = sets.find { |s| s.dig("attributes", "screenshotDisplayType") == display }

  if set
    have = c.all("v1/appScreenshotSets/#{set['id']}/appScreenshots")
    wanted = entries.map { |e| e["file"] }
    if have.map { |s| s.dig("attributes", "fileName") } == wanted &&
       have.all? { |s| s.dig("attributes", "assetDeliveryState", "state") == "COMPLETE" }
      puts "  #{series}: already exactly right (#{have.size})"
      next
    end
    puts "  #{series}: replacing #{have.size} existing"
    have.each { |s| c.delete("v1/appScreenshots/#{s['id']}") }
  else
    set = c.post("v1/appScreenshotSets", {
      "data" => {
        "type" => "appScreenshotSets",
        "attributes" => { "screenshotDisplayType" => display },
        "relationships" => {
          "appStoreVersionLocalization" => {
            "data" => { "type" => "appStoreVersionLocalizations", "id" => localization }
          }
        }
      }
    })["data"]
  end

  print "  #{series}: "
  entries.each do |entry|
    path = File.join(FOLDER, series, entry["file"])
    bytes = File.binread(path)

    reserved = c.post("v1/appScreenshots", {
      "data" => {
        "type" => "appScreenshots",
        "attributes" => { "fileName" => entry["file"], "fileSize" => bytes.bytesize },
        "relationships" => {
          "appScreenshotSet" => { "data" => { "type" => "appScreenshotSets", "id" => set["id"] } }
        }
      }
    })["data"]

    (reserved.dig("attributes", "uploadOperations") || []).each { |op| c.upload(op, bytes) }

    c.patch("v1/appScreenshots/#{reserved['id']}", {
      "data" => {
        "type" => "appScreenshots",
        "id" => reserved["id"],
        "attributes" => { "uploaded" => true, "sourceFileChecksum" => Digest::MD5.hexdigest(bytes) }
      }
    })
    print "."
    $stdout.flush
  end
  puts " #{entries.size} uploaded"
end

# -------------------------------------------------------------------- verify
puts "\n--- read back from App Store Connect ---"
ok = true
manifest.sort.each do |series, entries|
  device, locale = series.split("-")
  display = DISPLAY_TYPE.fetch(device)
  localization = localizations.fetch(LOCALE.fetch(locale))
  set = c.all("v1/appStoreVersionLocalizations/#{localization}/appScreenshotSets")
        .find { |s| s.dig("attributes", "screenshotDisplayType") == display }

  unless set
    puts "  #{series}: NO SET"
    ok = false
    next
  end

  have = c.all("v1/appScreenshotSets/#{set['id']}/appScreenshots")
  states = have.map { |s| s.dig("attributes", "assetDeliveryState", "state") }
  order_ok = have.map { |s| s.dig("attributes", "fileName") } == entries.map { |e| e["file"] }
  complete = states.all? { |s| s == "COMPLETE" }
  # The count is whatever the selection says, not a fixed ten. Apple allows up
  # to ten; a series is as long as it has good images for, and padding it to
  # reach a number is how a bad screenshot gets shipped.
  ok &&= have.size == entries.size && order_ok && complete

  puts format("  %-10s %-6s %-22s count=%2d order=%-3s states=%s",
              series, LOCALE[locale], display, have.size,
              order_ok ? "ok" : "BAD", states.uniq.join(","))
end

total = manifest.values.sum(&:size)
puts(ok ? "\nSCREENSHOTS = ASC UPLOADED AND VERIFIED (#{total} images, order and delivery state confirmed)"
        : "\nNOT RIGHT — see above")
puts "Human review is a separate gate: SCREENSHOT_REVIEW.html."
exit(ok ? 0 : 1)
