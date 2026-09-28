# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # BoxTool
  # ---------------------------------------------------------------------------
  # Place the active box on the surface under the cursor. A live preview shows
  # the box exactly as it will be created: back on the wall/floor/ceiling,
  # cover (highlighted) facing you — or recessed with the cover flush when the
  # installation is "empotrada".
  #
  #   Clic ............................ place the box
  #   Ctrl (Win) / Option (Mac) / Tab . rotate 90° on the surface
  #   Type an angle (e.g. 90) ......... rotate by that angle
  #   Right click ..................... choose another box, rotate, settings
  # ===========================================================================
  class BoxTool
    KEY_TAB = 9
    ORANGE = [240, 130, 0].freeze

    def activate
      @ip = Sketchup::InputPoint.new
      @quarter = 0
      @placement = nil
      Settings.load!
      update_ui
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      Settings.load!
      update_ui
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      @ip.pick(view, x, y)
      @xy = [x, y]
      @placement = compute_placement(view, x, y)
      view.tooltip = @placement ? "#{spec[:label]} · #{@placement[:where]}" : @ip.tooltip
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @ip.pick(view, x, y)
      @placement = compute_placement(view, x, y)
      place_box(view) if @placement
    end

    def onKeyDown(key, repeat, _flags, view)
      return false if repeat && repeat > 1

      if key == KEY_TAB || (defined?(COPY_MODIFIER_KEY) && key == COPY_MODIFIER_KEY)
        rotate(1, view)
        return true
      end
      false
    end

    def onUserText(text, view)
      deg = text.to_s.tr(',', '.').to_f
      @quarter = ((deg / 90.0).round % 4)
      refresh_placement(view)
      update_ui
      view.invalidate
    end

    def enableVCB?
      true
    end

    def getMenu(menu, _flags = nil, _x = nil, _y = nil, _view = nil)
      view = Sketchup.active_model.active_view
      menu.add_item('Girar 90° (Ctrl/Option o Tab)') { rotate(1, view) }
      sub = menu.add_submenu('Caja activa')
      Catalog::BOX_KEYS.each do |k|
        id = sub.add_item(Catalog::BOXES[k][:label]) do
          Settings.set('box_key', k)
          UIDialogs.refresh_settings
          update_ui
          view.invalidate
        end
        sub.set_validation_proc(id) { Settings.box_key == k ? MF_CHECKED : MF_UNCHECKED }
      end
      inst = Settings.surface? ? 'Cambiar a caja empotrada' : 'Cambiar a caja sobrepuesta'
      menu.add_item(inst) do
        Settings.set('install', Settings.surface? ? 'embedded' : 'surface')
        UIDialogs.refresh_settings
        update_ui
        view.invalidate
      end
      menu.add_separator
      menu.add_item('Ajustes…') { UIDialogs.show_settings }
      true
    end

    def draw(view)
      if @placement
        draw_preview(view)
      elsif @ip.valid?
        @ip.draw(view)
      end
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@ip.position) if @ip.valid?
      preview_corners.each { |p| bb.add(p) } if @placement
      bb
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def onSetCursor
      UI.set_cursor(Cursors.get('box'))
    end

    private

    def spec
      Catalog::BOXES[Settings.box_key] || Catalog::BOXES[Catalog::DEFAULT_BOX]
    end

    def rotate(steps, view)
      @quarter = (@quarter + steps) % 4
      refresh_placement(view)
      update_ui
      view.invalidate
    end

    def refresh_placement(view)
      @placement = compute_placement(view, *@xy) if @xy
    end

    # Where and how the box would be placed for the cursor at (x, y).
    def compute_placement(view, x, y)
      return nil unless @ip.valid?

      origin = @ip.position
      normals = Picker.normals_at(view, @ip, x, y)
      normal = normals.first && Geom::Vector3d.new(*normals.first)
      unless normal
        hit = Picker.face_hit(view, x, y)
        if hit
          normal = hit[:normal]
          origin = hit[:point] if hit[:point].distance(origin) > GeomUtil.mm(50)
        end
      end
      normal ||= Geom::Vector3d.new(0, 0, 1)
      # When the point sits on an edge (wall/floor corner) prefer the wall and
      # keep the box off the floor.
      if normals.length > 1
        wall = normals.min_by { |n| n[2].abs }
        normal = Geom::Vector3d.new(*wall)
      end
      mount = Settings.surface? ? 'surface' : 'embedded'
      back = mount == 'embedded' ? origin.offset(normal, -GeomUtil.mm(spec[:d])) : origin
      tr = Builder.box_transform(back, normal, nil, @quarter)
      { origin: origin, back: back, normal: normal, tr: tr, mount: mount,
        where: Picker.surface_name(normal) }
    rescue StandardError
      nil
    end

    def preview_corners
      w = GeomUtil.mm(spec[:w]) / 2.0
      h = GeomUtil.mm(spec[:h]) / 2.0
      d = GeomUtil.mm(spec[:d])
      [[-w, -h, 0], [w, -h, 0], [w, h, 0], [-w, h, 0],
       [-w, -h, d], [w, -h, d], [w, h, d], [-w, h, d]].map do |c|
        Geom::Point3d.new(*c).transform(@placement[:tr])
      end
    end

    def draw_preview(view)
      c = preview_corners
      edges = [[0, 1], [1, 2], [2, 3], [3, 0], [0, 4], [1, 5], [2, 6], [3, 7]]
      view.line_stipple = ''
      view.line_width = 2
      view.drawing_color = Sketchup::Color.new(90, 90, 90)
      view.draw(GL_LINES, edges.flat_map { |a, b| [c[a], c[b]] })
      # Cover (front) highlighted so the orientation is obvious.
      view.drawing_color = Sketchup::Color.new(*ORANGE)
      view.line_width = 3
      view.draw(GL_LINE_LOOP, [c[4], c[5], c[6], c[7]])
      # Long-axis marker (conduit bodies align this with the run).
      mid_a = Geom.linear_combination(0.5, c[4], 0.5, c[7])
      mid_b = Geom.linear_combination(0.5, c[5], 0.5, c[6])
      view.line_stipple = '-'
      view.draw(GL_LINES, [mid_a, mid_b])
      view.line_stipple = ''
      view.draw_points([@placement[:origin]], 8, 4, Sketchup::Color.new(*ORANGE))
    end

    def place_box(view)
      key = Settings.box_key
      sp = Catalog::BOXES[key]
      unless sp
        UI.messagebox('Selecciona una caja válida en Ajustes.')
        return
      end

      model = Sketchup.active_model
      pl = @placement
      model.start_operation('SKP E-Plumb — Caja', true)
      begin
        grp = Builder.drop_box(model, model.active_entities, pl[:back], sp, key, pl[:normal],
                               nil, mount: pl[:mount], quarter: @quarter)
        if grp
          model.commit_operation
        else
          model.abort_operation
          UI.messagebox('No se pudo crear la caja (geometría no válida).')
        end
      rescue StandardError => e
        model.abort_operation
        UIDialogs.report_error(e, 'colocar caja')
      end
      view.invalidate
    end

    def update_ui
      mount = Settings.surface? ? 'sobrepuesta' : 'empotrada'
      Sketchup.set_status_text("#{spec[:label]} (#{mount}) · giro #{@quarter.to_i * 90}° · " \
                               'Clic = colocar · Ctrl/Option/Tab = girar 90° · Clic derecho = cambiar caja')
      Sketchup.set_status_text('Giro (°)', SB_VCB_LABEL)
    end
  end
end
