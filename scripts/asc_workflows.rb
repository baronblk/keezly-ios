# frozen_string_literal: true

# Creates Keezly's three Xcode Cloud workflows through the App Store Connect
# REST API.
#
#   bundle exec ruby scripts/asc_workflows.rb [--dry-run]
#
# Idempotent by name: a workflow that already exists is updated, never
# duplicated, because a second "Keezly Release" would be indistinguishable in
# the interface and both would run.
#
# The toolchain for Release is pinned rather than left at "Latest Release"
# (§10 of the release brief). A release build must be reproducible, and "latest"
# is a moving target that can change what ships between one build and the next.
# CI and Main stay on Latest Release deliberately: their job is to find out
# early when a new Xcode breaks the project.

$LOAD_PATH.unshift File.expand_path(__dir__)
require "json"
require "asc_client"

DRY = ARGV.include?("--dry-run")

PRODUCT    = "e0972f02-56f2-47c1-adf8-3940083909fe"
REPOSITORY = "348b83b6-689e-46e1-ac9a-68ffc71049c6"
SCHEME     = "Keezly"

# The exact toolchain that produced green builds 4 and 5.
XCODE_PINNED  = "61944704-7a99-4e44-917c-0ade12ce6c45" # Xcode 27 (27A266a)
XCODE_LATEST  = "31ce63a2-a54f-3e25-b883-dc13290abb7f" # Latest Release
# Apple offers exactly three macOS choices for Xcode 27, and only one of them
# is not a beta. Recorded here so the next reader does not think the pin was
# forgotten: it is as specific as Apple allows for this Xcode.
MACOS_LATEST  = "31ce63a2-a54f-3e25-b883-dc13290abb7f" # Latest Release (26A428)

def build_action(name: "Build - iOS")
  {
    "name" => name, "actionType" => "BUILD", "destination" => "ANY_IOS_DEVICE",
    "buildDistributionAudience" => nil, "testConfiguration" => nil,
    "scheme" => SCHEME, "platform" => "IOS", "isRequiredToPass" => true
  }
end

# The same two devices the local `ui_tests` lane uses, so a cloud failure and a
# desk failure are about the same thing. Apple wants the destinations named
# explicitly; "any simulator" is refused.
TEST_DESTINATIONS = [
  {
    "deviceTypeName" => "iPhone 17",
    "deviceTypeIdentifier" => "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
    "runtimeName" => "iOS 27.0",
    "runtimeIdentifier" => "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
    "kind" => "SIMULATOR"
  },
  {
    "deviceTypeName" => "iPad Pro 13-inch (M5)",
    "deviceTypeIdentifier" => "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB",
    "runtimeName" => "iOS 27.0",
    "runtimeIdentifier" => "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
    "kind" => "SIMULATOR"
  }
].freeze

def test_action(name: "Test - iOS")
  {
    "name" => name, "actionType" => "TEST", "destination" => nil,
    "buildDistributionAudience" => nil,
    "testConfiguration" => {
      "kind" => "USE_SCHEME_SETTINGS",
      "testPlanName" => nil,
      "testDestinations" => TEST_DESTINATIONS
    },
    "scheme" => SCHEME, "platform" => "IOS", "isRequiredToPass" => true
  }
end

def analyze_action(name: "Analyze - iOS")
  {
    "name" => name, "actionType" => "ANALYZE", "destination" => "ANY_IOS_DEVICE",
    "buildDistributionAudience" => nil, "testConfiguration" => nil,
    "scheme" => SCHEME, "platform" => "IOS", "isRequiredToPass" => true
  }
end

# INTERNAL_ONLY on purpose: it reaches TestFlight's internal testers and does
# not start an external beta review. Neither this script nor any workflow it
# makes submits anything for App Review.
def archive_action(name: "Archive - iOS")
  {
    "name" => name, "actionType" => "ARCHIVE", "destination" => nil,
    "buildDistributionAudience" => "INTERNAL_ONLY", "testConfiguration" => nil,
    "scheme" => SCHEME, "platform" => "IOS", "isRequiredToPass" => true
  }
end

BRANCH_MAIN = {
  "source" => { "isAllMatch" => false, "patterns" => [{ "pattern" => "main", "isPrefix" => false }] },
  "filesAndFoldersRule" => nil, "autoCancel" => true
}.freeze

PULL_REQUESTS = {
  "source" => { "isAllMatch" => true, "patterns" => [] },
  "destination" => { "isAllMatch" => false, "patterns" => [{ "pattern" => "main", "isPrefix" => false }] },
  "filesAndFoldersRule" => nil, "autoCancel" => true
}.freeze

WORKFLOWS = [
  {
    name: "Keezly CI",
    description: "Pull requests into main: build and test. Fast enough to run on every push.",
    actions: [build_action, test_action],
    branch: nil, pull_request: PULL_REQUESTS, manual: false,
    xcode: XCODE_LATEST, macos: MACOS_LATEST
  },
  {
    name: "Keezly Main",
    description: "Every merge to main: build, test and analyze.",
    actions: [build_action, test_action, analyze_action],
    branch: BRANCH_MAIN, pull_request: nil, manual: false,
    xcode: XCODE_LATEST, macos: MACOS_LATEST
  },
  {
    name: "Keezly Release",
    description: "Started by hand: test, analyze and archive to TestFlight internal testers. Never submits for review.",
    actions: [test_action, analyze_action, archive_action],
    branch: nil, pull_request: nil, manual: true,
    xcode: XCODE_PINNED, macos: MACOS_LATEST
  }
].freeze

c = ASC::Client.new
existing = c.all("v1/ciProducts/#{PRODUCT}/workflows")
              .each_with_object({}) { |w, h| h[w.dig("attributes", "name")] = w }
puts "workflows already present: #{existing.keys.sort.join(', ')}"

if DRY
  WORKFLOWS.each do |w|
    puts format("  %-16s %-8s %s", w[:name], existing[w[:name]] ? "update" : "create",
                w[:actions].map { |a| a["actionType"] }.join("+"))
  end
  puts "\n--dry-run: nothing sent"
  exit 0
end

WORKFLOWS.each do |w|
  attributes = {
    "name" => w[:name],
    "description" => w[:description],
    "isLockedForEditing" => false,
    "isEnabled" => true,
    "clean" => true,
    "containerFilePath" => "Keezly.xcodeproj",
    "actions" => w[:actions],
    "branchStartCondition" => w[:branch],
    "pullRequestStartCondition" => w[:pull_request],
    "manualBranchStartCondition" => w[:manual] ? { "source" => { "isAllMatch" => false, "patterns" => [{ "pattern" => "main", "isPrefix" => false }] } } : nil
  }.compact

  if (found = existing[w[:name]])
    print "  #{w[:name]}: updating #{found['id']} ... "
    c.patch("v1/ciWorkflows/#{found['id']}", {
      "data" => { "type" => "ciWorkflows", "id" => found["id"], "attributes" => attributes }
    })
    puts "ok"
  else
    print "  #{w[:name]}: creating ... "
    created = c.post("v1/ciWorkflows", {
      "data" => {
        "type" => "ciWorkflows",
        "attributes" => attributes,
        "relationships" => {
          "product" => { "data" => { "type" => "ciProducts", "id" => PRODUCT } },
          "repository" => { "data" => { "type" => "scmRepositories", "id" => REPOSITORY } },
          "xcodeVersion" => { "data" => { "type" => "ciXcodeVersions", "id" => w[:xcode] } },
          "macOsVersion" => { "data" => { "type" => "ciMacOsVersions", "id" => w[:macos] } }
        }
      }
    })["data"]
    puts created["id"]
  end
end

# ------------------------------------------------------------------- verify
puts "\n--- read back from App Store Connect ---"
final = c.all("v1/ciProducts/#{PRODUCT}/workflows")
ok = true
final.sort_by { |w| w.dig("attributes", "name").to_s }.each do |w|
  a = w["attributes"]
  actions = (a["actions"] || []).map { |x| x["actionType"] }.join("+")
  trigger = if a["pullRequestStartCondition"] then "pull request"
            elsif a["branchStartCondition"] then "branch"
            else "manual"
            end
  puts format("  %-16s %-22s %-12s enabled=%s", a["name"], actions, trigger, a["isEnabled"])
end
wanted = WORKFLOWS.map { |w| w[:name] }
have = final.map { |w| w.dig("attributes", "name") }
missing = wanted - have
ok = missing.empty?
puts missing.empty? ? "\nWORKFLOWS = ASC VERIFIED" : "\nMISSING: #{missing.join(', ')}"
exit(ok ? 0 : 1)
