# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # ConduitTool
  # ---------------------------------------------------------------------------
  # Draw a conduit run by clicking points ON walls, floors and ceilings (the
  # tube is automatically laid on the surface — or inside it when embedded).
  #
  #   Clic ................ add a point (a plugin box = connect to it)
  #   Doble clic / Enter .. build the run
  #   Retroceso ........... undo the last point        Esc ... cancel
  #   Ctrl (Win) / Option (Mac) .. next corner: field bend <-> factory elbow
  #   Flechas → ← ↑ ........ lock to red / green / blue axis (↓ unlocks)
  #   Shift ............... lock the current inference
  #   Type a length ....... place the next point at that distance
  #   Right click ......... menu with all of the above
  #
  # The preview shows where the tube will really go; segments that would
  # pass through an object are drawn in RED.
  # ===========================================================================
  class ConduitTool
    KEY_ENTER = 13
    KEY_BACKSPACE = 8
    BLUE  = [31, 108, 176].freeze
    RED   = [214, 45, 32].freeze
    ORANGE = [240, 130, 0].freeze
    AXES = { right: [1, 0, 0], left: [0, 1, 0], up: [0, 0, 1] }.freeze
    AXIS_COLOR = { right: [220, 40, 40], left: [40, 170, 40], up: [40, 80, 230] }.freeze

    def activate
      @ip = Sketchup::InputPoint.new
      @ip_prev = Sketchup::InputPoint.new
      @flash = nil
      @lock = nil
      reset_run
      Settings.load!
      update_ui
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.lock_inference if view.respond_to?(:lock_inference)
      view.invalidate
    end

    def resume(view)
      Settings.load!
      update_ui
      view.invalidate
    end

    def suspend(view)
      view.invalidate
    end

    def onSetCursor
      UI.set_cursor(Cursors.get('conduit'))
    end

    def onCancel(_reason, view)
      if @pts.any?
        reset_run
        @flash = 'Trazado cancelado.'
        update_ui
        view.invalidate
      else
        Sketchup.active_model.select_tool(nil)
      end
    end

    def onMouseMove(_flags, x, y, view)
      track(view, x, y)
      view.tooltip = @snap_box ? 'Conectar a esta caja' : @ip.tooltip
      update_length_vcb
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      track(view, x, y)
      return unless @cur

      add_point(@cur, @cur_normals, @snap_box, view)
    end

    def onLButtonDoubleClick(_flags, _x, _y, view)
      finish_run(view)
    end

    def onKeyDown(key, repeat, _flags, view)
      return false if repeat && repeat > 1

      if key == KEY_ENTER
        finish_run(view)
      elsif key == KEY_BACKSPACE
        undo_point(view)
      elsif defined?(COPY_MODIFIER_KEY) && key == COPY_MODIFIER_KEY
        toggle_mode(view)
      elsif defined?(CONSTRAIN_MODIFIER_KEY) && key == CONSTRAIN_MODIFIER_KEY
        view.lock_inference(@ip, @ip_prev) if @ip.valid? && @ip_prev.valid?
        view.lock_inference(@ip) if @ip.valid? && !@ip_prev.valid?
        return false
      elsif (axis = arrow_axis(key))
        @lock = axis == :down || @lock == axis ? nil : axis
        @flash = @lock ? "Bloqueado al eje #{axis_name(@lock)}" : 'Eje desbloqueado'
        update_ui
        view.invalidate
      else
        return false
      end
      true
    end

    def onKeyUp(key, _repeat, _flags, view)
      return false unless defined?(CONSTRAIN_MODIFIER_KEY) && key == CONSTRAIN_MODIFIER_KEY

      view.lock_inference
      false
    end

    def onUserText(text, view)
      return unless @pts.any? && @cur

      begin
        dist = text.to_l
      rescue ArgumentError, StandardError
        Sketchup.set_status_text('Longitud no válida', SB_VCB_VALUE)
        return
      end
      dir = @cur - @pts.last
      return if dir.length.zero? || dist <= 0

      pt = @pts.last.offset(dir.normalize, dist)
      # The typed point stays on the same surface as the last point.
      normals = (@normals.last || []).select { |n| GeomUtil.dot3(n, GeomUtil.to_a3(dir.normalize)).abs < 0.05 }
      add_point(pt, normals, nil, view)
    end

    def getMenu(menu, _flags = nil, _x = nil, _y = nil, _view = nil)
      view = Sketchup.active_model.active_view
      if @pts.length >= 2
        menu.add_item('Terminar tubería (Enter)') { finish_run(view) }
      end
      menu.add_item('Deshacer último punto (Retroceso)') { undo_point(view) } if @pts.any?
      if @pts.length >= 2
        menu.add_item('Poner caja de paso en el último punto') do
          @modes[-1] = 'box'
          @flash = 'Caja en el último punto.'
          update_ui
          view.invalidate
        end
      end
      menu.add_separator
      label = Settings.field_bend? ? 'Siguiente curva: usar CODO prefabricado' : 'Siguiente curva: DOBLAR tubo'
      menu.add_item("#{label} (Ctrl/Option)") { toggle_mode(view) }
      sub = menu.add_submenu('Bloquear eje')
      sub.add_item('Rojo (→)') { set_lock(:right, view) }
      sub.add_item('Verde (←)') { set_lock(:left, view) }
      sub.add_item('Azul (↑)') { set_lock(:up, view) }
      sub.add_item('Sin bloqueo (↓)') { set_lock(nil, view) }
      menu.add_separator
      menu.add_item('Ajustes…') { UIDialogs.show_settings }
      menu.add_item('Cancelar trazado (Esc)') { onCancel(0, view) } if @pts.any?
      true
    end

    def draw(view)
      path = preview_path
      if path.length >= 2
        committed = @pts.length
        (0...path.length - 1).each do |k|
          bad = @hits[k]
          rubber = k >= committed - 1
          view.drawing_color = color(bad ? RED : (rubber ? lock_color : BLUE))
          view.line_width = rubber ? 2 : 4
          view.line_stipple = rubber ? '_' : ''
          view.draw(GL_LINES, [path[k], path[k + 1]])
        end
        view.line_stipple = ''
      end

      unless @pts.empty?
        @pts.each_with_index do |p, i|
          view.draw_points([p], 9, 2, mode_color(@modes[i]))
        end
      end

      if @snap_box&.valid?
        draw_box_outline(view, @snap_box)
        view.draw_points([@cur], 14, 1, color(ORANGE)) if @cur
      elsif @ip.valid?
        @ip.draw(view)
      end
      draw_hud(view)
    end

    def getExtents
      bb = Geom::BoundingBox.new
      @pts.each { |p| bb.add(p) }
      bb.add(@cur) if @cur
      bb.add(@snap_box.bounds) if @snap_box&.valid?
      bb
    end

    def enableVCB?
      true
    end

    # ---- internals --------------------------------------------------------

    private

    def reset_run
      @pts = []
      @modes = []
      @normals = []
      @box_conns = []
      @snap_box = nil
      @cur = nil
      @cur_normals = []
      @hits = []
      @committed_hits = []
      @ip_prev = Sketchup::InputPoint.new
    end

    # Resolve the cursor into a candidate point + surface normals.
    def track(view, x, y)
      if @pts.empty? then @ip.pick(view, x, y)
      else @ip.pick(view, x, y, @ip_prev)
      end
      @snap_box = Picker.box_under(view, x, y)
      if @snap_box
        @cur = Builder.box_surface_point(@snap_box)
        bn = Builder.box_world_normal(@snap_box)
        @cur_normals = bn ? [bn] : []
      elsif @lock && @pts.any?
        axis = Geom::Vector3d.new(*AXES[@lock])
        ray = view.pickray(x, y)
        pts = Geom.closest_points([@pts.last, axis], ray)
        @cur = pts[0]
        @cur_normals = (@normals.last || []).select { |n| GeomUtil.dot3(n, AXES[@lock]).abs < 0.05 }
      elsif @ip.valid?
        @cur, @cur_normals = Picker.surface_point(view, @ip, x, y)
      else
        @cur = nil
        @cur_normals = []
      end
      refresh_hits(view)
    end

    def add_point(pt, normals, box, view)
      @pts << pt.clone
      @modes << Settings.bend_mode.to_s
      @normals << (normals || [])
      @box_conns << box
      @ip_prev = Sketchup::InputPoint.new(pt)
      @flash = nil
      refresh_hits(view, commit: true)
      update_ui
      view.invalidate
    end

    def undo_point(view)
      return if @pts.empty?

      @pts.pop
      @modes.pop
      @normals.pop
      @box_conns.pop
      @ip_prev = @pts.empty? ? Sketchup::InputPoint.new : Sketchup::InputPoint.new(@pts.last)
      refresh_hits(view, commit: true)
      update_ui
      view.invalidate
    end

    def toggle_mode(view)
      mode = Settings.toggle_bend_mode!
      @flash = mode == :field ? 'Próxima curva: DOBLAR TUBO' : 'Próxima curva: CODO PREFABRICADO'
      UIDialogs.refresh_settings
      update_ui
      view.invalidate
    end

    def set_lock(axis, view)
      @lock = axis
      update_ui
      view.invalidate
    end

    def arrow_axis(key)
      return :right if defined?(VK_RIGHT) && key == VK_RIGHT
      return :left if defined?(VK_LEFT) && key == VK_LEFT
      return :up if defined?(VK_UP) && key == VK_UP
      return :down if defined?(VK_DOWN) && key == VK_DOWN

      nil
    end

    def axis_name(axis)
      { right: 'rojo', left: 'verde', up: 'azul' }[axis]
    end

    def lock_color
      @lock ? AXIS_COLOR[@lock] : [120, 120, 120]
    end

    def color(rgb)
      Sketchup::Color.new(*rgb)
    end

    def mode_color(mode)
      case mode.to_s
      when 'premade' then color([47, 133, 90])
      when 'box'     then color(ORANGE)
      else color([60, 90, 200])
      end
    end

    # Where the tube will actually run (surface offset applied), including
    # the rubber-band segment to the cursor.
    def preview_path
      pts = @pts.dup
      normals = @normals.dup
      if @cur
        pts << @cur
        normals << @cur_normals
      end
      return pts if pts.length < 2

      off = preview_offset
      seg_n = (0...pts.length - 1).map do |k|
        GeomUtil.segment_normal(normals[k], normals[k + 1], GeomUtil.to_a3(pts[k + 1] - pts[k]))
      end
      Builder.offset_path(pts, seg_n, off)
    rescue StandardError
      pts
    end

    def preview_offset
      r = GeomUtil.mm(Catalog.od_mm(Settings.type, Settings.size) / 2.0)
      if Settings.surface?
        r * Builder::COUPLING_SCALE + GeomUtil.mm(Settings.get('standoff_mm').to_f)
      else
        -(r + GeomUtil.mm(Settings.get('cover_mm').to_f))
      end
    end

    # Ray-test each preview segment (surface install only): a hit before the
    # segment's end means the tube would go through something.
    def refresh_hits(view, commit: false)
      path = preview_path
      unless Settings.surface?
        @hits = []
        return
      end
      if commit
        @committed_hits = (0...[path.length - 1, 0].max).map { |k| segment_blocked?(view.model, path[k], path[k + 1]) }
        @hits = @committed_hits.dup
        return
      end
      @hits = @committed_hits.first([@pts.length - 1, 0].max)
      k = path.length - 2
      return if k.negative?

      # The last committed segment may change shape when the next corner is
      # previewed, so re-test it together with the rubber band.
      @hits[k - 1] = segment_blocked?(view.model, path[k - 1], path[k]) if k >= 1
      @hits[k] = segment_blocked?(view.model, path[k], path[k + 1])
    end

    def segment_blocked?(model, p, q)
      v = q - p
      len = v.length
      return false if len < GeomUtil.mm(5)

      dir = v.normalize
      origin = p.offset(dir, GeomUtil.mm(2))
      4.times do
        hit = model.raytest([origin, dir], true)
        return false unless hit

        pt, path = hit
        return false if p.distance(pt) >= len - GeomUtil.mm(2)
        return true unless Picker.plugin_path?(path) # the tube's own boxes/fittings don't count

        origin = pt.offset(dir, GeomUtil.mm(1))
      end
      false
    rescue StandardError
      false
    end

    def draw_box_outline(view, box)
      bb = box.bounds
      pts = (0..7).map { |i| bb.corner(i) }
      edges = [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
      view.drawing_color = color(ORANGE)
      view.line_width = 3
      view.draw(GL_LINES, edges.flat_map { |a, b| [pts[a], pts[b]] })
    end

    def draw_hud(view)
      return unless @cur

      text = if @snap_box then 'Conectar a caja'
             elsif @pts.any?
               d = GeomUtil.to_mm(@pts.last.distance(@cur)) / 1000.0
               s = format('%.2f m', d)
               s += " · #{angle_text}" if angle_text
               s += ' · ⚠ atraviesa un objeto' if @hits.last
               s
             else
               "Inicio · #{Picker.surface_name(@cur_normals.first)}"
             end
      sp = view.screen_coords(@cur)
      view.draw_text(Geom::Point3d.new(sp.x + 18, sp.y + 14, 0), text)
    rescue StandardError
      nil
    end

    def angle_text
      return nil if @pts.length < 2 || @cur.nil?

      a = @pts[-1] - @pts[-2]
      b = @cur - @pts[-1]
      return nil if a.length.zero? || b.length.zero?

      deg = a.angle_between(b) * 180.0 / Math::PI
      return nil if deg < 1.0

      kind = Settings.field_bend? ? 'curva' : 'codo'
      "#{kind} #{deg.round}°"
    end

    def finish_run(view)
      if @pts.length < 2
        @flash = 'Marca al menos dos puntos para crear la tubería.'
        update_ui
        return
      end

      model = Sketchup.active_model
      model.start_operation('SKP E-Plumb — Tubería', true)
      begin
        group = Builder.build_run(model, @pts, @modes, Settings.run_options, @normals, @box_conns)
      rescue StandardError => e
        model.abort_operation
        UIDialogs.report_error(e, 'crear tubería')
        return
      end
      if group
        model.commit_operation
        issues = Bom.review_meta(Bom.read(group, Bom::RUN_DICT))
        @flash = if issues.empty?
                   'Tubería creada ✓'
                 else
                   "Tubería creada · ⚠ #{issues.first[:msg]}"
                 end
      else
        model.abort_operation
        @flash = 'No se pudo crear la tubería.'
      end

      reset_run
      update_ui
      view.invalidate
    end

    def update_length_vcb
      return unless @pts.any? && @cur

      Sketchup.set_status_text(@pts.last.distance(@cur).to_l.to_s, SB_VCB_VALUE)
    end

    def update_ui
      mode = Settings.field_bend? ? 'DOBLAR' : 'CODO'
      install = Settings.surface? ? 'a la vista' : 'empotrada'
      lock = @lock ? " · eje #{axis_name(@lock)}" : ''
      base = "#{Catalog.size_label(Settings.type, Settings.size)} #{install} · curva: #{mode} " \
             "(Ctrl/Option)#{lock} · Clic = punto · Doble clic/Enter = crear · Flechas = bloquear eje · " \
             'Clic derecho = opciones'
      base = "#{@flash}  |  #{base}" if @flash
      Sketchup.set_status_text(base)
      Sketchup.set_status_text('Longitud', SB_VCB_LABEL)
    end
  end
end
