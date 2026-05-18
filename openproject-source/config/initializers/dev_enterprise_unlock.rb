# frozen_string_literal: true

# Unlocks all enterprise/premium features for local development.
# Manually deployed into containers via docker cp — do NOT include in production images.

ALL_DEV_EE_FEATURES = %i[
  baseline_comparison
  calculated_values
  capture_external_links
  custom_actions
  custom_field_hierarchies
  customize_life_cycle
  date_alerts
  define_custom_style
  edit_attribute_groups
  gantt_pdf_export
  internal_comments
  ldap_groups
  mcp_server
  meeting_templates
  nextcloud_sso
  one_drive_sharepoint_file_storage
  placeholder_users
  portfolio_management
  project_creation_wizard
  readonly_work_packages
  scim_api
  sso_auth_providers
  team_planner_view
  time_entry_time_restrictions
  virus_scanning
  work_package_query_relation_columns
  work_package_sharing
  work_package_subject_generation
].to_set.freeze

Rails.application.config.after_initialize do
  EnterpriseToken.class_eval do
    class << self
      def allows_to?(_feature)
        true
      end

      def active?
        true
      end

      def trial_only?
        false
      end

      def available_features
        ALL_DEV_EE_FEATURES
      end

      def trialling_features
        Set.new
      end

      def trialling?(_feature)
        false
      end

      def hide_banners?
        true
      end

      def user_limit
        nil
      end

      def user_limit_reached?
        false
      end
    end

    def allows_to?(_feature)
      true
    end
  end

  Authorization::EnterpriseService.class_eval do
    def call(_feature)
      ServiceResult.new(success: true, result: true)
    end
  end
end
