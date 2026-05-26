# Replaces the default OpenProject logo used in all PDF exports
# (work-package single + list, project export, cost/timesheet reports)
# with the Tamilzorous brand logo.
#
# The image is served from the ./assets bind-mount declared in
# docker-compose.override.yml — see /app/public/tz-assets/tamilzorous-logo.png
# inside the container.
#
# Priority order preserved from upstream Exports::PDF::Common::Logo:
#   1. CustomStyle.current.export_logo  (Admin → Design → Export logo upload)
#   2. Tamilzorous logo (this override)
#   3. Stock OpenProject logo (only if the TZ file is missing)

Rails.application.config.after_initialize do
  tz_logo_path = "/app/public/tz-assets/tamilzorous-logo.png"

  Exports::PDF::Common::Logo.module_eval do
    define_method(:logo_image_filename) do
      custom_logo_image_filename ||
        (File.exist?(tz_logo_path) ? tz_logo_path : Rails.root.join("app/assets/images/logo_openproject.png"))
    end
  end
end
