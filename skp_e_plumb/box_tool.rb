# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # BoxTool
  # ---------------------------------------------------------------------------
  # Click to drop the currently selected box (Plexo watertight box, or a Rawelt
  # condulet / FS-FD box) at the picked point. If the pick lands on a face the
  # box is mounted flush to that face with its cover facing outward; otherwise
  # it sits on the ground plane. Each box is tagged for the BOM.
  # ===========================================================================
  class BoxTool
    def activate
      @ip = Sketchup::InputPoint.new
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

    def onMouseMove(_flags, x, y, view)
      @ip.pick(view, x, y)
      view.tooltip = @ip.tooltip
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @ip.pick(view, x, y)
      place_box(@ip.position.clone, @ip.face, view)
    end

    def draw(view)
      @ip.draw(view) if @ip.valid?
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@ip.position) if @ip.valid?
      bb
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    private

    def place_box(origin, face, view)
      key = Settings.box_key
      spec = Catalog::BOXES[key]
      unless spec
        UI.messagebox('Selecciona una caja válida en Ajustes.')
        return
      end

      model = Sketchup.active_model
      normal = face ? face.normal : Geom::Vector3d.new(0, 0, 1)
      normal = Geom::Vector3d.new(0, 0, 1) if normal.length.zero?

      axes = normal.axes
      transform = Geom::Transformation.axes(origin, axes[0], axes[1], normal)

      w = GeomUtil.mm(spec[:w])
      h = GeomUtil.mm(spec[:h])
      d = GeomUtil.mm(spec[:d])
      body_mat = GeomUtil.material(model, "EPlumb_box_#{key}", spec[:color])
      lid_mat  = GeomUtil.material(model, "EPlumb_box_#{key}_lid",
                                   spec[:color].map { |c| [(c - 25), 0].max })

      model.start_operation('SKP E-Plumb — Caja', true)
      grp = GeomUtil.box(model.active_entities, ORIGIN, w, h, d,
                         material: body_mat, lid_material: lid_mat, transform: transform)
      if grp
        grp.name = spec[:label]
        Bom.tag(grp, part: Bom::PART_BOX, type: spec[:family], size: box_size_label(spec),
                     desc: spec[:label], box_key: key, qty: 1)
        model.commit_operation
      else
        model.abort_operation
      end
      view.invalidate
    end

    def box_size_label(spec)
      "#{spec[:w]}×#{spec[:h]}×#{spec[:d]}"
    end

    def update_ui
      spec = Catalog::BOXES[Settings.box_key]
      label = spec ? spec[:label] : 'Caja'
      Sketchup.set_status_text("SKP E-Plumb · Colocar: #{label} · clic para ubicar")
    end
  end
end
