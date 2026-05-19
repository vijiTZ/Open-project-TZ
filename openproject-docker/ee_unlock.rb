# Enterprise feature unlock — applied via bind-mount initializer
Rails.application.config.after_initialize do
  EnterpriseToken.class_eval do
    class << self
      def allows_to?(*)
        true
      end

      def active?
        true
      end

      def trial_only?
        false
      end

      def hide_banners?
        true
      end

      def available_features
        Set.new(%i[
          sharing_user_link
          attribute_help_texts
          custom_fields_on_forms
          custom_actions
          two_factor_authentication
          ldap_groups
          board_view
          team_planner_view
          baseline_comparison
          work_package_sharing
          storage_s3_all_buckets
          work_package_export_pdf_with_images
          forms
          time_sheet_report
          project_list_sharing
          conditional_highlighting
          date_alerts
          progress_tracking
          portfolio_management
        ])
      end
    end

    def allows_to?(*)
      true
    end
  end
end
