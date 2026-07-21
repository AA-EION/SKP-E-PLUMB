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

    module_function

    # Public entry point. `s` is an options hash with symbol keys:
    #   :type :size :stock_m :bend_radius_mm :termination :connection :segments
    #   :terminate_start :terminate_end (booleans)
    # Returns the container group or nil.
    def build_run(model, raw_pts, vertex_modes, s)
      pts = GeomUtil.clean_points(raw_pts)
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
      features = compute_features(pts, vertex_modes, bend_r, s[:bend_mode])

      prev = pts[0]
      (1..n - 2).each do |i|
        f = features[i]
        next if f.nil? # collinear vertex, absorb into the straight leg

        add_leg(g, prev, f[:t_in], ctx)
        if f[:mode] == :field
          add_field_bend(g, f[:arc], ctx)
        else
          add_premade_elbow(g, f[:arc], f[:deg], ctx)
          add_coupling(g, f[:t_in], seg_dir(f[:arc], :start), ctx)
          add_coupling(g, f[:t_out], seg_dir(f[:arc], :end), ctx)
        end
        prev = f[:t_out]
      end
      add_leg(g, prev, pts[n - 1], ctx)

      add_termination(g, pts[0], pts[0] - pts[1], ctx, s[:termination]) if s[:terminate_start]
      add_termination(g, pts[n - 1], pts[n - 1] - pts[n - 2], ctx, s[:termination]) if s[:terminate_end]

      container
    end

    # ---- feature computation ---------------------------------------------

    # For every interior vertex, decide the trimmed tangent points and the
    # fillet arc, clamping the radius so it fits the shorter adjacent leg.
    def compute_features(pts, vertex_modes, bend_r, default_mode)
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

        mode = (vertex_modes && vertex_modes[i - 1]) || default_mode
        mode = mode.to_sym
        features[i] = { t_in: t_in, t_out: t_out, arc: arc, mode: mode,
                        deg: ang * 180.0 / Math::PI }
      end
      features
    end

    # ---- piece builders ---------------------------------------------------

    # A straight pipe leg with couplings at each stock boundary.
    def add_leg(g, a, b, ctx)
      u = b - a
      length = u.length
      return if length < TINY

      u.normalize!
      tube = GeomUtil.straight_tube(g, a, b, ctx[:radius], segments: ctx[:segs],
                                                           material: ctx[:pipe_mat])
      if tube
        Bom.tag(tube,
                part: Bom::PART_PIPE, type: ctx[:type], size: ctx[:size],
                desc: "Tubería #{ctx[:type]} #{ctx[:size]}\"",
                length_mm: GeomUtil.to_mm(length), stock_m: ctx[:stock_m])
      end

      stock_in = GeomUtil.mm(ctx[:stock_m] * 1000.0)
      return if stock_in <= TINY

      k = 1
      while k * stock_in < length - TINY
        c = a.offset(u, k * stock_in)
        add_coupling(g, c, u, ctx)
        k += 1
      end
    end

    def add_field_bend(g, arc_pts, ctx)
      tube = GeomUtil.tube_group(g, arc_pts, ctx[:radius], segments: ctx[:segs],
                                                           material: ctx[:pipe_mat])
      return unless tube

      Bom.tag(tube,
              part: Bom::PART_PIPE, type: ctx[:type], size: ctx[:size],
              desc: "Tubería #{ctx[:type]} #{ctx[:size]}\" (curva de campo)",
              length_mm: path_length_mm(arc_pts), stock_m: ctx[:stock_m])
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
