# frozen_string_literal: true

# TZ custom mailer for work package notifications.
# Shows proper subject lines and full WP details in the email body.

class TzWorkPackageMailer < ApplicationMailer
  helper :mail_notification

  def notify(recipient, journal, reason)
    @user = recipient
    @work_package = journal.journable
    @journal = journal
    @reason = reason
    @author = journal.user

    # Attach logos as inline CID so they work in all email clients
    logo_path = Rails.root.join("public", "tz-assets", "tamilzorous-logo.png")
    attachments.inline["tz-logo.png"] = File.read(logo_path) if File.exist?(logo_path)

    slogan_path = Rails.root.join("public", "tz-assets", "tamilzorous-logo-slogan.png")
    attachments.inline["tz-logo-slogan.png"] = File.read(slogan_path) if File.exist?(slogan_path)

    User.execute_as @author do
      set_work_package_headers(@work_package)
      message_id journal, recipient
      references journal

      send_localized_mail(recipient) do
        tz_subject_for(reason, @author, @work_package)
      end
    end
  end

  private

  def tz_subject_for(reason, author, wp)
    case reason
    when :assigned
      "#{author.name} assigned you a task: ##{wp.id} - #{wp.subject}"
    when :responsible
      "#{author.name} made you accountable for: ##{wp.id} - #{wp.subject}"
    when :commented
      "#{author.name} commented on: ##{wp.id} - #{wp.subject}"
    when :created
      "#{author.name} created: ##{wp.id} - #{wp.subject}"
    when :shared
      "#{author.name} shared with you: ##{wp.id} - #{wp.subject}"
    when :watched
      "Update on watched task: ##{wp.id} - #{wp.subject}"
    when :mentioned
      "#{author.name} mentioned you in: ##{wp.id} - #{wp.subject}"
    else
      "#{author.name} updated: ##{wp.id} - #{wp.subject}"
    end
  end

  def set_work_package_headers(work_package)
    open_project_headers "Project" => work_package.project.identifier,
                         "WorkPackage-Id" => work_package.id,
                         "WorkPackage-Author" => work_package.author.login,
                         "Type" => "WorkPackage"

    if work_package.assigned_to
      open_project_headers "WorkPackage-Assignee" => work_package.assigned_to.login
    end
  end
end
