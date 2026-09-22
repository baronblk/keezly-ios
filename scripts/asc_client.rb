# frozen_string_literal: true

# A small App Store Connect REST client.
#
# Exists because parts of the API that Keezly needs are not wrapped by
# fastlane's spaceship — Game Center's v2 resources in particular. The absence
# of a spaceship model is a fact about spaceship, not about the API, and is not
# a reason to fall back to a web form.
#
# Everything here is the documented REST interface with the same ES256 JWT the
# rest of the project already authenticates with. No credential is read from or
# written to the repository: the key path comes from `KEEZLY_ASC_ENV`, which
# points outside it.

require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

module ASC
  HOST = "api.appstoreconnect.apple.com"

  class Error < StandardError
    attr_reader :status, :body

    def initialize(status, body)
      @status = status
      @body = body
      detail = begin
        JSON.parse(body)["errors"]&.map { |e| "#{e['title']}: #{e['detail']}" }&.join(" | ")
      rescue StandardError
        nil
      end
      super("HTTP #{status} — #{detail || body.to_s[0, 400]}")
    end
  end

  class Client
    def initialize
      path = ENV.fetch("KEEZLY_ASC_ENV")
      File.readlines(path, encoding: "UTF-8").each do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")
        k, v = line.split("=", 2)
        ENV[k] = v if k && v
      end
      @key_id = ENV.fetch("KEEZLY_ASC_KEY_ID")
      @issuer = ENV.fetch("KEEZLY_ASC_ISSUER_ID")
      @key = OpenSSL::PKey::EC.new(File.read(File.expand_path(ENV.fetch("KEEZLY_ASC_KEY_PATH"))))
    end

    # ES256, signed by hand so the only dependency is OpenSSL.
    def token
      now = Time.now.to_i
      return @token if @token && @token_expires > now + 60

      header = { alg: "ES256", kid: @key_id, typ: "JWT" }
      claims = { iss: @issuer, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" }
      signing_input = [header, claims].map { |p| b64(JSON.generate(p)) }.join(".")

      der = @key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
      r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
      @token = "#{signing_input}.#{b64(r + s)}"
      @token_expires = now + 1200
      @token
    end

    def get(path, params = {})
      uri = URI::HTTPS.build(host: HOST, path: normalise(path))
      uri.query = URI.encode_www_form(params) unless params.empty?
      request(Net::HTTP::Get.new(uri))
    end

    def post(path, body)
      uri = URI::HTTPS.build(host: HOST, path: normalise(path))
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)
      request(req)
    end

    def patch(path, body)
      uri = URI::HTTPS.build(host: HOST, path: normalise(path))
      req = Net::HTTP::Patch.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)
      request(req)
    end

    # Apple's asset uploads are plain HTTP against a URL it hands back, with
    # headers it also hands back. Not a JSON API call.
    def upload(operation, bytes)
      uri = URI(operation["url"])
      req = Net::HTTP::Put.new(uri)
      (operation["requestHeaders"] || []).each { |h| req[h["name"]] = h["value"] }
      req.body = bytes
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 180
      res = http.request(req)
      raise Error.new(res.code.to_i, res.body) unless res.code.to_i.between?(200, 299)
      true
    end

    # Follows pagination so a caller never sees a half answer.
    def all(path, params = {})
      out = []
      page = get(path, params.merge(limit: 200))
      loop do
        out.concat(page["data"] || [])
        nxt = page.dig("links", "next")
        break unless nxt
        page = request(Net::HTTP::Get.new(URI(nxt)))
      end
      out
    end

    private

    def normalise(path)
      path.start_with?("/") ? path : "/#{path}"
    end

    def b64(data)
      Base64.urlsafe_encode64(data).delete("=")
    end

    def request(req)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      http = Net::HTTP.new(HOST, 443)
      http.use_ssl = true
      http.read_timeout = 120
      res = http.request(req)
      code = res.code.to_i
      raise Error.new(code, res.body) unless code.between?(200, 299)
      res.body.to_s.empty? ? {} : JSON.parse(res.body)
    end
  end
end
