# Injects <link rel="stylesheet" href="/custom-redesign.css"> into every HTML
# response, just before </head>. The file is delivered via the bind-mount in
# docker-compose.override.yml at /app/public/custom-redesign.css.
#
# Why: a file in /app/public/ is reachable over HTTP but no OpenProject layout
# references it, so the browser never fetches it. This middleware adds the tag.

module CustomCssInjector
  CSS_URL  = "/custom-redesign.css".freeze
  CSS_FILE = "/app/public/custom-redesign.css".freeze
  JS_URL   = "/custom-redesign.js".freeze
  JS_FILE  = "/app/public/custom-redesign.js".freeze

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

      modified = false

      if body.include?("</head>")
        css_mtime = File.exist?(CSS_FILE) ? File.mtime(CSS_FILE).to_i : 0
        js_mtime  = File.exist?(JS_FILE)  ? File.mtime(JS_FILE).to_i  : 0
        tags = []
        tags << %(<link rel="stylesheet" href="#{CSS_URL}?v=#{css_mtime}">)
        tags << %(<script src="#{JS_URL}?v=#{js_mtime}" defer></script>) if File.exist?(JS_FILE)
        body = body.sub("</head>", "#{tags.join("\n")}\n</head>")
        modified = true
      end

      headers.delete_if { |k, _| %w[content-length etag].include?(k.to_s.downcase) } if modified

      [status, headers, [body]]
    rescue => e
      Rails.logger&.error("CustomCssInjector failed: #{e.class}: #{e.message}")
      [status, headers, [body || ""]]
    end
  end
end

Rails.application.config.middleware.use CustomCssInjector::Middleware
