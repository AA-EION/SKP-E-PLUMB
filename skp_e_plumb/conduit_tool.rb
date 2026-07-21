# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # ConduitTool
  # ---------------------------------------------------------------------------
  # Interactive tool to draw a conduit run. Click to add centreline vertices,
  # double-click or Enter to build. Alt / Option (or Ctrl on Windows) toggles
  # between FIELD-BEND mode (the pipe is bent, no fitting) and PREMADE-ELBOW
  # mode (a factory elbow is inserted and counted separately). The mode active
  # when you click a corner is the mode used for that corner, so you can mix
  # bends and elbows in a single run. You can also type a length in the
  # measurement box to place the next vertex at an exact distance.
  # ===========================================================================
  class ConduitTool
    # Windows Alt (VK_MENU) key code; Mac Option maps to COPY_MODIFIER_KEY.
    WIN_ALT = 18
    KEY_ENTER = 13
    KEY_BACKSPACE = 8

    def activate
      @pts = []
      @modes = []
      @ip = Sketchup::InputPoint.new
      @ip_prev = Sketchup::InputPoint.new
      @flash = nil
      Settings.load!
      update_ui
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_ui
      view.invalidate
    end

    def suspend(view)
      view.invalidate
    end

    def onCancel(_reason, view)
      if @pts.any?
        reset_run
        update_ui
        view.invalidate
      else
        Sketchup.active_model.select_tool(nil)
      end
    end

    def onMouseMove(_flags, x, y, view)
      if @pts.empty?
        @ip.pick(view, x, y)
      else
        @ip.pick(view, x, y, @ip_prev)
      end
      view.tooltip = @ip.tooltip
      update_length_vcb
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      if @pts.empty?
        @ip.pick(view, x, y)
      else
        @ip.pick(view, x, y, @ip_prev)
      end
      add_point(@ip.position.clone, view)
    end

    def onLButtonDoubleClick(_flags, _x, _y, view)
      finish_run(view)
    end

    def onKeyDown(key, repeat, _flags, view)
      return false if repeat && repeat > 1

      if alt_key?(key)
        mode = Settings.toggle_bend_mode!
        @flash = mode == :field ? 'Modo: DOBLAR TUBO (curva de campo)' \
                                : 'Modo: CODO PREFABRICADO'
        update_ui
        view.invalidate
        return true
      elsif key == KEY_ENTER
        finish_run(view)
        return true
      elsif key == KEY_BACKSPACE
        undo_point(view)
        return true
      end
      false
    end

    def onUserText(text, view)
      return unless @pts.any? && @ip.valid?

      begin
        dist = text.to_l
      rescue ArgumentError, StandardError
        Sketchup.set_status_text('Longitud no válida', SB_VCB_VALUE)
        return
      end

      dir = @ip.position - @pts.last
      return if dir.length.zero?

      dir.normalize!
      add_point(@pts.last.offset(dir, dist), view)
    end

    def draw(view)
      return if @pts.empty?

      if @pts.length >= 2
        view.drawing_color = Sketchup::Color.new(31, 108, 176)
        view.line_width = 3
        view.line_stipple = ''
        view.draw(GL_LINE_STRIP, @pts)
      end

      if @ip.valid? && !@pts.empty?
        view.drawing_color = Sketchup::Color.new(120, 120, 120)
        view.line_width = 2
        view.line_stipple = '_'
        view.draw(GL_LINES, [@pts.last, @ip.position])
        view.line_stipple = ''
      end

      draw_vertices(view)
      @ip.draw(view) if @ip.valid?
    end

    def getExtents
      bb = Geom::BoundingBox.new
      @pts.each { |p| bb.add(p) }
      bb.add(@ip.position) if @ip.valid?
      bb
    end

    def enableVCB?
      true
    end

    # ---- internals --------------------------------------------------------

    private

    def alt_key?(key)
      return true if key == WIN_ALT
      return true if defined?(COPY_MODIFIER_KEY) && key == COPY_MODIFIER_KEY

      false
    end

    def add_point(pt, view)
      @pts << pt
      @modes << Settings.bend_mode
      @ip_prev = Sketchup::InputPoint.new(pt)
      update_ui
      view.invalidate
    end

    def undo_point(view)
      return if @pts.empty?

      @pts.pop
      @modes.pop
      @ip_prev = @pts.empty? ? Sketchup::InputPoint.new : Sketchup::InputPoint.new(@pts.last)
      update_ui
      view.invalidate
    end

    def reset_run
      @pts = []
      @modes = []
      @ip_prev = Sketchup::InputPoint.new
    end

    def draw_vertices(view)
      return if @pts.empty?

      view.draw_points(@pts, 8, 4, Sketchup::Color.new(31, 108, 176))
    end

    def finish_run(view)
      if @pts.length < 2
        UI.messagebox('Marca al menos dos puntos para crear la tubería.')
        return
      end

      model = Sketchup.active_model
      n = @pts.length
      s = {
        type: Settings.type, size: Settings.size, stock_m: Settings.stock_m,
        bend_radius_mm: Settings.bend_radius_mm, termination: Settings.get('termination'),
        connection: Settings.connection, segments: Settings.segments,
        bend_mode: Settings.bend_mode,
        terminate_start: Settings.termination != :none,
        terminate_end: Settings.termination != :none
      }
      interior_modes = n > 2 ? @modes[1..(n - 2)] : []

      model.start_operation('SKP E-Plumb — Tubería', true)
      group = Builder.build_run(model, @pts, interior_modes, s)
      if group
        model.commit_operation
        @flash = 'Tubería creada. BOM actualizado.'
      else
        model.abort_operation
        @flash = 'No se pudo crear la tubería.'
      end

      reset_run
      update_ui
      view.invalidate
    end

    def update_length_vcb
      return unless @pts.any? && @ip.valid?

      dist = @pts.last.distance(@ip.position)
      Sketchup.set_status_text(dist.to_l.to_s, SB_VCB_VALUE)
    end

    def update_ui
      mode = Settings.field_bend? ? 'DOBLAR TUBO' : 'CODO PREFABRICADO'
      base = "SKP E-Plumb · #{Catalog.size_label(Settings.type, Settings.size)} · " \
             "curva: #{mode} (Alt/Option cambia) · clic=punto, doble clic/Enter=crear"
      base = "#{@flash}  |  #{base}" if @flash
      Sketchup.set_status_text(base)
      Sketchup.set_status_text('Longitud', SB_VCB_LABEL)
    end
  end
end
