# frozen_string_literal: true

module ResourcePlanners
  module Forms
    class DefaultViewForm < ApplicationForm
      form do |f|
        f.select_list(
          name: :default_view_class_name,
          label: ResourcePlanner.human_attribute_name(:default_view_class_name),
          required: true,
          input_width: :large
        ) do |select|
          ResourcePlanner.allowed_children.each do |class_name|
            select.option(
              value: class_name,
              label: I18n.t("resource_management.view_types.#{class_name}", default: class_name.underscore.humanize)
            )
          end
        end
      end
    end
  end
end
