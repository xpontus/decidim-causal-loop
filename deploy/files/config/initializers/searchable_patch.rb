# frozen_string_literal: true

# Patch for Decidim bug: contents_to_searchable_resource_attributes crashes when
# a resource has no searchable content for a given locale (returns nil instead of hash).
Decidim::Searchable.module_eval do
  def contents_to_searchable_resource_attributes(fields, locale)
    contents = fields[:i18n][locale]
    return { content_a: "", content_b: "", content_c: "", content_d: "" } if contents.nil?

    {
      content_a: I18n.transliterate(contents[:A] || ""),
      content_b: I18n.transliterate(contents[:B] || ""),
      content_c: I18n.transliterate(contents[:C] || ""),
      content_d: I18n.transliterate(contents[:D] || "")
    }
  end
end
