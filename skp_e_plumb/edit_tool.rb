# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # EditTool
  # ---------------------------------------------------------------------------
  # Re-open a conduit run created by SKP E-Plumb and edit it by anchors. The
  # run stores its centreline, surfaces and settings (Builder.store_run_meta),
  # so this tool reshapes that definition and rebuilds geometry + BOM.
  #
  #   Clic en una tubería .... load it (anchors appear)
  #   Arrastrar un ancla ..... move that vertex (drop it on a box to connect)
  #   Clic en un segmento .... insert an anchor there
  #   Clic en vacío/superficie extend the run from its nearest end
  #   Retroceso / Supr ....... delete the anchor under the cursor
  #   Ctrl / Option .......... anchor type: curve -> elbow -> box
  #   Enter .................. apply          Esc ... leave the run
  #   Clic derecho ........... all of the above + "apply current settings"
  # ===========================================================================
  class EditTool
    HANDLE_PX = 11
    SEGMENT_PX = 8
    KEY_ENTER = 13
    KEY_BACKSPACE = 8

    NODE_ORDER = %w[field premade box].freeze
    NODE_LABEL = { 'field' => 'curva de campo', 'premade' => 'codo prefabricado', 'box' => 'caja' }.freeze

    def activate
      @model = Sketchup.active_model
      reset_all
      @ip = Sketchup::InputPoint.new
      update_ui
      @model.active_view.invalidate
    end

    def deactivate(view)
      offer_apply(view)
      view.invalidate
    end

    def resume(view)
      update_ui
      view.invalidate
    end

    def suspend(view)
      view.invalidate
    end

    def onSetCursor
      UI.set_cursor(Cursors.get('edit'))
    end

    def onCancel(_reason, view)
      if @run
        offer_apply(view)
        reset_all
        update_ui
        view.invalidate
      else
        @model.select_tool(nil)
      end
    end

    def onMouseMove(_flags, x, y, view)
      @ip.pick(view, x, y)
      if @run && @drag
        box = Picker.box_under(view, x, y)
        if box
          @pts[@drag] = Builder.box_surface_point(box)
          bn = Builder.box_world_normal(box)
          @normals[@drag] = bn ? [bn] : []
        else
          pos, normals = Picker.surface_point(view, @ip, x, y)
          @pts[@drag] = pos if pos
          @normals[@drag] = normals
        end
        @box_conns[@drag] = box
        @dirty = true
      elsif @run
        @hover = anchor_at(view, x, y)
      end
      view.tooltip = @ip.tooltip
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      if @run.nil?
        pick_run(view, x, y)
        return
      end

      idx = anchor_at(view, x, y)
      if idx
        @drag = idx
        @hover = idx
      elsif (seg = segment_at(view, x, y))
        insert_vertex(seg[0], seg[1])
      elsif @ip.valid?
        pos, normals = Picker.surface_point(view, @ip, x, y)
        append_vertex(pos, normals) if pos
      end
      view.invalidate
    end

    def onLButtonUp(_flags, _x, _y, view)
      return unless @drag

      @drag = nil
      update_ui
      view.invalidate
    end

    def onKeyDown(key, repeat, _flags, view)
      return false if repeat && repeat > 1
      return false if @run.nil?

      if key == KEY_ENTER
        rebuild(view)
      elsif defined?(COPY_MODIFIER_KEY) && key == COPY_MODIFIER_KEY
        cycle_vertex_type(@hover, view)
      elsif key == KEY_BACKSPACE || (defined?(VK_DELETE) && key == VK_DELETE)
        delete_vertex(@hover, view)
      else
        return false
      end
      true
    end

    def getMenu(menu, _flags = nil, x = nil, y = nil, view = nil)
      view ||= @model.active_view
      unless @run
        menu.add_item('Haz clic en una tubería para editarla') {}
        return true
      end
      idx = x && y ? anchor_at(view, x, y) : @hover
      if idx
        @hover = idx
        sub = menu.add_submenu("Ancla #{idx + 1}")
        NODE_ORDER.each do |m|
          id = sub.add_item(NODE_LABEL[m].capitalize) { set_vertex_type(idx, m, view) }
          sub.set_validation_proc(id) { @modes[idx].to_s == m ? MF_CHECKED : MF_UNCHECKED }
        end
        sub.add_item('Eliminar ancla') { delete_vertex(idx, view) }
      end
      menu.add_item('Aplicar ajustes actuales a esta tubería (tipo, diámetro, montaje…)') do
        apply_current_settings(view)
      end
      menu.add_separator
      menu.add_item('Aplicar cambios (Enter)') { rebuild(view) }
      menu.add_item('Descartar cambios') do
        reset_all
        update_ui
        view.invalidate
      end
      true
    end

    def draw(view)
      if @run.nil?
        @ip.draw(view) if @ip.valid?
        return
      end

      if @pts.length >= 2
        view.drawing_color = Sketchup::Color.new(31, 108, 176)
        view.line_width = 3
        view.line_stipple = ''
        view.draw(GL_LINE_STRIP, @pts)
      end

      @pts.each_with_index do |p, i|
        color = i == @hover || i == @drag ? Sketchup::Color.new(240, 130, 0) : mode_color(@modes[i])
        view.draw_points([p], 12, 2, color)
      end
      @ip.draw(view) if @ip.valid? && @drag
    end

    def getExtents
      bb = Geom::BoundingBox.new
      @pts.each { |p| bb.add(p) }
      bb.add(@run.bounds) if @run&.valid?
      bb.add(@ip.position) if @ip.valid?
      bb
    end

    # ---- internals --------------------------------------------------------

    private

    def reset_all
      @run = nil
      @pts = []
      @modes = []
      @normals = []
      @box_conns = []
      @s = nil
      @drag = nil
      @hover = nil
      @dirty = false
      @flash = nil
    end

    def offer_apply(view)
      return unless @run && @dirty

      res = UI.messagebox('Hay cambios sin aplicar en la tubería. ¿Aplicarlos?', MB_YESNO)
      rebuild(view) if res == IDYES
    rescue StandardError
      nil
    end

    def mode_color(mode)
      case mode.to_s
      when 'premade' then Sketchup::Color.new(47, 133, 90)
      when 'box'     then Sketchup::Color.new(240, 130, 0)
      else Sketchup::Color.new(60, 90, 200)
      end
    end

    def anchor_at(view, x, y)
      best = nil
      bestd = HANDLE_PX
      @pts.each_with_index do |p, i|
        sp = view.screen_coords(p)
        d = Math.hypot(sp.x - x, sp.y - y)
        if d < bestd
          bestd = d
          best = i
        end
      end
      best
    end

    # [segment_index, point3d_on_segment] if (x, y) is near a segment.
    def segment_at(view, x, y)
      return nil if @pts.length < 2

      best = nil
      bestd = SEGMENT_PX
      (0...@pts.length - 1).each do |i|
        a = view.screen_coords(@pts[i])
        b = view.screen_coords(@pts[i + 1])
        d, t = point_seg_dist_2d(x, y, a.x, a.y, b.x, b.y)
        next if t <= 0.02 || t >= 0.98

        next unless d < bestd

        bestd = d
        va = @pts[i]
        vb = @pts[i + 1]
        best = [i, Geom::Point3d.new(va.x + (vb.x - va.x) * t, va.y + (vb.y - va.y) * t,
                                     va.z + (vb.z - va.z) * t)]
      end
      best
    end

    def point_seg_dist_2d(px, py, ax, ay, bx, by)
      dx = bx - ax
      dy = by - ay
      len2 = dx * dx + dy * dy
      return [Math.hypot(px - ax, py - ay), 0.0] if len2 <= 1.0e-9

      t = ((px - ax) * dx + (py - ay) * dy) / len2
      t = t.clamp(0.0, 1.0)
      [Math.hypot(px - (ax + dx * t), py - (ay + dy * t)), t]
    end

    def pick_run(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      container = nil
      (0...ph.count).each do |i|
        path = ph.path_at(i)
        next unless path

        container = path.reverse.find do |e|
          (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && Builder.run?(e)
        end
        break if container
      end

      if container
        load_run(container, view)
      else
        @flash = 'Haz clic sobre una tubería creada con SKP E-Plumb.'
        update_ui
      end
    end

    def load_run(container, view)
      meta = Builder.read_run_meta(container)
      unless meta
        UI.messagebox('No pude leer los datos de esta tubería.')
        return
      end

      @run = container
      @pts = meta[:pts].map(&:clone)
      default = (meta[:s][:bend_mode] || 'field').to_s
      @modes = meta[:modes].map(&:to_s)
      @modes << default while @modes.length < @pts.length
      @normals = meta[:normals].map(&:dup)
      @normals << [] while @normals.length < @pts.length
      @box_conns = meta[:box_conns].dup
      @box_conns << nil while @box_conns.length < @pts.length
      @s = meta[:s]
      @drag = nil
      @hover = nil
      @dirty = false
      @flash = 'Tubería cargada.'
      @model.selection.clear
      update_ui
      view.invalidate
    end

    def append_vertex(pos, normals)
      mode = (@s[:bend_mode] || 'field').to_s
      if @pts.first.distance(pos) < @pts.last.distance(pos)
        @pts.unshift(pos.clone)
        @modes.unshift(mode)
        @normals.unshift(normals)
        @box_conns.unshift(nil)
      else
        @pts.push(pos.clone)
        @modes.push(mode)
        @normals.push(normals)
        @box_conns.push(nil)
      end
      mark('Ancla añadida (extender).')
    end

    # A vertex inserted on a segment lies on that segment's surface.
    def insert_vertex(index, point3d)
      dir = GeomUtil.to_a3(@pts[index + 1] - @pts[index])
      n = GeomUtil.segment_normal(@normals[index], @normals[index + 1], dir)
      @pts.insert(index + 1, point3d)
      @modes.insert(index + 1, (@s[:bend_mode] || 'field').to_s)
      @normals.insert(index + 1, n ? [n] : [])
      @box_conns.insert(index + 1, nil)
      mark('Ancla insertada.')
    end

    def delete_vertex(idx, view)
      return if idx.nil? || idx >= @pts.length

      if @pts.length <= 2
        @flash = 'Una tubería necesita al menos dos puntos.'
        update_ui
        return
      end
      [@pts, @modes, @normals, @box_conns].each { |a| a.delete_at(idx) }
      @hover = nil
      @drag = nil
      mark('Ancla eliminada.')
      view.invalidate
    end

    def cycle_vertex_type(idx, view)
      return if idx.nil?

      cur = NODE_ORDER.include?(@modes[idx].to_s) ? @modes[idx].to_s : 'field'
      set_vertex_type(idx, NODE_ORDER[(NODE_ORDER.index(cur) + 1) % NODE_ORDER.length], view)
    end

    def set_vertex_type(idx, mode, view)
      @modes[idx] = mode
      @s[:box_key] = Settings.box_key if mode == 'box' && @s[:box_key].to_s.empty?
      mark("Ancla #{idx + 1}: #{NODE_LABEL[mode]}")
      view.invalidate
    end

    def apply_current_settings(view)
      Settings.load!
      keep = { bend_mode: @s[:bend_mode] }
      @s = Settings.run_options.merge(keep)
      mark("Ajustes aplicados: #{Catalog.size_label(@s[:type], @s[:size])}. Enter para reconstruir.")
      view.invalidate
    end

    def mark(msg)
      @dirty = true
      @flash = msg
      update_ui
    end

    def rebuild(view)
      return if @run.nil? || @pts.length < 2

      s = @s.dup
      no_term = s[:termination].to_s == 'none'
      s[:terminate_start] = !no_term
      s[:terminate_end] = !no_term

      @model.start_operation('SKP E-Plumb — Editar tubería', true)
      begin
        @run.erase! if @run.valid?
        newrun = Builder.build_run(@model, @pts, @modes, s, @normals, @box_conns)
      rescue StandardError => e
        @model.abort_operation
        UIDialogs.report_error(e, 'editar tubería')
        return
      end
      if newrun
        @model.commit_operation
        @run = newrun
        @dirty = false
        issues = Bom.review_meta(Bom.read(newrun, Bom::RUN_DICT))
        @flash = issues.empty? ? 'Tubería actualizada ✓' : "Tubería actualizada · ⚠ #{issues.first[:msg]}"
      else
        @model.abort_operation
        @flash = 'No se pudo reconstruir la tubería.'
      end
      update_ui
      view.invalidate
    end

    def update_ui
      if @run.nil?
        msg = 'SKP E-Plumb · Editar: haz clic en una tubería.'
        msg = "#{@flash}  |  #{msg}" if @flash
        Sketchup.set_status_text(msg)
        return
      end

      hint = 'Arrastrar ancla = mover · Clic en segmento = insertar · Clic fuera = extender · ' \
             'Retroceso = borrar · Ctrl/Option = tipo de ancla · Enter = aplicar · Clic derecho = opciones'
      msg = "Editando #{Catalog.size_label(@s[:type], @s[:size])}#{@dirty ? ' (sin aplicar)' : ''} · #{hint}"
      msg = "#{@flash}  |  #{msg}" if @flash
      Sketchup.set_status_text(msg)
    end
  end
end
