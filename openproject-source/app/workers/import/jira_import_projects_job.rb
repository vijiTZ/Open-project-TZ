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

module Import
  class JiraImportProjectsJob < ApplicationJob
    include Import::JiraOpenProjectReferenceCreation
    include JiraImportCustomFields

    # rubocop:disable Metrics/AbcSize
    def perform(jira_import_id)
      @jira_import = Import::JiraImport.find(jira_import_id)
      jira = @jira_import.jira
      @jira_id = jira.id
      @user = User.system
      @jira_client = Import::JiraClient.new(url: jira.url, personal_access_token: jira.personal_access_token)

      ActiveRecord::Base.transaction do
        @project_role = setup_project_role
        custom_field_registry = build_custom_field_registry

        Import::JiraProject.where(jira_id: @jira_id, jira_project_id: @jira_import.project_ids).find_each do |jira_project|
          project = import_project(jira_project)
          update_custom_fields_in_project(project, jira_project, custom_field_registry)
          Import::JiraIssue.where(jira_id: @jira_id, jira_project_id: jira_project.id).find_each do |jira_issue|
            import_issue(jira_issue, project, custom_field_registry)
          end
        end
      end
    end

    private

    def setup_project_role
      service_call = Roles::CreateService.new(user: @user).call(
        name: "JiraMember",
        permissions: %i[add_work_packages
                        view_work_packages
                        add_work_package_comments
                        add_work_package_attachments
                        work_package_assigned]
      )
      if service_call.success?
        create_reference!(op_leg: service_call.result, jira_leg: nil, jira_import: @jira_import, uses_existing: false)
      elsif service_call.errors.find { |error| error.type == :taken }.blank?
        raise service_call.message
      end
      Role.find_by!(name: "JiraMember")
    end

    def import_project(jira_project)
      project_key = jira_project.payload.fetch("key")
      identifier = Setting::WorkPackageIdentifier.semantic? ? project_key.upcase : project_key.downcase
      service_call = Projects::CreateService
                       .new(user: @user, contract_class: EmptyContract)
                       .call(
                         name: jira_project.payload.fetch("name"),
                         identifier:,
                         description: jira_project.payload.fetch("description"),
                         active: true,
                         public: false,
                         parent: nil,
                         status_code: nil,
                         status_explanation: nil,
                         templated: false,
                         workspace_type: "project"
                       )
      if service_call.success?
        create_reference!(op_leg: service_call.result, jira_leg: jira_project, jira_import: @jira_import, uses_existing: false)
        return service_call.result
      end

      if (error = service_call.errors.find { |e| e.attribute == :identifier && e.type == :taken }) && error.present?
        taken_identifier = error.options[:value]
        raise I18n.t(:"admin.jira.run.project_identifier_taken", taken_identifier:)
      end

      raise service_call.message
    end

    def import_issue(jira_issue, project, custom_field_registry)
      type = import_type(jira_issue, project)
      status = import_status(jira_issue)
      update_workflows(type)
      new_custom_fields = new_custom_fields_in_type(jira_issue, type, custom_field_registry)
      update_custom_fields_in_type(type, new_custom_fields) if new_custom_fields.any?
      priority = import_priority(jira_issue)
      import_work_package(jira_issue, project, type, status, priority, custom_field_registry)
    end

    def new_custom_fields_in_type(jira_issue, type, custom_field_registry)
      existing_cf_ids = type.custom_field_ids
      cfs = custom_field_registry.filter_map do |entry|
        field_key = entry[:jira_field].jira_field_id
        raw_value = jira_issue.payload["fields"][field_key]
        next if raw_value.blank?

        context = find_context_for_issue(entry, jira_issue)
        context&.dig(:custom_field)
      end
      cfs.uniq.reject { |cf| existing_cf_ids.include?(cf.id) }
    end

    def update_custom_fields_in_type(type, new_custom_fields)
      type.custom_fields << new_custom_fields
      new_cf_keys = new_custom_fields.map(&:attribute_name)
      groups = type.attribute_groups.map { |g| [g.key, g.is_a?(Type::QueryGroup) ? [g.query_attribute_name] : g.attributes] }

      remove_custom_fields_from_other_groups(groups, new_cf_keys)
      add_or_update_jira_import_group(groups, new_cf_keys)

      type.attribute_groups = groups
      type.save!
      type.reload
    end

    def remove_custom_fields_from_other_groups(groups, cf_keys)
      groups.each do |group|
        next if group[0] == JIRA_IMPORT_GROUP_KEY

        group[1] -= cf_keys
      end
    end

    def add_or_update_jira_import_group(groups, cf_keys)
      jira_group = groups.find { |g| g[0] == JIRA_IMPORT_GROUP_KEY }
      if jira_group
        jira_group[1] |= cf_keys
      else
        groups << [JIRA_IMPORT_GROUP_KEY, cf_keys]
      end
    end

    def update_custom_fields_in_project(project, jira_project, custom_field_registry)
      project_key = jira_project.payload["key"]
      applicable_cfs = custom_field_registry.flat_map do |entry|
        entry[:contexts]
          .select { |ctx| context_applies_to_project?(ctx, project_key) }
          .map { |ctx| ctx[:custom_field] }
      end
      existing_cf_ids = project.work_package_custom_fields.pluck(:id).to_set
      new_cfs = applicable_cfs.uniq.reject { |cf| existing_cf_ids.include?(cf.id) }
      project.work_package_custom_fields << new_cfs if new_cfs.any?
    end

    def import_type(jira_issue, project)
      issue_type = jira_issue.payload["fields"]["issuetype"]
      type = Type.where("LOWER(name) = LOWER(?)", issue_type["name"]).first
      uses_existing = true

      if type.blank?
        service_call = WorkPackageTypes::CreateService
                         .new(user: @user)
                         .call(name: issue_type["name"], description: issue_type["description"], is_default: false)
        raise service_call.message unless service_call.success?

        type = service_call.result
        uses_existing = false
      end

      type.projects << project unless type.projects.include?(project)
      jira_issue_type = Import::JiraIssueType.find_by!(jira_issue_type_id: issue_type["id"], jira_id: @jira_id)
      create_reference!(op_leg: type, jira_leg: jira_issue_type, jira_import: @jira_import, uses_existing:)
      type
    end

    def import_status(jira_issue)
      issue_status = jira_issue.payload["fields"]["status"]
      status = Status.where("LOWER(name) = LOWER(?)", issue_status["name"]).first
      uses_existing = true
      if status.blank?
        status = Status.create!(name: issue_status["name"])
        uses_existing = false
      end
      jira_status = Import::JiraStatus.find_by!(jira_status_id: issue_status["id"], jira_id: @jira_id)
      create_reference!(op_leg: status, jira_leg: jira_status, jira_import: @jira_import, uses_existing:)
      status
    end

    def import_priority(jira_issue)
      issue_priority = jira_issue.payload["fields"]["priority"]
      priority = IssuePriority.where("LOWER(name) = LOWER(?)", issue_priority["name"]).first
      uses_existing = true
      if priority.blank?
        priority = IssuePriority.create!(name: issue_priority["name"])
        uses_existing = false
      end
      jira_priority = Import::JiraPriority.find_by!(jira_priority_id: issue_priority["id"], jira_id: @jira_id)
      create_reference!(op_leg: priority, jira_leg: jira_priority, jira_import: @jira_import, uses_existing:)
      priority
    end

    def update_workflows(type)
      statuses = Status.all
      row = statuses.to_h { |status| [status.id.to_s, ["always"]] }
      status_params = statuses.to_h { |status| [status.id.to_s, row] }
      call = Workflows::BulkUpdateService.new(role: @project_role, type:, tab: "always").call(status_params)
      raise call.message if call.failure?
    end

    def import_work_package(jira_issue, project, type, status, priority, custom_field_registry)
      # required because otherwise project.types does not include type and then wp creation fails.
      project.reload
      author_key = jira_issue.payload.dig("fields", "creator", "key")
      author = find_user(author_key)
      assignee_key = jira_issue.payload.dig("fields", "assignee", "key")
      assigned_to = find_user(assignee_key)

      [author, assigned_to].uniq.compact.each { |member| import_member(project, member) }
      description = Import::JiraWikiMarkupConverter.new(jira_issue.payload["fields"]["description"] || "").convert
      custom_field_attrs = collect_custom_field_attributes(custom_field_registry, jira_issue)

      service_call = WorkPackages::CreateService
                       .new(user: author || User.system, contract_class: EmptyContract)
                       .call(
                         project:,
                         subject: jira_issue.payload["fields"]["summary"],
                         description:,
                         type:,
                         priority:,
                         status:,
                         assigned_to:,
                         **custom_field_attrs
                       )
      raise service_call.message unless service_call.success?

      work_package = service_call.result
      create_reference!(op_leg: work_package, jira_leg: jira_issue, jira_import: @jira_import, uses_existing: false)
      import_work_package_history(work_package, jira_issue, project)
    end

    def import_work_package_history(work_package, jira_issue, project)
      journal_service = Import::JiraImportJournals.new(work_package:)

      jira_created_at = jira_issue.payload.dig("fields", "created")
      journal_service.update_creation_entry(date_time: jira_created_at) if jira_created_at.present?

      history = jira_issue.payload.dig("changelog", "histories")
      journal_service.add_history(history:) if history.present?

      comments = jira_issue.payload.dig("fields", "comment", "comments") || []
      comments.each do |comment|
        author = find_user(comment["author"]["key"])
        import_member(project, author)
        journal_service.add_comment(comment:, user: author)
      end

      journal_service.call

      attachments = jira_issue.payload.dig("fields", "attachment") || []
      attachments.each do |attachment|
        author = find_user(attachment["author"]["key"])
        import_member(project, author)
        import_attachment(work_package, attachment, author)
      end
    end

    def import_attachment(work_package, attachment, author)
      filename = attachment["filename"]
      content_url = attachment["content"]
      mime_type = attachment["mimeType"]
      size = attachment["size"]
      @jira_client.download_attachment(content_url, filename) do |tempfile|
        tempfile.rewind
        tempfile.define_singleton_method(:original_filename) { filename }
        tempfile.define_singleton_method(:content_type) { mime_type }
        tempfile.define_singleton_method(:size) { size }
        call = Attachments::CreateService
                 .new(user: author, contract_class: EmptyContract)
                 .call(container: work_package, filename:, file: tempfile)

        call.on_failure do
          raise call.message
        end
      end
    end

    def import_member(project, member)
      service_call = Members::CreateService
                       .new(user: @user, contract_class: EmptyContract)
                       .call(
                         project:,
                         roles: [@project_role],
                         user_id: member.id,
                         principal: member
                       )
      return if service_call.success?

      if service_call.errors.find { |error| error.type == :taken }.blank?
        raise service_call.message
      end
    end

    def find_user(jira_user_key)
      return if jira_user_key.blank?

      jira_user = Import::JiraUser.find_by(jira_user_key:, jira_import: @jira_import)
      if jira_user
        JiraOpenProjectReference.find_by!(
          jira_entity_class: "Import::JiraUser",
          jira_entity_id: jira_user.id
        ).op_leg
      else
        raise "Import::JiraUser with jira_user_key #{jira_user_key} not found!"
      end
    end

    # rubocop:enable Metrics/AbcSize
  end
end
