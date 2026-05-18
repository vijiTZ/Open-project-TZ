# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Projects
  module Settings
    module Backlogs
      class SharingForm < ApplicationForm
        form do |sharing_form|
          # TODO: Remove this hidden field, once the `radio_button_group` supports rendering
          # the hidden empty field.
          # The purpose of the hidden field is to ensure we submit the `sprint_sharing` field
          # even if no radio button is chosen. Otherwise, the submitted form will not include
          # the field at all and the save request will return success when in fact no setting
          # is saved.
          # Ideally the hidden field should automatically be rendered by the `radio_button_group`
          # helper, similar to how the `collection_radio_buttons` rails helper does.
          sharing_form.hidden(name: :sprint_sharing, value: "")

          sharing_form.radio_button_group(
            name: :sprint_sharing,
            label: I18n.t("projects.settings.backlog_sharing.sprint_sharing")
          ) do |group|
            Project::SPRINT_SHARING_MODES.each do |option|
              group.radio_button(
                label: sharing_option_text(option, :label),
                value: option,
                checked: checked?(option),
                disabled: disabled?(option),
                caption: caption_for(option),
                data: { "show-when-value-selected-target": "cause" }
              )
            end
          end

          sharing_form.html_content { banner_for(Project::SHARE_SUBPROJECTS, type: :info) }
          sharing_form.html_content { banner_for(Project::RECEIVE_SHARED, type: :warning) }

          sharing_form.submit(
            name: :submit,
            label: I18n.t("button_save"),
            scheme: :primary
          )
        end

        private

        def checked?(option)
          option == model.sprint_sharing
        end

        def disabled?(option)
          option == Project::SHARE_ALL_PROJECTS && share_all_projects_disabled?
        end

        def sharing_option_text(option, key, **)
          I18n.t("projects.settings.backlog_sharing.options.#{option}.#{key}", **)
        end

        def caption_for(option)
          if disabled?(option)
            if User.current.allowed_in_project?(:view_project, global_sprint_sharer)
              sharing_option_text(option, :disabled_caption, name: global_sprint_sharer.name)
            else
              sharing_option_text(option, :disabled_caption_anonymous)
            end
          else
            sharing_option_text(option, :caption)
          end
        end

        def share_all_projects_disabled?
          global_sprint_sharer && global_sprint_sharer != model
        end

        def global_sprint_sharer
          @global_sprint_sharer ||= Project.global_sprint_sharer
        end

        def banner_for(option, type: :info)
          banner_arguments =
            type == :warning ? { scheme: :warning } : { icon: :info }

          render(Primer::BaseComponent.new(
                   tag: :div,
                   hidden: model.sprint_sharing != option,
                   data: { value: option, "show-when-value-selected-target": "effect" }
                 )) do
            render(Primer::Alpha::Banner.new(**banner_arguments)) do
              sharing_option_text(option, type)
            end
          end
        end
      end
    end
  end
end
