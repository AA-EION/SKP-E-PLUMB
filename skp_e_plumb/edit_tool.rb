# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # EditTool
  # ---------------------------------------------------------------------------
  # Re-open a conduit run created by SKP E-Plumb and edit it by anchors. The
  # run stores its centreline + settings (see Builder.store_run_meta), so this
  # tool loads that definition, lets the user reshape it, and rebuilds the
  # geometry and BOM tags in place.
  #
  # Interactions (no letter/modifier keys required, for macOS/Windows parity):
  #   * Click a run ....... load it for editing (anchors appear).
  #   * Drag an anchor .... move that vertex.
  #   * Click a segment ... insert a new anchor there.
  #   * Click empty space . extend the run from its nearest end.
  #   * Backspace/Delete .. remove the anchor under the cursor.
  #   * Alt / Option ...... toggle that vertex between field-bend and elbow.
  #   * Enter ............. apply (rebuild geometry + BOM).
  #   * Esc ............... drop the current selection / exit.
  # ===========================================================================
  class EditTool
    HANDLE_PX = 11      # pixel radius to grab an anchor
    SEGMENT_PX = 8      # pixel distance to hit a segment
    KEY_ENTER = 13
    KEY_BACKSPACE = 8
    WIN_ALT = 18

    def activate
      @model = Sketchup.active_model
      reset_all
      @ip = Sketchup::InputPoint.new
      update_ui
      @model.active_view.invalidate
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

    def onSetCursor
      UI.set_cursor(Cursors.get('edit'))
    end

    def onCancel(_reason, view)
      if @run
        reset_all
        update_ui
        view.invalidate
      else
        @model.select_tool(nil)
      end
    end

    def onMouseMove(_flags, x, y, view)
      if @run.nil?
        @ip.pick(view, x, y)
        view.invalidate
        return
      end

      if @drag
        @ip.pick(view, x, y)
        @pts[@drag] = @ip.position
        @dirty = true
      else
        @ip.pick(view, x, y)
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
      else
        seg = segment_at(view, x, y)
        if seg
          insert_vertex(seg[0], seg[1])
        else
          append_vertex(@ip.position)
        end
      end
      view.invalidate
    end

    def onLButtonUp(_flags, _x, _y, view)
      return unless @drag

      @drag = nil
      view.invalidate
    end

    def onKeyDown(key, repeat, _flags, view)
      return false if repeat && repeat > 1
      return false if @run.nil?

      if key == KEY_ENTER
        rebuild(view)
        true
      elsif alt_key?(key)
        toggle_vertex_mode(view)
        true
      elsif delete_key?(key)
        delete_vertex(view)
        true
      else
        false
      end
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
        color = if i == @hover || i == @drag
                  Sketchup::Color.new(240, 130, 0)
                else
                  mode_color(@modes[i])
                end
        view.draw_points([p], 12, 2, color)
      end

      @ip.draw(view) if @ip.valid?
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
      @s = nil
      @drag = nil
      @hover = nil
      @dirty = false
      @flash = nil
    end

    def alt_key?(key)
      return true if key == WIN_ALT
      return true if defined?(COPY_MODIFIER_KEY) && key == COPY_MODIFIER_KEY

      false
    end

    def delete_key?(key)
      return true if key == KEY_BACKSPACE
      return true if defined?(VK_DELETE) && key == VK_DELETE

      false
    end

    def mode_color(mode)
      mode.to_s == 'premade' ? Sketchup::Color.new(47, 133, 90) : Sketchup::Color.new(60, 90, 200)
    end

    # Index of the anchor within HANDLE_PX pixels of (x, y), or nil.
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

    # Returns [segment_index, point3d_on_segment] if (x, y) is near a segment
    # (but not near a vertex), else nil.
    def segment_at(view, x, y)
      return nil if @pts.length < 2

      best = nil
      bestd = SEGMENT_PX
      (0...@pts.length - 1).each do |i|
        a = view.screen_coords(@pts[i])
        b = view.screen_coords(@pts[i + 1])
        d, t = point_seg_dist_2d(x, y, a.x, a.y, b.x, b.y)
        next if t <= 0.02 || t >= 0.98 # too close to a vertex

        if d < bestd
          bestd = d
          # interpolate the real 3D point by the same parameter
          va = @pts[i]
          vb = @pts[i + 1]
          p3d = Geom::Point3d.new(va.x + (vb.x - va.x) * t,
                                  va.y + (vb.y - va.y) * t,
                                  va.z + (vb.z - va.z) * t)
          best = [i, p3d]
        end
      end
      best
    end

    # 2D distance from (px,py) to segment (ax,ay)-(bx,by); returns [dist, t].
    def point_seg_dist_2d(px, py, ax, ay, bx, by)
      dx = bx - ax
      dy = by - ay
      len2 = dx * dx + dy * dy
      return [Math.hypot(px - ax, py - ay), 0.0] if len2 <= 1.0e-9

      t = ((px - ax) * dx + (py - ay) * dy) / len2
      t = 0.0 if t < 0.0
      t = 1.0 if t > 1.0
      cx = ax + dx * t
      cy = ay + dy * t
      [Math.hypot(px - cx, py - cy), t]
    end

    def pick_run(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      container = nil
      (0...ph.count).each do |i|
        path = ph.path_at(i)
        next unless path

        found = path.reverse.find do |e|
          (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && Builder.run?(e)
        end
        if found
          container = found
          break
        end
      end

      if container
        load_run(container, view)
      else
        UI.messagebox('Haz clic sobre una tubería creada con SKP E-Plumb para editarla.')
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
      @modes = meta[:modes].map(&:to_s)
      default = (meta[:s][:bend_mode] || 'field').to_s
      @modes << default while @modes.length < @pts.length
      @normals = (meta[:normals] || []).dup
      @normals << nil while @normals.length < @pts.length
      @s = meta[:s]
      @drag = nil
      @hover = nil
      @dirty = false
      @flash = 'Tubería cargada para edición.'
      update_ui
      view.invalidate
    end

    def append_vertex(pos)
      mode = (@s[:bend_mode] || 'field').to_s
      if @pts.first.distance(pos) < @pts.last.distance(pos)
        @pts.unshift(pos.clone)
        @modes.unshift(mode)
        @normals.unshift(nil)
      else
        @pts.push(pos.clone)
        @modes.push(mode)
        @normals.push(nil)
      end
      @dirty = true
      @flash = 'Vértice añadido (extender).'
      update_ui
    end

    def insert_vertex(index, point3d)
      @pts.insert(index + 1, point3d)
      @modes.insert(index + 1, (@s[:bend_mode] || 'field').to_s)
      @normals.insert(index + 1, nil)
      @dirty = true
      @flash = 'Vértice insertado.'
      update_ui
    end

    def delete_vertex(view)
      idx = @hover
      return if idx.nil?
      if @pts.length <= 2
        UI.messagebox('Una tubería necesita al menos dos puntos.')
        return
      end

      @pts.delete_at(idx)
      @modes.delete_at(idx)
      @normals.delete_at(idx)
      @hover = nil
      @drag = nil
      @dirty = true
      @flash = 'Vértice eliminado.'
      update_ui
      view.invalidate
    end

    def toggle_vertex_mode(view)
      idx = @hover
      return if idx.nil?

      @modes[idx] = @modes[idx].to_s == 'field' ? 'premade' : 'field'
      @dirty = true
      @flash = "Vértice #{idx + 1}: #{@modes[idx] == 'field' ? 'DOBLAR TUBO' : 'CODO'}"
      update_ui
      view.invalidate
    end

    def rebuild(view)
      return if @run.nil? || @pts.length < 2

      s = @s.dup
      no_term = s[:termination].to_s == 'none'
      s[:terminate_start] = !no_term
      s[:terminate_end] = !no_term

      @model.start_operation('SKP E-Plumb — Editar tubería', true)
      @run.erase! if @run.valid?
      newrun = Builder.build_run(@model, @pts, @modes, s, @normals)
      if newrun
        @model.commit_operation
        @run = newrun
        @dirty = false
        @flash = 'Tubería actualizada. BOM recalculado.'
      else
        @model.abort_operation
        @flash = 'No se pudo reconstruir la tubería.'
      end
      update_ui
      view.invalidate
    end

    def update_ui
      if @run.nil?
        Sketchup.set_status_text('SKP E-Plumb · Editar: haz clic en una tubería para editarla.')
        return
      end

      hint = 'arrastra anclas=mover · clic en segmento=insertar · clic en vacío=extender · ' \
             'Retroceso=borrar · Alt=codo/curva · Enter=aplicar'
      msg = "Editar #{@s[:type]} #{@s[:size]}\" · #{hint}"
      msg = "#{@flash}  |  #{msg}" if @flash
      Sketchup.set_status_text(msg)
    end
  end
end
