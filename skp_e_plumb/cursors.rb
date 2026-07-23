# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Cursors
  # ---------------------------------------------------------------------------
  # Custom mouse cursors so it is obvious which SKP E-Plumb tool is active
  # (drawing conduit, placing a box, or editing). Built once from the toolbar
  # icons and cached. Falls back to the default arrow if creation fails.
  # ===========================================================================
  module Cursors
    ICON_DIR = File.join(__dir__, 'resources', 'icons').freeze

    @cache = {}

    module_function

    # Returns a SketchUp cursor id for the named tool ('conduit'|'box'|'edit'),
    # or 0 (default arrow) if it can't be created.
    def get(name)
      return @cache[name] if @cache.key?(name)

      path = File.join(ICON_DIR, "#{name}_24.png")
      id = 0
      begin
        id = UI.create_cursor(path, 3, 2) if File.exist?(path)
      rescue StandardError
        id = 0
      end
      @cache[name] = id
    end
  end
end
