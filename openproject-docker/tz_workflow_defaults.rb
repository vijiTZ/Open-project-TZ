# frozen_string_literal: true

# Tamil Zorous: Auto-heal workflow gaps on every boot.
#
# OpenProject's `workflows` table gates every status transition by
# (type, role, old_status -> new_status). If any row is missing, the
# user sees: "Status is invalid because no valid transition exists
# from old to new status for the current user's roles."
#
# Out of the box, only a subset of types and roles have rows seeded,
# and built-in roles like "Non member" have none at all — which makes
# global admins (who often aren't members of a project) hit the error
# whenever they drag a card on a Kanban board.
#
# This initializer fills any missing (type x role x old_status x
# new_status) cell for every non-anonymous role, in one idempotent
# SQL statement. It's cheap (single INSERT ... NOT EXISTS) and runs
# at boot, so adding a new status, type, or role auto-extends the
# matrix on the next container restart.

Rails.application.config.after_initialize do
  begin
    sql = <<~SQL
      INSERT INTO workflows (type_id, old_status_id, new_status_id, role_id, assignee, author)
      SELECT t.id, s1.id, s2.id, r.id, false, false
      FROM types t
      CROSS JOIN statuses s1
      CROSS JOIN statuses s2
      CROSS JOIN (SELECT id FROM roles WHERE name <> 'Anonymous') r
      WHERE NOT EXISTS (
        SELECT 1 FROM workflows w
        WHERE w.type_id = t.id AND w.role_id = r.id
          AND w.old_status_id = s1.id AND w.new_status_id = s2.id
      )
    SQL

    result = ActiveRecord::Base.connection.execute(sql)
    inserted = result.respond_to?(:cmd_tuples) ? result.cmd_tuples : 0
    if inserted.to_i > 0
      Rails.logger.info "[TZ] Workflow auto-heal: inserted #{inserted} missing transitions"
    end
  rescue => e
    Rails.logger.error "[TZ] Workflow auto-heal failed: #{e.message}"
  end
end
