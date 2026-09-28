# frozen_string_literal: true

begin
  require 'json'
rescue LoadError
  nil
end

module SkpEPlumb
  # ===========================================================================
  # Builder
  # ---------------------------------------------------------------------------
  # Turns a clicked centreline (Geom::Point3d, inches) plus per-vertex data
  # into real SketchUp geometry, and tags every piece for the BOM.
  #
  # Geometry rules:
  #  * Every clicked point remembers the surface(s) it was picked on (one
  #    normal on a face, two on an edge such as a wall/floor corner). Each
  #    SEGMENT gets the surface it runs along, and the whole path is offset
  #    so the tube lies ON those surfaces (surface install) or fully INSIDE
  #    them (embedded install) — at corners the point is pushed off both
  #    planes, so no piece of tube cuts through a wall, floor or ceiling.
  #  * Over an outside (convex) corner a bend of radius R would cut the edge,
  #    so the vertex is pushed out until the bend clears it.
  #  * Boxes mount on the surface (or recessed into it when embedded) with the
  #    cover facing out and their long axis along the run; conduits end
  #    exactly on the box wall they enter.
  #
  # BOM rules:
  #  * The run is cut into stock-length tube pieces with a coupling on each
  #    joint. A field bend is part of the tube; a premade elbow is its own
  #    part with a coupling on each end.
  #  * Run ends and boxes get the terminations of the raceway family.
  #  * Optional pull boxes when the bends between boxes exceed the code limit
  #    (NEC/NTC 2050: 360°), supports per code spacing, and the conductors
  #    inside (for fill checks and the wire list).
  # ===========================================================================
  module Builder
    TINY = 1.0e-4

    # Attribute dictionary with the editable definition of a run. Kept
    # SEPARATE from Bom::DICT so the BOM scanner still descends into it.
    RUN_DICT = 'SKP_E_PLUMB_RUN'

    COUPLING_SCALE = 1.18 # coupling radius / tube radius

    module_function

    # Public entry point.
    #   raw_pts   -> Array<Geom::Point3d> clicked centreline (world, inches)
    #   modes     -> per-vertex 'field' | 'premade' | 'box' (nil = s[:bend_mode])
    #   s         -> options (see Settings.run_options)
    #   normals   -> per-vertex Array of candidate outward normals [[x,y,z],...]
    #                (a single [x,y,z] is accepted for older data) or nil
    #   box_conns -> per-vertex box instance the point snaps to, or nil
    # Returns the run container group, or nil.
    def build_run(model, raw_pts, modes, s, normals = nil, box_conns = nil)
      s = normalize_options(s)
      pts, modes, cands, box_conns = clean_path(raw_pts, modes, normals, box_conns)
      return nil if pts.length < 2

      type = s[:type]
      size = s[:size]
      radius = GeomUtil.mm(Catalog.od_mm(type, size) / 2.0)
      info = Catalog.type_info(type)
      pipe_mat    = GeomUtil.material(model, "EPlumb_#{type}", info[:color])
      fitting_mat = GeomUtil.material(model, "EPlumb_#{type}_fit", darken(info[:color]))

      container = model.active_entities.add_group
      container.name = "Canalización #{Catalog.size_label(type, size)}"
      g = container.entities

      # Only EMT lets the user choose (set-screw vs compression); IMC/RMC are
      # threaded and PVC is solvent-welded.
      conn = type == 'EMT' ? (s[:connection] || :setscrew).to_sym : Catalog.connection_method(type)

      surface = s[:install] != 'embedded'
      off = if surface
              radius * COUPLING_SCALE + GeomUtil.mm(s[:standoff_mm].to_f)
            else
              -(radius + GeomUtil.mm(s[:cover_mm].to_f))
            end

      ctx = {
        model: model, container: container, type: type, size: size,
        segs: (s[:segments] || 16).to_i, radius: radius, od_in: radius * 2.0,
        pipe_mat: pipe_mat, fitting_mat: fitting_mat, stock_m: s[:stock_m].to_f,
        connection: conn, termination: s[:termination], surface: surface, off: off,
        len_in: 0.0, terms: 0, boxes: 0
      }

      # Box connection points take the box's own surface normal.
      box_conns.each_with_index do |b, i|
        next unless b && b.valid?

        bn = box_world_normal(b)
        cands[i] = [bn] if bn
      end

      seg_n = (0...pts.length - 1).map do |k|
        GeomUtil.segment_normal(cands[k], cands[k + 1], GeomUtil.to_a3(pts[k + 1] - pts[k]))
      end
      opts = offset_path(pts, seg_n, off)
      bend_r = GeomUtil.mm(s[:bend_radius_mm].to_f)
      clear_convex_corners!(opts, pts, seg_n, modes, bend_r, radius) if surface

      n = opts.length
      features = compute_features(opts, modes, bend_r, s[:bend_mode])

      box_spec = Catalog::BOXES[s[:box_key].to_s]
      box_key = box_spec ? s[:box_key].to_s : Catalog::DEFAULT_BOX
      box_spec ||= Catalog::BOXES[box_key]
      max_deg = s[:max_bend_deg].to_f
      max_deg = 360.0 if max_deg < 90.0

      # Sections between pull points, for bend/length stats and supports.
      sections = []
      sec = new_section(opts[0])

      # --- start of the run ---------------------------------------------------
      force_start = false
      if box_conns[0]
        e = box_enter_point(box_conns[0], opts[1], opts[0])
        opts[0] = e if e
        sec[:pts][0] = opts[0]
        force_start = true
      elsif modes[0].to_s == 'box'
        grp = place_run_box(ctx, pts, opts, seg_n, cands, 0, box_spec, box_key, opts[1] - opts[0])
        e = grp && box_enter_point(grp, opts[1], opts[0])
        opts[0] = e if e
        sec[:pts][0] = opts[0]
        force_start = true
      end

      # --- end of the run -----------------------------------------------------
      force_end = false
      if box_conns[n - 1]
        e = box_enter_point(box_conns[n - 1], opts[n - 2], opts[n - 1])
        opts[n - 1] = e if e
        force_end = true
      elsif modes[n - 1].to_s == 'box'
        grp = place_run_box(ctx, pts, opts, seg_n, cands, n - 1, box_spec, box_key, opts[n - 1] - opts[n - 2])
        e = grp && box_enter_point(grp, opts[n - 2], opts[n - 1])
        opts[n - 1] = e if e
        force_end = true
      end

      current = [opts[0]]
      (1..n - 2).each do |i|
        f = features[i]
        explicit_box = modes[i].to_s == 'box'
        conn_box = box_conns[i]
        pull = f && s[:pull_boxes] && sec[:deg] + f[:deg] > max_deg + 0.5

        if conn_box || explicit_box || pull
          # The tube reaches the box, terminates, and the run continues out of
          # the box (also a straight pass-through, e.g. one box on each side of
          # a wall: in one face, out the opposite one).
          grp = conn_box || place_run_box(ctx, pts, opts, seg_n, cands, i, box_spec, box_key, opts[i] - opts[i - 1])
          din = safe_dir(opts[i] - opts[i - 1])
          dout = safe_dir(opts[i + 1] - opts[i])
          e_in = (grp && box_enter_point(grp, opts[i - 1], opts[i])) || opts[i].offset(din, -box_inset(box_spec, opts, i))
          e_out = (grp && box_enter_point(grp, opts[i + 1], opts[i])) || opts[i].offset(dout, box_inset(box_spec, opts, i))
          current << e_in
          render_continuous_path(g, current, ctx)
          add_termination(g, e_in, din, ctx)
          add_termination(g, e_out, dout.reverse, ctx)
          sec[:pts] << e_in
          sec[:normals] << seg_n[i - 1]
          sec[:setbacks] << 0.0
          sections << sec
          sec = new_section(e_out)
          current = [e_out]
          next
        end

        sec[:pts] << opts[i]
        sec[:normals] << seg_n[i - 1]
        if f.nil? # collinear vertex, absorbed into the straight run
          sec[:setbacks] << 0.0
          next
        end

        sec[:setbacks] << opts[i].distance(f[:t_in])
        sec[:deg] += f[:deg]
        current << f[:t_in]
        if f[:mode] == :premade
          render_continuous_path(g, current, ctx)
          add_premade_elbow(g, f[:arc], f[:deg], ctx)
          add_coupling(g, f[:t_in], seg_dir(f[:arc], :start), ctx)
          add_coupling(g, f[:t_out], seg_dir(f[:arc], :end), ctx)
          current = [f[:t_out]]
        else
          current.concat(f[:arc][1..-1]) # field bend: part of the same tube
        end
      end
      current << opts[n - 1]
      render_continuous_path(g, current, ctx)
      sec[:pts] << opts[n - 1]
      sec[:normals] << seg_n[n - 2]
      sec[:setbacks] << 0.0
      sections << sec

      add_termination(g, opts[0], opts[0] - opts[1], ctx) if s[:terminate_start] || force_start
      add_termination(g, opts[n - 1], opts[n - 1] - opts[n - 2], ctx) if s[:terminate_end] || force_end

      add_straps(g, sections, ctx, s) if surface && s[:straps]

      stats = run_stats(sections, ctx, s)
      store_run_meta(container, pts, modes, cands, box_conns, s, stats)
      container
    end

    # Fill in defaults and accept string keys / older option names.
    def normalize_options(s)
      o = {}
      (s || {}).each { |k, v| o[k.to_sym] = v }
      o[:type] = 'EMT' unless Catalog.valid_type?(o[:type])
      o[:size] = Catalog.default_size(o[:type]) unless Catalog.valid_size?(o[:size].to_s, o[:type])
      o[:profile] ||= 'NTC'
      o[:stock_m] = 3.0 if o[:stock_m].to_f < 0.3
      o[:bend_radius_mm] = Catalog.min_bend_radius_mm(o[:type], o[:size]) if o[:bend_radius_mm].to_f <= 0
      o[:bend_mode] = (o[:bend_mode] || 'field').to_sym
      o[:termination] = (o[:termination] || 'std').to_s
      # 1.x runs: surface_mount true/false, auto_box every N curves.
      if o[:install].nil?
        o[:install] = 'surface'
      end
      if o[:pull_boxes].nil? && !o[:auto_box].nil?
        o[:pull_boxes] = o[:auto_box] ? true : false
        o[:max_bend_deg] ||= [[o[:auto_box_every].to_i, 1].max * 90, 360].min
      end
      o[:max_bend_deg] = 360 if o[:max_bend_deg].to_i < 90
      o[:straps] = true if o[:straps].nil?
      o[:standoff_mm] = o[:standoff_mm].to_f
      o[:cover_mm] = o[:cover_mm].nil? ? 5.0 : o[:cover_mm].to_f
      o[:wiring] ||= {}
      o
    end

    def new_section(start_pt)
      { pts: [start_pt], normals: [], setbacks: [0.0], deg: 0.0 }
    end

    def safe_dir(vec)
      vec.length.zero? ? Geom::Vector3d.new(1, 0, 0) : vec.normalize
    end

    # ---- surface offset ------------------------------------------------------

    # Offset every vertex off the surfaces of its adjacent segments.
    def offset_path(pts, seg_n, off)
      pts.each_index.map do |i|
        a = i.positive? ? seg_n[i - 1] : nil
        b = i < pts.length - 1 ? seg_n[i] : nil
        v = GeomUtil.offset_vector(a, b, off)
        if v[0].abs + v[1].abs + v[2].abs < 1.0e-12
          pts[i].clone
        else
          pts[i].offset(Geom::Vector3d.new(*v))
        end
      end
    end

    # Push vertices over outside corners (e.g. over a beam edge or around a
    # column) outward until the bend of radius `bend_r` clears the edge.
    def clear_convex_corners!(opts, raw, seg_n, modes, bend_r, radius)
      (1..opts.length - 2).each do |i|
        a = seg_n[i - 1]
        b = seg_n[i]
        next unless a && b && GeomUtil.dot3(a, b) < 0.99
        next if modes[i].to_s == 'box'

        dout = GeomUtil.to_a3(raw[i + 1] - raw[i])
        next unless GeomUtil.dot3(GeomUtil.norm3(dout), a) < -0.2 # goes behind surface a => convex

        # Pushing the vertex tilts the legs and changes the bend, so iterate
        # until the whole bend circle keeps `radius` (+1 mm) from the edge —
        # the tangent legs then clear it too.
        20.times do
          step = convex_push(opts, i, raw[i], bend_r, radius)
          break if step.nil?

          opts[i] = opts[i].offset(step[0], step[1])
        end
      end
    end

    # [direction, distance] to push vertex i away from corner point `edge`,
    # or nil when its bend already clears it.
    def convex_push(opts, i, edge, bend_r, radius)
      din_v = opts[i] - opts[i - 1]
      dout_v = opts[i + 1] - opts[i]
      return nil if din_v.length < TINY || dout_v.length < TINY

      din = din_v.normalize
      doutn = dout_v.normalize
      ang = Math.acos(clamp(din.dot(doutn), -1.0, 1.0))
      return nil if ang < 0.0175

      half = ang / 2.0
      r = [bend_r, 0.45 * [din_v.length, dout_v.length].min / Math.tan(half)].min
      bis = din.reverse + doutn
      return nil if bis.length < TINY

      bis = bis.normalize
      center = opts[i].offset(bis, r / Math.cos(half))
      need = r - radius - GeomUtil.mm(1.0)
      return nil if need <= 0

      dist = center.distance(edge)
      return nil if dist <= need + GeomUtil.mm(0.05)

      [bis.reverse, dist - need]
    end

    # ---- boxes ------------------------------------------------------------------

    # Drop a box at vertex i of the run, mounted on the surface the point was
    # drawn on and aligned with the run direction `along`.
    def place_run_box(ctx, pts, opts, seg_n, cands, i, spec, key, along)
      normals = [i.positive? ? seg_n[i - 1] : nil, seg_n[i]].compact
      normals = (cands[i] || []).dup if normals.empty?
      # Prefer a wall (horizontal normal) when the point is on a corner.
      mount = normals.min_by { |nv| nv[2].abs }
      nrm = mount ? Geom::Vector3d.new(*mount) : raycast_normal(ctx[:model], pts[i], ctx)
      nrm ||= Geom::Vector3d.new(0, 0, 1)
      other = normals.find { |nv| mount && GeomUtil.dot3(nv, mount) < 0.95 }

      origin = pts[i].clone
      d = GeomUtil.mm(spec[:d])
      origin = origin.offset(nrm, -d) unless ctx[:surface] # recessed, cover flush
      if other
        # On a corner: slide the box off the other surface so it does not
        # stick through it (e.g. a box at the foot of a wall).
        x, y, = GeomUtil.surface_basis(GeomUtil.to_a3(nrm), GeomUtil.to_a3(along))
        ext = (GeomUtil.dot3(x, other).abs * spec[:w] + GeomUtil.dot3(y, other).abs * spec[:h]) / 2.0
        origin = origin.offset(Geom::Vector3d.new(*other), GeomUtil.mm(ext))
      end
      grp = drop_box(ctx[:model], ctx[:container].entities, origin, spec, key, nrm, along,
                     mount: ctx[:surface] ? 'surface' : 'embedded')
      ctx[:boxes] += 1 if grp
      grp
    end

    # Fallback distance from a vertex to the box wall when no box geometry
    # could be resolved.
    def box_inset(spec, opts, i)
      li = opts[i].distance(opts[i - 1])
      lo = opts[i].distance(opts[i + 1])
      [GeomUtil.mm([spec[:w], spec[:h]].min) / 2.0, 0.4 * li, 0.4 * lo].min
    end

    # Build one box whose back is at `origin`, local +Z (cover) along
    # `normal`, long side along `along` (optional). Returns the group.
    def drop_box(model, entities, origin, spec, key, normal = Geom::Vector3d.new(0, 0, 1),
                 along = nil, mount: 'surface', quarter: 0)
      w = GeomUtil.mm(spec[:w])
      h = GeomUtil.mm(spec[:h])
      d = GeomUtil.mm(spec[:d])
      body_mat = GeomUtil.material(model, "EPlumb_box_#{key}", spec[:color])
      lid_mat  = GeomUtil.material(model, "EPlumb_box_#{key}_lid",
                                   spec[:color].map { |c| [(c - 25), 0].max })
      t = box_transform(origin, normal, along, quarter)
      grp = GeomUtil.box(entities, ORIGIN, w, h, d,
                         material: body_mat, lid_material: lid_mat, transform: t)
      return nil unless grp

      grp.name = spec[:label]
      Bom.tag(grp, part: Bom::PART_BOX, type: spec[:family],
                   size: "#{spec[:w]}×#{spec[:h]}×#{spec[:d]}",
                   desc: spec[:label], box_key: key, qty: 1, mount: mount,
                   std: spec[:std].to_s)
      grp
    rescue StandardError
      nil
    end

    def box_transform(origin, normal, along = nil, quarter = 0)
      hint = along && along.length > TINY ? GeomUtil.to_a3(along) : nil
      basis = GeomUtil.surface_basis(GeomUtil.to_a3(normal), hint)
      x, y, z = GeomUtil.rotate_basis(basis, quarter)
      Geom::Transformation.axes(origin, Geom::Vector3d.new(*x), Geom::Vector3d.new(*y),
                                Geom::Vector3d.new(*z))
    end

    # Transformation of an entity in world space (walks up group parents).
    def world_transformation(ent)
      tr = ent.transformation
      parent = ent.parent
      while parent.is_a?(Sketchup::ComponentDefinition)
        insts = parent.instances
        break unless insts.length == 1

        tr = insts.first.transformation * tr
        parent = insts.first.parent
      end
      tr
    rescue StandardError
      ent.transformation
    end

    # World outward normal (cover direction) of a plugin box, as [x,y,z].
    def box_world_normal(box)
      z = world_transformation(box).zaxis
      z.length.zero? ? nil : GeomUtil.to_a3(z.normalize)
    rescue StandardError
      nil
    end

    # Point on the box surface (back face for surface boxes, cover plane for
    # embedded ones) — where a conduit drawn along that surface should aim.
    def box_surface_point(box)
      key = box.get_attribute(Bom::DICT, 'box_key')
      spec = key && Catalog::BOXES[key]
      tr = world_transformation(box)
      depth = spec && box.get_attribute(Bom::DICT, 'mount') == 'embedded' ? GeomUtil.mm(spec[:d]) : 0.0
      Geom::Point3d.new(0, 0, depth).transform(tr)
    rescue StandardError
      box.bounds.center
    end

    # Where the conduit going from `from_pt` toward `to_pt` meets the box
    # wall. nil when the line does not reach the box (caller falls back).
    def box_enter_point(box, from_pt, to_pt)
      key = box.get_attribute(Bom::DICT, 'box_key')
      spec = key && Catalog::BOXES[key]
      return nil unless spec

      w = GeomUtil.mm(spec[:w])
      h = GeomUtil.mm(spec[:h])
      d = GeomUtil.mm(spec[:d])
      tr = world_transformation(box)
      inv = tr.inverse
      o = from_pt.transform(inv)
      t = to_pt.transform(inv)
      dir = t - o
      return nil if dir.length < TINY

      dv = [dir.x.to_f, dir.y.to_f, dir.z.to_f]
      tt = GeomUtil.ray_box_enter([o.x.to_f, o.y.to_f, o.z.to_f], dv,
                                  [-w / 2.0, -h / 2.0, 0.0], [w / 2.0, h / 2.0, d])
      unless tt && tt > 1.0e-6 && tt <= 1.0 + 1.0e-6
        # The line misses the box: aim at the box centre instead.
        c = Geom::Point3d.new(0, 0, d / 2.0)
        dir = c - o
        return nil if dir.length < TINY

        dv = [dir.x.to_f, dir.y.to_f, dir.z.to_f]
        tt = GeomUtil.ray_box_enter([o.x.to_f, o.y.to_f, o.z.to_f], dv,
                                    [-w / 2.0, -h / 2.0, 0.0], [w / 2.0, h / 2.0, d])
        return nil unless tt && tt > 1.0e-6
      end
      Geom::Point3d.new(o.x + dv[0] * tt, o.y + dv[1] * tt, o.z + dv[2] * tt).transform(tr)
    rescue StandardError
      nil
    end

    # Cast rays along the six axes to find the nearest surface (wall/floor/
    # ceiling) a box can back onto. Returns its world normal or nil.
    def raycast_normal(model, point, ctx)
      return nil unless model.respond_to?(:raytest)

      best = nil
      bestd = GeomUtil.mm(600.0)
      [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]].each do |a|
        dir = Geom::Vector3d.new(*a)
        hit = model.raytest([point.offset(dir, ctx[:radius] * 2.2), dir])
        next unless hit

        hp, path = hit
        next if path && path.include?(ctx[:container])

        dist = point.distance(hp)
        next unless dist < bestd

        leaf = path && path.last
        tr = nil
        (path || [])[0...-1].each do |e|
          next unless e.respond_to?(:transformation)

          tr = tr ? tr * e.transformation : e.transformation
        end
        n = leaf.is_a?(Sketchup::Face) ? GeomUtil.world_normal(leaf.normal, tr, point: hp, eye: point) : nil
        bestd = dist
        best = n || dir.reverse
      end
      best
    rescue StandardError
      nil
    end

    # ---- clean-up / metadata ------------------------------------------------------

    # Dedupe consecutive coincident points, carrying the matching per-vertex
    # data so the parallel arrays stay aligned with the points.
    def clean_path(raw_pts, modes, normals = nil, box_conns = nil)
      out_pts = []
      out_modes = []
      out_cands = []
      out_conns = []
      raw_pts.each_with_index do |p, i|
        next unless out_pts.empty? || out_pts.last.distance(p) > 1.0e-3

        out_pts << p
        out_modes << (modes && modes[i])
        out_cands << candidates(normals && normals[i])
        conn = box_conns && box_conns[i]
        out_conns << (conn.respond_to?(:valid?) && conn.valid? ? conn : nil)
      end
      [out_pts, out_modes, out_cands, out_conns]
    end

    # Normalise a per-vertex normal entry to an Array of unit [x,y,z].
    def candidates(entry)
      return [] if entry.nil?

      list = entry.first.is_a?(Numeric) ? [entry] : entry
      list.map { |v| GeomUtil.norm3(v.map(&:to_f)) }.reject { |v| v == [0.0, 0.0, 0.0] }
    rescue StandardError
      []
    end

    # Persist the run definition on its container so it can be re-opened and
    # edited later.
    def store_run_meta(group, pts, modes, cands, box_conns, s, stats = {})
      group.set_attribute(RUN_DICT, 'run', true)
      group.set_attribute(RUN_DICT, 'version', 2)
      group.set_attribute(RUN_DICT, 'conn_pid', pts.each_index.map do |i|
        b = box_conns && box_conns[i]
        (b.respond_to?(:persistent_id) ? b.persistent_id : 0).to_i
      rescue StandardError
        0
      end)
      group.set_attribute(RUN_DICT, 'px', pts.map { |p| p.x.to_f })
      group.set_attribute(RUN_DICT, 'py', pts.map { |p| p.y.to_f })
      group.set_attribute(RUN_DICT, 'pz', pts.map { |p| p.z.to_f })
      group.set_attribute(RUN_DICT, 'modes', pts.each_index.map { |i| (modes[i] || s[:bend_mode] || 'field').to_s })
      # Candidate normals, flattened: nc[i] normals for point i in nv.
      group.set_attribute(RUN_DICT, 'nc', cands.map(&:length))
      group.set_attribute(RUN_DICT, 'nv', cands.flatten.map(&:to_f))
      group.set_attribute(RUN_DICT, 'opts_json', options_json(s))
      # Plain copies used by the BOM / code review without parsing JSON.
      group.set_attribute(RUN_DICT, 'type', s[:type])
      group.set_attribute(RUN_DICT, 'size', s[:size])
      group.set_attribute(RUN_DICT, 'profile', s[:profile].to_s)
      stats.each { |k, v| group.set_attribute(RUN_DICT, k.to_s, v) }
      group
    end

    def options_json(s)
      h = {}
      s.each do |k, v|
        h[k.to_s] = v.is_a?(Symbol) ? v.to_s : v
      end
      h.to_json
    rescue StandardError
      '{}'
    end

    def run?(group)
      group.respond_to?(:attribute_dictionary) &&
        !group.attribute_dictionary(RUN_DICT).nil?
    end

    # Read the editable definition back, in the run's CURRENT position (the
    # container may have been moved/rotated since it was built).
    # Returns { pts:, modes:, normals:, box_conns:, s: }.
    def read_run_meta(group)
      return nil unless run?(group)

      px = group.get_attribute(RUN_DICT, 'px')
      py = group.get_attribute(RUN_DICT, 'py')
      pz = group.get_attribute(RUN_DICT, 'pz')
      return nil unless px && py && pz && px.length >= 2

      tr = group.transformation
      identity = tr.respond_to?(:identity?) ? tr.identity? : false
      pts = px.each_index.map do |i|
        p = Geom::Point3d.new(px[i], py[i], pz[i])
        identity ? p : p.transform(tr)
      end
      modes = group.get_attribute(RUN_DICT, 'modes') || []
      normals = read_normals(group, px.length)
      unless identity
        normals = normals.map do |list|
          list.map do |v|
            w = Geom::Vector3d.new(*v).transform(tr)
            w.length.zero? ? v : GeomUtil.to_a3(w.normalize)
          end
        end
      end

      pids = group.get_attribute(RUN_DICT, 'conn_pid')
      model = group.model
      box_conns = px.each_index.map do |i|
        pid = pids && pids[i]
        next nil unless pid && pid.to_i != 0 && model.respond_to?(:find_entity_by_persistent_id)

        begin
          ent = model.find_entity_by_persistent_id(pid.to_i)
          ent && ent.valid? ? ent : nil
        rescue StandardError
          nil
        end
      end

      { pts: pts, modes: modes, normals: normals, box_conns: box_conns, s: read_options(group) }
    end

    def read_normals(group, count)
      nc = group.get_attribute(RUN_DICT, 'nc')
      nv = group.get_attribute(RUN_DICT, 'nv')
      if nc && nv
        k = 0
        return (0...count).map do |i|
          c = nc[i].to_i
          list = (0...c).map { |j| nv[(k + j) * 3, 3] }
          k += c
          list
        end
      end
      # 1.x: one normal per point in nx/ny/nz (0,0,0 = none).
      nx = group.get_attribute(RUN_DICT, 'nx')
      ny = group.get_attribute(RUN_DICT, 'ny')
      nz = group.get_attribute(RUN_DICT, 'nz')
      (0...count).map do |i|
        if nx && ny && nz && nx[i] && (nx[i] != 0.0 || ny[i] != 0.0 || nz[i] != 0.0)
          [[nx[i], ny[i], nz[i]]]
        else
          []
        end
      end
    end

    def read_options(group)
      json = group.get_attribute(RUN_DICT, 'opts_json')
      if json && defined?(JSON)
        begin
          h = JSON.parse(json)
          return normalize_options(h)
        rescue StandardError
          nil
        end
      end
      # 1.x attributes.
      g = ->(k, d) { group.get_attribute(RUN_DICT, k, d) }
      conn = g.call('connection', '').to_s
      normalize_options(
        type: g.call('type', 'EMT'), size: g.call('size', '3/4'),
        stock_m: g.call('stock_m', 3.0).to_f, bend_radius_mm: g.call('bend_radius_mm', 114.3).to_f,
        termination: g.call('termination', 'std'), connection: conn.empty? ? nil : conn.to_sym,
        segments: g.call('segments', 24).to_i, bend_mode: g.call('bend_mode', 'field'),
        terminate_start: g.call('terminate_start', true), terminate_end: g.call('terminate_end', true),
        auto_box: g.call('auto_box', false), auto_box_every: g.call('auto_box_every', 2).to_i,
        box_key: g.call('box_key', ''), install: 'surface'
      )
    end

    # ---- feature computation ---------------------------------------------

    # For every interior vertex, decide the trimmed tangent points and the
    # fillet arc, clamping the radius so it fits the shorter adjacent leg.
    def compute_features(pts, modes, bend_r, default_mode)
      features = {}
      n = pts.length
      (1..n - 2).each do |i|
        din = pts[i] - pts[i - 1]
        dout = pts[i + 1] - pts[i]
        len_in = din.length
        len_out = dout.length
        next if len_in < TINY || len_out < TINY

        dinn = din.normalize
        doutn = dout.normalize
        ang = Math.acos(clamp(dinn.dot(doutn), -1.0, 1.0))
        next if ang < 0.0175 # ~1 degree -> collinear

        half = ang / 2.0
        r = bend_r
        max_sb = 0.45 * [len_in, len_out].min
        r = max_sb / Math.tan(half) if r * Math.tan(half) > max_sb && Math.tan(half) > TINY

        arc, _setback, t_in, t_out = GeomUtil.fillet_arc(pts[i], dinn, doutn, r)
        next if arc.nil?

        mode = ((modes && modes[i]) || default_mode).to_s
        mode = 'field' if mode == 'box'
        features[i] = { t_in: t_in, t_out: t_out, arc: arc, mode: mode.to_sym,
                        deg: ang * 180.0 / Math::PI }
      end
      features
    end

    # ---- piece builders ---------------------------------------------------

    # Cut a continuous centreline into stock-length tube pieces with a
    # coupling straddling every joint.
    def render_continuous_path(g, path, ctx)
      path = GeomUtil.clean_points(path)
      return if path.length < 2

      stock_in = GeomUtil.mm(ctx[:stock_m] * 1000.0)
      stock_in = nil if stock_in <= TINY

      piece = [path[0]]
      acc = 0.0
      prev = path[0]
      j = 1
      while j < path.length
        nxt = path[j]
        seg = nxt - prev
        seg_len = seg.length
        if seg_len <= TINY
          prev = nxt
          j += 1
          next
        end

        if stock_in.nil? || acc + seg_len <= stock_in + TINY
          piece << nxt
          acc += seg_len
          prev = nxt
          j += 1
        else
          dir = seg.normalize
          cut = prev.offset(dir, stock_in - acc)
          piece << cut
          emit_pipe_piece(g, piece, ctx)
          add_coupling(g, cut, dir, ctx)
          piece = [cut]
          acc = 0.0
          prev = cut
        end
      end
      emit_pipe_piece(g, piece, ctx) if piece.length >= 2
    end

    # One tube piece (<= a stock length). Each piece is one purchased tube.
    def emit_pipe_piece(g, piece_pts, ctx)
      len_mm = path_length_mm(piece_pts)
      ctx[:len_in] += GeomUtil.mm(len_mm)
      tube = GeomUtil.tube_group(g, piece_pts, ctx[:radius], segments: ctx[:segs],
                                                             material: ctx[:pipe_mat])
      return unless tube

      Bom.tag(tube,
              part: Bom::PART_PIPE, type: ctx[:type], size: ctx[:size],
              desc: "Tubería #{Catalog.size_label(ctx[:type], ctx[:size])}",
              length_mm: len_mm, stock_m: ctx[:stock_m],
              std: Catalog.type_info(ctx[:type])[:std].to_s)
    end

    def add_premade_elbow(g, arc_pts, deg, ctx)
      ctx[:len_in] += GeomUtil.mm(path_length_mm(arc_pts))
      tube = GeomUtil.tube_group(g, arc_pts, ctx[:radius], segments: ctx[:segs],
                                                           material: ctx[:fitting_mat])
      return unless tube

      nominal, exact = Catalog.standard_elbow(deg)
      nom = nominal % 1 == 0 ? nominal.round : nominal
      desc = "#{Catalog::ELBOW_NAME} #{nom}° #{Catalog.size_label(ctx[:type], ctx[:size])}"
      desc += " (trazado #{deg.round}°: no estándar)" unless exact
      Bom.tag(tube, part: Bom::PART_ELBOW, type: ctx[:type], size: ctx[:size], desc: desc,
                    angle: nominal.to_f, qty: 1, std: Catalog.type_info(ctx[:type])[:std].to_s)
    end

    def add_coupling(g, center, axis_vec, ctx)
      axis = axis_vec.length.zero? ? Geom::Vector3d.new(0, 0, 1) : axis_vec.normalize
      len = [ctx[:od_in] * 1.15, GeomUtil.mm(40)].max
      grp = GeomUtil.sleeve(g, center, axis, ctx[:radius] * COUPLING_SCALE, len,
                            segments: ctx[:segs], material: ctx[:fitting_mat])
      return unless grp

      label = Catalog::COUPLING_NAME[ctx[:connection]] || 'Unión'
      Bom.tag(grp,
              part: Bom::PART_COUPLING, type: ctx[:type], size: ctx[:size],
              desc: "#{label} #{Catalog.size_label(ctx[:type], ctx[:size])}", qty: 1)
    end

    # Termination into a box/panel with the correct accessories. `out_dir`
    # points from the tube end INTO the box; the parts sit inside it.
    def add_termination(g, endpt, out_dir, ctx)
      ctx[:terms] += 1
      parts = termination_parts(ctx[:connection], (ctx[:termination] || 'std').to_sym)
      return if parts.empty?

      u = out_dir.length.zero? ? Geom::Vector3d.new(0, 0, 1) : out_dir.normalize
      offset = 0.0
      parts.each do |p|
        ring_len = p[:kind] == :bushing ? GeomUtil.mm(8) : [ctx[:od_in] * 0.5, GeomUtil.mm(10)].max
        ring_r   = p[:kind] == :bushing ? ctx[:radius] * 1.35 : ctx[:radius] * 1.28
        center = endpt.offset(u, offset + ring_len / 2.0)
        grp = GeomUtil.sleeve(g, center, u, ring_r, ring_len, segments: ctx[:segs],
                                                              material: ctx[:fitting_mat])
        if grp
          if p[:part] == Bom::PART_BUSHING_GND
            begin
              side = u.axes[0]
              lug_c = center.offset(side, ring_r)
              GeomUtil.box(g, lug_c, GeomUtil.mm(8), GeomUtil.mm(6), GeomUtil.mm(6),
                           material: ctx[:fitting_mat])
            rescue StandardError
              nil
            end
          end
          Bom.tag(grp, part: p[:part], type: ctx[:type], size: ctx[:size],
                       desc: "#{p[:desc]} #{Catalog.size_label(ctx[:type], ctx[:size])}", qty: 1)
        end
        offset += ring_len
      end
    end

    # Which discrete accessories a run end needs.
    def termination_parts(method, setting)
      return [] if setting == :none

      case method
      when :setscrew, :compression
        [{ part: Bom::PART_CONNECTOR, desc: Catalog::CONNECTOR_NAME[method], kind: :connector },
         bushing_part(setting)]
      when :threaded
        [{ part: Bom::PART_LOCKNUT, desc: Catalog::LOCKNUT, kind: :locknut },
         bushing_part(setting)]
      when :solvent
        # PVC: terminal adapter + locknut. A grounding bushing is not used on
        # a non-metallic raceway.
        [{ part: Bom::PART_CONNECTOR, desc: Catalog::CONNECTOR_NAME[:solvent], kind: :connector }]
      else
        []
      end
    end

    def bushing_part(setting)
      if setting == :gnd
        { part: Bom::PART_BUSHING_GND, desc: Catalog::BUSHING_GND, kind: :bushing }
      else
        { part: Bom::PART_BUSHING_STD, desc: Catalog::BUSHING_STD, kind: :bushing }
      end
    end

    # ---- supports -------------------------------------------------------------------

    # Place code-spaced straps along each section between boxes: the first
    # 0.3 m from each box/end, then at most `spacing` apart. Only where the
    # tube runs along a surface, and never on a bend.
    def add_straps(g, sections, ctx, s)
      spacing = GeomUtil.mm(Codes.strap_spacing_m(s[:profile], ctx[:type], ctx[:size]) * 1000.0)
      end_off = GeomUtil.mm(Codes::STRAP_END_M * 1000.0)
      sections.each do |sec|
        pts = sec[:pts]
        next if pts.length < 2

        cum = [0.0]
        pts.each_cons(2) { |a, b| cum << cum.last + a.distance(b) }
        total = cum.last
        Codes.strap_positions(total, spacing, end_off).each do |dist|
          dist = shift_off_bends(dist, cum, sec[:setbacks])
          k = (0...pts.length - 1).find { |j| dist <= cum[j + 1] + TINY } || (pts.length - 2)
          nrm = sec[:normals][k]
          next unless nrm

          seg = pts[k + 1] - pts[k]
          next if seg.length < TINY

          p = pts[k].offset(seg.normalize, dist - cum[k])
          add_strap(g, p, seg.normalize, Geom::Vector3d.new(*nrm), ctx)
        end
      end
    end

    # Move a support position out of the bend zone around a vertex.
    def shift_off_bends(dist, cum, setbacks)
      (1...cum.length - 1).each do |j|
        sb = setbacks[j].to_f
        next if sb <= TINY

        lo = cum[j] - sb
        hi = cum[j] + sb
        next unless dist > lo && dist < hi

        return dist - lo < hi - dist ? lo : hi
      end
      dist
    end

    def add_strap(g, center, dir, nrm, ctx)
      ring = GeomUtil.sleeve(g, center, dir, ctx[:radius] * 1.08, GeomUtil.mm(14),
                             segments: ctx[:segs], material: ctx[:fitting_mat])
      base = center.offset(nrm, -ctx[:off])
      side = nrm * dir
      if side.length > TINY
        t = Geom::Transformation.axes(base, dir, side.normalize, nrm)
        GeomUtil.box(g, ORIGIN, GeomUtil.mm(14), ctx[:radius] * 3.2, GeomUtil.mm(1.5),
                     material: ctx[:fitting_mat], transform: t)
      end
      return unless ring

      Bom.tag(ring, part: Bom::PART_STRAP, type: ctx[:type], size: ctx[:size],
                    desc: "#{Catalog::STRAP_NAME} #{Catalog.size_label(ctx[:type], ctx[:size])}", qty: 1)
    rescue StandardError
      nil
    end

    # ---- stats for code review / wire list -----------------------------------------

    def run_stats(sections, ctx, s)
      conds = Codes.conductors(s[:wiring] || {})
      fill = Codes.fill(ctx[:type], ctx[:size], conds)
      {
        run_len_m: (GeomUtil.to_mm(ctx[:len_in]) / 1000.0).round(3),
        max_deg: sections.map { |x| x[:deg] }.max.to_f.round(1),
        max_len_m: sections.map { |x| path_length_mm(x[:pts]) / 1000.0 }.max.to_f.round(2),
        terms: ctx[:terms],
        w_role: conds.map { |c| c[:role] }, w_size: conds.map { |c| c[:size] },
        w_ins: conds.map { |c| c[:ins] }, w_color: conds.map { |c| c[:color] },
        fill_pct: fill[:pct].to_f, fill_limit: fill[:limit].to_f
      }
    end

    # ---- small helpers ----------------------------------------------------

    def seg_dir(arc_pts, which)
      which == :start ? arc_pts[1] - arc_pts[0] : arc_pts[-1] - arc_pts[-2]
    end

    def path_length_mm(pts)
      total = 0.0
      pts.each_cons(2) { |a, b| total += a.distance(b) }
      GeomUtil.to_mm(total)
    end

    def darken(rgb, factor = 0.72)
      rgb.map { |c| (c * factor).round }
    end

    def clamp(v, lo, hi)
      return lo if v < lo
      return hi if v > hi

      v
    end
  end
end
