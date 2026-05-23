# frozen_string_literal: true

# Tamil Zorous: Send instant emails for all important work-package events
# (not just @mentions).
#
# By default OpenProject only sends immediate emails when someone is
# @mentioned.  This patch extends that to: assigned, responsible,
# commented, created, shared, and watched — so users get a real-time
# inbox notification whenever something important happens on a work
# package they care about.

Rails.application.config.after_initialize do
  strategy = Notifications::CreateFromModelService::WorkPackageStrategy

  strategy.define_singleton_method(:supports_mail?) do |reason|
    reason.in?(%i[mentioned assigned responsible commented created shared watched])
  end
end
