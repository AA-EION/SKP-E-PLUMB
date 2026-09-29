# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Picker
  # ---------------------------------------------------------------------------
  # What surface is under the cursor, shared by the drawing, box and edit
  # tools. The key rules that keep tubes out of walls and boxes facing out:
  #  * Normals are converted to WORLD space through the containing groups /
  #    components (including non-uniform scale).
  #  * Normals always point toward the camera: the side the user clicked is
  #    the visible side, even when the model's faces are reversed.
  #  * A point snapped on an edge (e.g. a wall/floor corner) gets the normals
  #    of BOTH faces; on a vertex, of all its faces.
  #  * When the inference engine snapped to something without a face, the
  #    face actually visible under the cursor is found with a ray test.
  #  * The plugin's own tubes and fittings are ignored as mounting surfaces.
  # ===========================================================================
  module Picker
    module_function

    # Candidate outward normals ([[x,y,z], ...]) at the input point.
    def normals_at(view, ip, x = nil, y = nil)
      return [] unless ip&.valid?
      return [] if plugin_path?(ip_path(ip))

      eye = view.camera.eye
      pos = ip.position
      tr = safe_tr(ip)
      faces = if ip.face then [ip.face]
              elsif ip.edge then ip.edge.faces
              elsif ip.vertex then ip.vertex.faces
              else []
              end
      list = faces.map { |f| GeomUtil.world_normal(f.normal, tr, point: pos, eye: eye) }.compact
      if list.empty? && x && y
        hit = face_hit(view, x, y)
        list << hit[:normal] if hit && hit[:point].distance(pos) < GeomUtil.mm(3.0)
      end
      dedupe(list.map { |n| GeomUtil.to_a3(n) })
    rescue StandardError
      []
    end

    # [position, normals] for the cursor. When the inference landed on the
    # plugin's own tubes/fittings, the real surface behind them is used, so a
    # point never ends up floating on (or inside) an existing tube.
    def surface_point(view, ip, x, y)
      return [nil, []] unless ip&.valid?

      if plugin_path?(ip_path(ip))
        hit = face_hit(view, x, y)
        return hit ? [hit[:point], [GeomUtil.to_a3(hit[:normal])]] : [ip.position, []]
      end
      [ip.position, normals_at(view, ip, x, y)]
    end

    # The face visible under screen (x, y), skipping plugin geometry.
    # Returns { point:, normal: (Vector3d, toward camera), face: } or nil.
    def face_hit(view, x, y)
      model = view.model
      ray = view.pickray(x, y)
      origin = ray[0]
      dir = ray[1]
      eye = view.camera.eye
      6.times do
        hit = model.raytest([origin, dir], true)
        return nil unless hit

        pt, path = hit
        leaf = path && path.last
        if plugin_path?(path) || !leaf.is_a?(Sketchup::Face)
          origin = pt.offset(dir, GeomUtil.mm(0.5))
          next
        end
        tr = path_transformation(path[0...-1])
        n = GeomUtil.world_normal(leaf.normal, tr, point: pt, eye: eye)
        return n ? { point: pt, normal: n, face: leaf } : nil
      end
      nil
    rescue StandardError
      nil
    end

    # Plugin box (group/component tagged as a box) under the cursor, at any
    # nesting depth (auto boxes live inside their run), or nil.
    def box_under(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      (0...ph.count).each do |i|
        path = ph.path_at(i)
        next unless path

        found = path.find { |e| box?(e) }
        return found if found
      end
      nil
    rescue StandardError
      nil
    end

    def box?(ent)
      (ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)) &&
        ent.get_attribute(Bom::DICT, 'part') == Bom::PART_BOX
    rescue StandardError
      false
    end

    def plugin_path?(path)
      return false unless path

      path.any? do |e|
        (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
          (Bom.tagged?(e) || Bom.run_container?(e))
      end
    rescue StandardError
      false
    end

    def ip_path(ip)
      ip.respond_to?(:instance_path) ? ip.instance_path.to_a : nil
    rescue StandardError
      nil
    end

    def safe_tr(ip)
      ip.transformation
    rescue StandardError
      nil
    end

    def path_transformation(path)
      tr = nil
      (path || []).each do |e|
        next unless e.respond_to?(:transformation)

        tr = tr ? tr * e.transformation : e.transformation
      end
      tr
    end

    def dedupe(list)
      out = []
      list.each do |n|
        out << n unless out.any? { |m| GeomUtil.dot3(m, n) > 0.995 }
      end
      out.first(3)
    end

    # Describe a normal for the UI.
    def surface_name(n)
      return 'en el aire' unless n

      z = n.is_a?(Array) ? n[2] : n.z
      if z > 0.7 then 'piso'
      elsif z < -0.7 then 'techo'
      else 'pared'
      end
    end
  end
end
