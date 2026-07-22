# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Builder
  # ---------------------------------------------------------------------------
  # Turns a clicked centreline (array of Geom::Point3d, in inches) plus a per
  # vertex bend-mode list into real SketchUp geometry, and tags every piece for
  # the BOM. Design rules that make the BOM realistic:
  #
  #  * A straight leg longer than one stock length gets a coupling at every
  #    stock boundary (you cannot run more than one tube without joining them).
  #  * A FIELD bend is part of the pipe: the arc length is added to the pipe
  #    metres and NO fitting is generated (that is the whole point of bending).
  #  * A PREMADE elbow is its own BOM line (Codo 45/90) and is joined to the
  #    adjacent tubing with a coupling at each end.
  #  * Run ends terminate into boxes/panels with the correct accessories for
  #    the raceway family (set-screw/compression connector for EMT; locknut +
  #    bushing for IMC/RMC; terminal adapter for PVC). A grounding bushing is
  #    used when the termination is set to "gnd".
  # ===========================================================================
  module Builder
    TINY = 1.0e-4

    # Attribute dictionary used to store the editable definition of a run
    # (its centreline, per-vertex bend modes and settings). Kept SEPARATE from
    # Bom::DICT so the BOM scanner still descends into the container.
    RUN_DICT = 'SKP_E_PLUMB_RUN'

    module_function

    # Public entry point. `s` is an options hash with symbol keys:
    #   :type :size :stock_m :bend_radius_mm :termination :connection :segments
    #   :bend_mode :terminate_start :terminate_end
    # `modes` is a per-vertex Array (modes[i] is the bend mode for vertex i);
    # nil entries fall back to s[:bend_mode]. `normals` is an optional per-vertex
    # Array of world-space [x,y,z] surface normals (the face each point was drawn
    # on) used to mount boxes flush to that surface. Returns the container or nil.
    def build_run(model, raw_pts, modes, s, normals = nil)
      pts, modes, normals = clean_path(raw_pts, modes, normals)
      return nil if pts.length < 2

      type = s[:type]
      size = s[:size]
      segs = (s[:segments] || 24).to_i
      radius = GeomUtil.mm(Catalog.od_mm(type, size) / 2.0)
      od_in  = radius * 2.0
      bend_r = GeomUtil.mm(s[:bend_radius_mm].to_f)

      pipe_mat    = GeomUtil.material(model, "EPlumb_#{type}", Catalog.type_info(type)[:color])
      fitting_mat = GeomUtil.material(model, "EPlumb_#{type}_fit", darken(Catalog.type_info(type)[:color]))

      container = model.active_entities.add_group
      container.name = "Conduit #{type} #{size}\""
      g = container.entities

      # The joining method is a property of the raceway: only EMT lets the user
      # choose (set-screw vs compression); IMC/RMC are threaded, PVC is solvent.
      conn = if type == 'EMT'
               (s[:connection] || :setscrew).to_sym
             else
               Catalog.connection_method(type)
             end

      ctx = {
        type: type, size: size, segs: segs, radius: radius, od_in: od_in,
        pipe_mat: pipe_mat, fitting_mat: fitting_mat, stock_m: s[:stock_m].to_f,
        connection: conn
      }

      n = pts.length
      features = compute_features(pts, modes, bend_r, s[:bend_mode])

      # Assemble the run as a sequence of CONTINUOUS tube paths (straights +
      # field bends) separated by PREMADE elbows. Each continuous path is then
      # cut into stock-length tube pieces, and a coupling straddles every joint
      # (one tube ends, the next begins, the union sits on top). A premade elbow
      # is its own fitting, joined to the tubes with a coupling on each side.
      box_key = s[:box_key]
      box_spec = box_key && Catalog::BOXES[box_key]
      auto_on = s[:auto_box] && !box_spec.nil?
      every = (s[:auto_box_every] || 2).to_i
      every = 2 if every < 1

      current = [pts[0]]
      bends_since_box = 0
      (1..n - 2).each do |i|
        f = features[i]
        next if f.nil? # collinear vertex, absorbed into the straight run

        if auto_on && bends_since_box >= every
          # RETIE pull box: the tube reaches the box, terminates (connector /
          # locknut + bushing, or grounding bushing), and the run continues out
          # the other side with its own termination. The box replaces the curve.
          din = safe_dir(pts[i] - pts[i - 1])
          dout = safe_dir(pts[i + 1] - pts[i])
          li = (pts[i] - pts[i - 1]).length
          lo = (pts[i + 1] - pts[i]).length
          inset = [GeomUtil.mm([box_spec[:w], box_spec[:h]].min) / 2.0,
                   0.4 * li, 0.4 * lo].min

          nrm = auto_box_normal(model, pts, i, normals, ctx, container)
          current << pts[i].offset(din, -inset)
          render_continuous_path(g, current, ctx)
          add_termination(g, pts[i].offset(din, -inset), din, ctx, s[:termination])
          drop_box(model, g, pts[i], box_spec, box_key, nrm)
          add_termination(g, pts[i].offset(dout, inset), dout.reverse, ctx, s[:termination])
          current = [pts[i].offset(dout, inset)]
          bends_since_box = 0
        elsif f[:mode] == :field
          current << f[:t_in]
          current.concat(f[:arc][1..-1]) # bend is part of the continuous tube
          bends_since_box += 1
        else
          current << f[:t_in]
          render_continuous_path(g, current, ctx)
          add_premade_elbow(g, f[:arc], f[:deg], ctx)
          add_coupling(g, f[:t_in], seg_dir(f[:arc], :start), ctx)
          add_coupling(g, f[:t_out], seg_dir(f[:arc], :end), ctx)
          current = [f[:t_out]]
          bends_since_box += 1
        end
      end
      current << pts[n - 1]
      render_continuous_path(g, current, ctx)

      add_termination(g, pts[0], pts[0] - pts[1], ctx, s[:termination]) if s[:terminate_start]
      add_termination(g, pts[n - 1], pts[n - 1] - pts[n - 2], ctx, s[:termination]) if s[:terminate_end]

      store_run_meta(container, pts, modes, normals, s)
      container
    end

    def safe_dir(vec)
      vec.length.zero? ? Geom::Vector3d.new(1, 0, 0) : vec.normalize
    end

    # Outward normal of the surface a box should mount on at vertex i. Prefers
    # the face the point was drawn on; falls back to a short raycast toward the
    # nearest surface; finally to world up.
    def auto_box_normal(model, pts, i, normals, ctx, container)
      if normals && normals[i]
        v = Geom::Vector3d.new(*normals[i])
        return v unless v.length.zero?
      end
      raycast_normal(model, pts[i], ctx, container) || Geom::Vector3d.new(0, 0, 1)
    end

    # Cast rays along the six axes to find the nearest surface (wall/floor/
    # ceiling) the box can back onto. Best effort — returns nil if nothing near.
    def raycast_normal(model, point, ctx, container)
      return nil unless model.respond_to?(:raytest)

      best = nil
      bestd = GeomUtil.mm(600.0) # only consider surfaces within ~0.6 m
      off = ctx[:radius] * 2.2   # start the ray just outside our own tube
      axes = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
      axes.each do |a|
        dir = Geom::Vector3d.new(*a)
        origin = point.offset(dir, off)
        hit = model.raytest([origin, dir])
        next unless hit

        hp = hit[0]
        path = hit[1]
        next if path && container && path.respond_to?(:include?) && path.include?(container)

        d = point.distance(hp)
        if d < bestd
          bestd = d
          best = dir.reverse # box faces back out toward the run
        end
      end
      best
    rescue StandardError
      nil
    end

    # Dedupe consecutive coincident points, carrying the matching bend mode and
    # surface normal so the parallel arrays stay aligned with the point array.
    def clean_path(raw_pts, modes, normals = nil)
      out_pts = []
      out_modes = []
      out_normals = []
      raw_pts.each_with_index do |p, i|
        next unless out_pts.empty? || out_pts.last.distance(p) > 1.0e-6

        out_pts << p
        out_modes << (modes && modes[i])
        out_normals << (normals && normals[i])
      end
      [out_pts, out_modes, out_normals]
    end

    # ---- editable run metadata -------------------------------------------

    # Persist the run definition on its container so it can be re-opened and
    # edited by anchors later.
    def store_run_meta(group, pts, modes, normals, s)
      group.set_attribute(RUN_DICT, 'run', true)
      group.set_attribute(RUN_DICT, 'px', pts.map { |p| p.x.to_f })
      group.set_attribute(RUN_DICT, 'py', pts.map { |p| p.y.to_f })
      group.set_attribute(RUN_DICT, 'pz', pts.map { |p| p.z.to_f })
      group.set_attribute(RUN_DICT, 'modes', pts.each_index.map { |i| (modes[i] || s[:bend_mode] || 'field').to_s })
      # Surface normals (0,0,0 marks "none").
      group.set_attribute(RUN_DICT, 'nx', pts.each_index.map { |i| normals && normals[i] ? normals[i][0].to_f : 0.0 })
      group.set_attribute(RUN_DICT, 'ny', pts.each_index.map { |i| normals && normals[i] ? normals[i][1].to_f : 0.0 })
      group.set_attribute(RUN_DICT, 'nz', pts.each_index.map { |i| normals && normals[i] ? normals[i][2].to_f : 0.0 })
      group.set_attribute(RUN_DICT, 'type', s[:type])
      group.set_attribute(RUN_DICT, 'size', s[:size])
      group.set_attribute(RUN_DICT, 'stock_m', s[:stock_m].to_f)
      group.set_attribute(RUN_DICT, 'bend_radius_mm', s[:bend_radius_mm].to_f)
      group.set_attribute(RUN_DICT, 'termination', s[:termination].to_s)
      group.set_attribute(RUN_DICT, 'connection', (s[:connection] || '').to_s)
      group.set_attribute(RUN_DICT, 'segments', s[:segments].to_i)
      group.set_attribute(RUN_DICT, 'bend_mode', (s[:bend_mode] || 'field').to_s)
      group.set_attribute(RUN_DICT, 'terminate_start', s[:terminate_start] ? true : false)
      group.set_attribute(RUN_DICT, 'terminate_end', s[:terminate_end] ? true : false)
      group.set_attribute(RUN_DICT, 'auto_box', s[:auto_box] ? true : false)
      group.set_attribute(RUN_DICT, 'auto_box_every', (s[:auto_box_every] || 2).to_i)
      group.set_attribute(RUN_DICT, 'box_key', s[:box_key].to_s)
      group
    end

    def run?(group)
      group.respond_to?(:attribute_dictionary) &&
        !group.attribute_dictionary(RUN_DICT).nil?
    end

    # Read the editable definition back. Returns { pts:, modes:, normals:, s: }.
    def read_run_meta(group)
      return nil unless run?(group)

      px = group.get_attribute(RUN_DICT, 'px')
      py = group.get_attribute(RUN_DICT, 'py')
      pz = group.get_attribute(RUN_DICT, 'pz')
      return nil unless px && py && pz && px.length >= 2

      pts = px.each_index.map { |i| Geom::Point3d.new(px[i], py[i], pz[i]) }
      modes = group.get_attribute(RUN_DICT, 'modes') || []

      nx = group.get_attribute(RUN_DICT, 'nx')
      ny = group.get_attribute(RUN_DICT, 'ny')
      nz = group.get_attribute(RUN_DICT, 'nz')
      normals = px.each_index.map do |i|
        if nx && ny && nz && nx[i] && (nx[i] != 0.0 || ny[i] != 0.0 || nz[i] != 0.0)
          [nx[i], ny[i], nz[i]]
        end
      end

      conn = group.get_attribute(RUN_DICT, 'connection').to_s

      s = {
        type: group.get_attribute(RUN_DICT, 'type', 'EMT'),
        size: group.get_attribute(RUN_DICT, 'size', '3/4'),
        stock_m: group.get_attribute(RUN_DICT, 'stock_m', 3.0).to_f,
        bend_radius_mm: group.get_attribute(RUN_DICT, 'bend_radius_mm', 114.3).to_f,
        termination: group.get_attribute(RUN_DICT, 'termination', 'std'),
        connection: conn.empty? ? nil : conn.to_sym,
        segments: group.get_attribute(RUN_DICT, 'segments', 24).to_i,
        bend_mode: group.get_attribute(RUN_DICT, 'bend_mode', 'field'),
        terminate_start: group.get_attribute(RUN_DICT, 'terminate_start', true),
        terminate_end: group.get_attribute(RUN_DICT, 'terminate_end', true),
        auto_box: group.get_attribute(RUN_DICT, 'auto_box', false),
        auto_box_every: group.get_attribute(RUN_DICT, 'auto_box_every', 2).to_i,
        box_key: group.get_attribute(RUN_DICT, 'box_key', '')
      }
      { pts: pts, modes: modes, normals: normals, s: s }
    end

    # ---- feature computation ---------------------------------------------

    # For every interior vertex, decide the trimmed tangent points and the
    # fillet arc, clamping the radius so it fits the shorter adjacent leg.
    def compute_features(pts, modes, bend_r, default_mode)
      features = {}
      n = pts.length
      (1..n - 2).each do |i|
        a = pts[i - 1]
        v = pts[i]
        b = pts[i + 1]
        din = v - a
        dout = b - v
        len_in = din.length
        len_out = dout.length
        next if len_in < TINY || len_out < TINY

        dinn = din.normalize
        doutn = dout.normalize
        cosang = clamp(dinn.dot(doutn), -1.0, 1.0)
        ang = Math.acos(cosang)
        next if ang < 0.0175 # ~1 degree -> collinear

        half = ang / 2.0
        r = bend_r
        max_sb = 0.45 * [len_in, len_out].min
        sb = r * Math.tan(half)
        if sb > max_sb && Math.tan(half) > TINY
          r = max_sb / Math.tan(half)
        end

        arc, _setback, t_in, t_out = GeomUtil.fillet_arc(v, dinn, doutn, r)
        next if arc.nil?

        mode = (modes && modes[i]) || default_mode
        mode = mode.to_sym
        features[i] = { t_in: t_in, t_out: t_out, arc: arc, mode: mode,
                        deg: ang * 180.0 / Math::PI }
      end
      features
    end

    # ---- piece builders ---------------------------------------------------

    # Cut a continuous centreline into stock-length tube pieces. Each piece is
    # its own tube (so you see where every tube is), and a coupling straddles
    # every joint where one tube ends and the next begins.
    def render_continuous_path(g, path, ctx)
      path = GeomUtil.clean_points(path)
      return if path.length < 2

      stock_in = GeomUtil.mm(ctx[:stock_m] * 1000.0)
      stock_in = nil if stock_in && stock_in <= TINY

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
          # Split this segment at the stock boundary; drop a coupling there.
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
      tube = GeomUtil.tube_group(g, piece_pts, ctx[:radius], segments: ctx[:segs],
                                                             material: ctx[:pipe_mat])
      return unless tube

      Bom.tag(tube,
              part: Bom::PART_PIPE, type: ctx[:type], size: ctx[:size],
              desc: "Tubería #{ctx[:type]} #{ctx[:size]}\"",
              length_mm: path_length_mm(piece_pts), stock_m: ctx[:stock_m])
    end

    # Build one box (used by the RETIE auto-box), oriented by `normal`.
    def drop_box(model, entities, origin, spec, key, normal = Geom::Vector3d.new(0, 0, 1))
      w = GeomUtil.mm(spec[:w])
      h = GeomUtil.mm(spec[:h])
      d = GeomUtil.mm(spec[:d])
      body_mat = GeomUtil.material(model, "EPlumb_box_#{key}", spec[:color])
      lid_mat  = GeomUtil.material(model, "EPlumb_box_#{key}_lid",
                                   spec[:color].map { |c| [(c - 25), 0].max })
      t = GeomUtil.surface_transform(origin, normal)
      grp = GeomUtil.box(entities, ORIGIN, w, h, d,
                         material: body_mat, lid_material: lid_mat, transform: t)
      return unless grp

      grp.name = spec[:label]
      Bom.tag(grp, part: Bom::PART_BOX, type: spec[:family],
                   size: "#{spec[:w]}×#{spec[:h]}×#{spec[:d]}",
                   desc: spec[:label], box_key: key, qty: 1)
    rescue StandardError
      nil
    end

    def add_premade_elbow(g, arc_pts, deg, ctx)
      tube = GeomUtil.tube_group(g, arc_pts, ctx[:radius], segments: ctx[:segs],
                                                           material: ctx[:fitting_mat])
      return unless tube

      is90 = (deg - 90.0).abs <= (deg - 45.0).abs
      part = is90 ? Bom::PART_ELBOW90 : Bom::PART_ELBOW45
      base = is90 ? Catalog::ELBOW_90 : Catalog::ELBOW_45
      desc = "#{base} #{ctx[:type]} #{ctx[:size]}\" (#{deg.round(0)}°)"
      Bom.tag(tube, part: part, type: ctx[:type], size: ctx[:size], desc: desc, qty: 1)
    end

    def add_coupling(g, center, axis_vec, ctx)
      axis = axis_vec.length.zero? ? Geom::Vector3d.new(0, 0, 1) : axis_vec.normalize
      len = [ctx[:od_in] * 1.15, GeomUtil.mm(40)].max
      rr = ctx[:radius] * 1.18
      grp = GeomUtil.sleeve(g, center, axis, rr, len, segments: ctx[:segs],
                                                      material: ctx[:fitting_mat])
      return unless grp

      label = Catalog::COUPLING_NAME[ctx[:connection]] || 'Copla'
      Bom.tag(grp,
              part: Bom::PART_COUPLING, type: ctx[:type], size: ctx[:size],
              desc: "#{label} #{ctx[:type]} #{ctx[:size]}\"", qty: 1)
    end

    # Termination into a box/panel with the correct accessories.
    def add_termination(g, endpt, out_dir, ctx, termination)
      setting = (termination || 'std').to_sym
      parts = termination_parts(ctx[:connection], setting)
      return if parts.empty?

      u = out_dir.length.zero? ? Geom::Vector3d.new(0, 0, 1) : out_dir.normalize
      offset = 0.0
      parts.each do |p|
        ring_len = p[:kind] == :bushing ? GeomUtil.mm(8) : [ctx[:od_in] * 0.9, GeomUtil.mm(30)].max
        ring_r   = p[:kind] == :bushing ? ctx[:radius] * 1.5 : ctx[:radius] * 1.28
        center = endpt.offset(u, offset + ring_len / 2.0)
        grp = GeomUtil.sleeve(g, center, u, ring_r, ring_len, segments: ctx[:segs],
                                                              material: ctx[:fitting_mat])
        if grp
          # grounding bushing gets a small lug on the side
          if p[:part] == Bom::PART_BUSHING_GND
            side = u.axes[0]
            lug_c = center.offset(side, ring_r + GeomUtil.mm(4))
            begin
              GeomUtil.box(g, lug_c, GeomUtil.mm(10), GeomUtil.mm(8),
                           GeomUtil.mm(8), material: ctx[:fitting_mat])
            rescue StandardError
              nil
            end
          end
          Bom.tag(grp, part: p[:part], type: ctx[:type], size: ctx[:size],
                       desc: "#{p[:desc]} #{ctx[:type]} #{ctx[:size]}\"", qty: 1)
        end
        offset += ring_len
      end
    end

    # Which discrete accessories a run end needs.
    def termination_parts(method, setting)
      return [] if setting == :none

      case method
      when :setscrew, :compression
        parts = [{ part: Bom::PART_CONNECTOR, desc: Catalog::CONNECTOR_NAME[method], kind: :connector }]
        parts << bushing_part(setting)
      when :threaded
        parts = [{ part: Bom::PART_LOCKNUT, desc: Catalog::LOCKNUT, kind: :locknut }]
        parts << bushing_part(setting)
      when :solvent
        # PVC: terminal adapter (bundles locknut). No metallic bushing.
        parts = [{ part: Bom::PART_CONNECTOR, desc: Catalog::CONNECTOR_NAME[:solvent], kind: :connector }]
      else
        parts = []
      end
      parts
    end

    def bushing_part(setting)
      if setting == :gnd
        { part: Bom::PART_BUSHING_GND, desc: Catalog::BUSHING_GND, kind: :bushing }
      else
        { part: Bom::PART_BUSHING_STD, desc: Catalog::BUSHING_STD, kind: :bushing }
      end
    end

    # ---- small helpers ----------------------------------------------------

    def seg_dir(arc_pts, which)
      if which == :start
        arc_pts[1] - arc_pts[0]
      else
        arc_pts[-1] - arc_pts[-2]
      end
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
