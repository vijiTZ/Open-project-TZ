# Injects <link rel="stylesheet" href="/custom-redesign.css"> into every HTML
# response, just before </head>. The file is delivered via the bind-mount in
# docker-compose.override.yml at /app/public/custom-redesign.css.
#
# Why: a file in /app/public/ is reachable over HTTP but no OpenProject layout
# references it, so the browser never fetches it. This middleware adds the tag.
#
# Cache-buster: we append `?v=<hash>` to each asset URL so browsers refetch
# whenever the file changes. Previously this used File.mtime(...).to_i, but
# mtimes are unreliable across machines (a fresh `git clone` resets every
# mtime to checkout-time, and Docker bind-mounts on Windows/WSL2 sometimes
# lag behind host mtime updates). The result was that a teammate who pulled
# the latest code could still get the old cached JS from their browser
# because the served `?v=` token hadn't actually changed for them.
#
# Switched to a CONTENT HASH (first 10 hex chars of MD5). Same content on
# any machine → same hash → same URL → browser cache hit. One byte changes →
# different hash → different URL → forced refetch. Deterministic everywhere,
# immune to mtime quirks. MD5 is fine here because this is cache-busting, not
# a security/integrity check.

require "digest"

module CustomCssInjector
  CSS_URL    = "/custom-redesign.css".freeze
  CSS_FILE   = "/app/public/custom-redesign.css".freeze
  JS_URL     = "/tz-bulk-select.js".freeze
  JS_FILE    = "/app/public/tz-bulk-select.js".freeze
  TZ_JS_URL  = "/tz-table.js".freeze
  TZ_JS_FILE = "/app/public/tz-table.js".freeze
  LOGO_URL   = "/tz-assets/tamilzorous-logo.png".freeze
  LOGO_FILE  = "/app/public/tz-assets/tamilzorous-logo.png".freeze

  # Compute a short content hash for cache-busting. Returns "0" if the file
  # is missing so the middleware still emits a (broken) tag we can debug in
  # the browser network panel rather than silently dropping it.
  def self.asset_version(path)
    return "0" unless File.exist?(path)
    Digest::MD5.file(path).hexdigest[0, 10]
  rescue StandardError
    "0"
  end

  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)

      ct = (headers["Content-Type"] || headers["content-type"]).to_s
      return [status, headers, response] unless ct.start_with?("text/html")

      body = +""
      response.each { |chunk| body << chunk.to_s }
      response.close if response.respond_to?(:close)

      if body.include?("</head>")
        css_ver   = CustomCssInjector.asset_version(CSS_FILE)
        js_ver    = CustomCssInjector.asset_version(JS_FILE)
        tz_js_ver = CustomCssInjector.asset_version(TZ_JS_FILE)
        logo_ver  = CustomCssInjector.asset_version(LOGO_FILE)
        link      = %(<link rel="stylesheet" href="#{CSS_URL}?v=#{css_ver}">)
        script    = %(<script src="#{JS_URL}?v=#{js_ver}" defer></script>)
        tz_script = %(<script src="#{TZ_JS_URL}?v=#{tz_js_ver}" defer></script>)
        # Inline style overrides the logo URL with a content-hash cache-buster
        # so browsers refetch the PNG whenever the file content changes.
        logo_url   = "#{LOGO_URL}?v=#{logo_ver}"
        logo_style = %(<style id="tz-logo-cachebust">.op-logo--link,.op-logo--link_high_contrast,.op-logo--icon,.op-logo--icon_white{background-image:url("#{logo_url}") !important;}</style>)
        body = body.sub("</head>", "#{link}\n#{logo_style}\n#{script}\n#{tz_script}\n</head>")
        headers.delete_if { |k, _| %w[content-length etag].include?(k.to_s.downcase) }
      end

      [status, headers, [body]]
    rescue => e
      Rails.logger&.error("CustomCssInjector failed: #{e.class}: #{e.message}")
      [status, headers, [body || ""]]
    end
  end
end

Rails.application.config.middleware.use CustomCssInjector::Middleware
