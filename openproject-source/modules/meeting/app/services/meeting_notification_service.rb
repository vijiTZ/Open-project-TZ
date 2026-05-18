# frozen_string_literal: true
class MeetingNotificationService
  attr_reader :meeting, :content_type

  def initialize(meeting)
    @meeting = meeting
  end

  def call(action, **)
    if meeting.notify?
      recipients_with_errors = send_notifications!(action, **)
      ServiceResult.new(success: recipients_with_errors.empty?, errors: recipients_with_errors)
    else
      ServiceResult.failure(errors: meeting.participants.includes(:user))
    end
  end

  private

  def send_notifications!(action, **)
    recipients_with_errors = []
    meeting.participants.includes(:user).find_each do |recipient|
      MeetingMailer.send(action, meeting, recipient.user, User.current, **).deliver_later
    rescue StandardError => e
      Rails.logger.error do
        "Failed to deliver #{action} notification to #{recipient.mail}: #{e.message}"
      end
      recipients_with_errors << recipient
    end

    recipients_with_errors
  end
end
