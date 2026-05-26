# Adds a leading :select checkbox column to the admin Users index table.
#
# Strategy: build two small modules and `prepend` them onto
# Users::TableComponent and Users::RowComponent. Prepending puts the module
# ABOVE the class in the ancestor chain, so `super` in our overrides cleanly
# delegates to the original implementation. (class_eval + def would have
# replaced the original instead — that bug 500'd the page on the first try.)
#
# Wrapped in begin/rescue so a future OpenProject upgrade that renames or
# removes one of these classes can't crash app boot — worst case the
# feature silently disappears until the patch is updated.

module TzUsersTableColumnSelect
  def columns
    @tz_columns_with_select ||= begin
      original = super
      rest = Array(original).reject do |c|
        attr = c.respond_to?(:attribute) ? c.attribute.to_s : c.to_s
        attr == "select"
      end
      [:select] + rest
    end
  end

  def sortable_column?(column)
    attr = column.respond_to?(:attribute) ? column.attribute : column
    return false if attr.to_s == "select"
    super
  end

  def header_options(column)
    attr = column.respond_to?(:attribute) ? column.attribute : column
    if attr.to_s == "select"
      master = helpers.tag.input(
        type: "checkbox",
        class: "form--check-box tz-master-checkbox",
        "aria-label": "Select all users",
        "data-tz-master": "1"
      )
      { caption: master }
    else
      super
    end
  end
end

module TzUsersRowSelectCell
  def select
    helpers.tag.input(
      type: "checkbox",
      class: "form--check-box tz-user-checkbox",
      value: user.id,
      name: "user_ids[]",
      "data-user-id": user.id,
      "aria-label": "Select user #{user.login}"
    )
  end

  def column_css_class(column)
    attr = column.respond_to?(:attribute) ? column.attribute : column
    return "tz-select-cell" if attr.to_s == "select"
    super
  end
end

Rails.application.config.after_initialize do
  begin
    Users::TableComponent.prepend(TzUsersTableColumnSelect)
    Users::RowComponent.prepend(TzUsersRowSelectCell)
  rescue => e
    Rails.logger&.error("[tz] users_table_checkbox initializer failed: #{e.class}: #{e.message}")
  end
end
