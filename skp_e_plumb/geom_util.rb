# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # GeomUtil
  # ---------------------------------------------------------------------------
  # Low level geometry helpers built on the SketchUp API. Everything here works
  # in SketchUp internal units (inches); callers pass millimetres and use #mm.
  #
  # The core primitive is #tube_group, a "sweep a circle profile along a
  # centreline" routine. Straight pipes, curved field-bends and factory elbows
  # are all just a centreline handed to that routine.
  # ===========================================================================
  module GeomUtil
    DEFAULT_SEGMENTS = 24
    ARC_SEGMENTS     = 16 # per 90° of arc

    module_function

    # Millimetres -> SketchUp internal length (inches).
    def mm(value)
      value.to_f / 25.4
    end

    # Inches -> millimetres.
    def to_mm(value)
      value.to_f * 25.4
    end

    # Find/create a named material with an RGB colour.
    def material(model, name, rgb)
      mats = model.materials
      mat  = mats[name]
      unless mat
        mat = mats.add(name)
        mat.color = Sketchup::Color.new(*rgb)
      end
      mat
    end

    # Build a swept tube (solid) inside its own group and return the group.
    #   parent   -> Sketchup::Entities to add the group to
    #   pts      -> Array<Geom::Point3d> centreline (>= 2 points), in inches
    #   radius   -> profile radius in inches
    #   segments -> circle facet count
    #   material -> optional Sketchup::Material applied to the group
    def tube_group(parent, pts, radius, segments: DEFAULT_SEGMENTS, material: nil)
      pts = clean_points(pts)
      return nil if pts.length < 2 || radius <= 0

      group = parent.add_group
      ents  = group.entities

      dir = pts[1] - pts[0]
      return cleanup(group) if dir.length.zero?

      normal = dir.normalize
      circle = ents.add_circle(pts[0], normal, radius, segments)
      face   = ents.add_face(circle)
      return cleanup(group) unless face

      path = ents.add_edges(pts)
      begin
        face.followme(path)
      rescue StandardError
        return cleanup(group)
      end

      # Remove the leftover centreline edges (interior to the solid).
      leftovers = path.select { |e| e.respond_to?(:valid?) && e.valid? }
      ents.erase_entities(leftovers) unless leftovers.empty?

      group.material = material if material
      group
    end

    # Straight tube between two points.
    def straight_tube(parent, p1, p2, radius, segments: DEFAULT_SEGMENTS, material: nil)
      tube_group(parent, [p1, p2], radius, segments: segments, material: material)
    end

    # A short sleeve (coupling/connector body) centred on `center`, whose axis
    # is `axis` (a vector). Radius is usually a little larger than the pipe.
    def sleeve(parent, center, axis, radius, length, segments: DEFAULT_SEGMENTS, material: nil)
      a  = axis.normalize
      h  = length / 2.0
      p1 = center.offset(a, -h)
      p2 = center.offset(a, h)
      tube_group(parent, [p1, p2], radius, segments: segments, material: material)
    end

    # Centreline points for a circular arc that fillets the corner at `vertex`
    # between incoming direction `din` and outgoing direction `dout`.
    #   radius -> arc radius to the centreline (inches)
    # Returns [arc_points, setback] where setback is how far back along each
    # leg the tangent point sits, or nil when the corner is (near) straight.
    def fillet_arc(vertex, din, dout, radius)
      din  = din.normalize
      dout = dout.normalize

      # Deflection angle between the incoming travel direction and the outgoing.
      cos = clamp(din.dot(dout), -1.0, 1.0)
      angle = Math.acos(cos) # 0 = straight, PI = full reversal
      return nil if angle < 0.017 # < ~1 degree, treat as straight

      half = angle / 2.0
      setback = radius * Math.tan(half)

      # Tangent points on each leg.
      t_in  = vertex.offset(din, -setback)  # back along incoming leg
      t_out = vertex.offset(dout, setback)  # forward along outgoing leg

      # Arc centre: perpendicular bisector direction.
      bisect = (din.reverse + dout)
      return nil if bisect.length.zero?

      bisect = bisect.normalize
      dist_to_center = radius / Math.cos(half)
      center = vertex.offset(bisect, dist_to_center)

      # Rotation axis (normal of the bend plane).
      axis = din * dout
      return nil if axis.length.zero?

      axis = axis.normalize

      steps = [(ARC_SEGMENTS * angle / (Math::PI / 2.0)).ceil, 4].max
      v0 = t_in - center
      pts = (0..steps).map do |i|
        t = angle * i / steps.to_f
        rot = Geom::Transformation.rotation(center, axis, t)
        p = center + v0
        p.transform(rot)
      end

      [pts, setback, t_in, t_out]
    end

    # Points of an arc for a factory elbow of the given sweep angle (radians)
    # starting at `start_pt`, initial direction `din`, bending toward `dout`.
    def elbow_arc(start_pt, din, dout, radius, sweep_angle)
      din  = din.normalize
      dout = dout.normalize
      axis = din * dout
      axis = Geom::Vector3d.new(0, 0, 1) if axis.length.zero?
      axis = axis.normalize

      # Centre is perpendicular to din at distance radius on the bend side.
      side = axis * din # points from start toward centre
      side = side.normalize
      center = start_pt.offset(side, radius)
      v0 = start_pt - center

      steps = [(ARC_SEGMENTS * sweep_angle / (Math::PI / 2.0)).ceil, 4].max
      (0..steps).map do |i|
        t = sweep_angle * i / steps.to_f
        rot = Geom::Transformation.rotation(center, axis, t)
        p = center + v0
        p.transform(rot)
      end
    end

    # ---- surface orientation ---------------------------------------------
    # Build an orthonormal basis for placing a box flat on a surface whose
    # outward normal is given. Local +Z (the box depth) aligns to the normal.
    # Local +X (the box's long axis) follows `xhint` projected onto the
    # surface when given (so a conduit body lines up with its run); otherwise
    # +Y points "up" along the surface and +X is horizontal. Pure-array maths
    # so it can be unit tested without SketchUp. Returns [x, y, z] arrays.
    def surface_basis(normal3, xhint = nil)
      n = norm3(normal3)
      return [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]] if n == [0.0, 0.0, 0.0]

      if xhint
        h = sub3(xhint, scale3(n, dot3(xhint, n)))
        if len3(h) > 1.0e-6
          x = norm3(h)
          return [x, norm3(cross3(n, x)), n]
        end
      end
      up = [0.0, 0.0, 1.0]
      ref = parallel3?(n, up) ? [1.0, 0.0, 0.0] : up
      x = norm3(cross3(ref, n))
      y = norm3(cross3(n, x))
      [x, y, n]
    end

    # Geom::Transformation that places a box flat on the surface at `origin`.
    def surface_transform(origin, normal, xhint = nil)
      hint = xhint && [xhint.x.to_f, xhint.y.to_f, xhint.z.to_f]
      x, y, z = surface_basis([normal.x.to_f, normal.y.to_f, normal.z.to_f], hint)
      Geom::Transformation.axes(origin,
                                Geom::Vector3d.new(*x),
                                Geom::Vector3d.new(*y),
                                Geom::Vector3d.new(*z))
    end

    # Rotate a surface basis by `quarter` × 90° about its normal.
    def rotate_basis(basis, quarter)
      x, y, z = basis
      (quarter.to_i % 4).times { x, y = y, scale3(x, -1.0) }
      [x, y, z]
    end

    # Offset that moves a point lying on up to two surfaces (outward normals
    # a and b, unit arrays or nil) so it ends `off` away from BOTH planes —
    # i.e. the intersection of the two offset planes nearest the point. For a
    # single surface it is simply off·a. Negative `off` goes into the surface.
    def offset_vector(a, b, off)
      return [0.0, 0.0, 0.0] if a.nil? && b.nil?
      return scale3(a || b, off) if a.nil? || b.nil?

      c = dot3(a, b)
      return scale3(a, off) if c > 0.999 || c < -0.9 # same plane / opposite faces

      k = off / (1.0 + c)
      add3(scale3(a, k), scale3(b, k))
    end

    # Surface normal of the segment p->q given the candidate normals recorded
    # at each end (arrays of unit normals). A valid normal is perpendicular to
    # the segment; one shared by both ends wins, then either end's. nil when
    # the segment does not run along any known surface.
    def segment_normal(cands_p, cands_q, dir)
      d = norm3(dir)
      perp = ->(n) { dot3(n, d).abs < 0.05 }
      cp = (cands_p || []).select(&perp)
      cq = (cands_q || []).select(&perp)
      shared = cp.find { |n| cq.any? { |m| dot3(n, m) > 0.995 } }
      shared || cp.first || cq.first
    end

    # Distance t (>0) from an interior point `c` along unit `dir` to where the
    # ray exits an axis-aligned box [mins..maxs]. Pure arrays; returns nil if no
    # exit found.
    def ray_box_t(c, dir, mins, maxs)
      t = nil
      3.times do |i|
        next if dir[i].abs < 1.0e-12

        [mins[i], maxs[i]].each do |b|
          tt = (b - c[i]) / dir[i]
          next if tt <= 1.0e-9

          ok = true
          3.times do |j|
            next if j == i

            v = c[j] + dir[j] * tt
            if v < mins[j] - 1.0e-6 || v > maxs[j] + 1.0e-6
              ok = false
              break
            end
          end
          t = tt if ok && (t.nil? || tt < t)
        end
      end
      t
    end

    # Slab test: parameter t >= 0 where the ray origin + t·dir ENTERS the
    # axis-aligned box [mins..maxs] (0 if it starts inside). nil if it misses.
    def ray_box_enter(origin, dir, mins, maxs)
      tmin = 0.0
      tmax = Float::INFINITY
      3.times do |i|
        if dir[i].abs < 1.0e-12
          return nil if origin[i] < mins[i] - 1.0e-9 || origin[i] > maxs[i] + 1.0e-9

          next
        end
        t1 = (mins[i] - origin[i]) / dir[i]
        t2 = (maxs[i] - origin[i]) / dir[i]
        t1, t2 = t2, t1 if t1 > t2
        tmin = t1 if t1 > tmin
        tmax = t2 if t2 < tmax
        return nil if tmin > tmax
      end
      tmin
    end

    # World-space normal of a face seen through `tr` (Geom::Transformation or
    # nil). Uses two in-plane vectors so non-uniform scaling is handled, and
    # optionally flips it to face `eye` (the camera) — the side you clicked is
    # the visible one, whatever the face orientation in the model.
    def world_normal(face_normal, tr = nil, point: nil, eye: nil)
      n = face_normal
      if tr
        u, v = n.axes
        wn = u.transform(tr) * v.transform(tr)
        n = wn.length > 1.0e-12 ? wn.normalize : n.transform(tr)
      end
      return nil if n.length.zero?

      n = n.normalize
      n = n.reverse if point && eye && n.dot(eye - point) < 0
      n
    rescue StandardError
      nil
    end

    def to_a3(v)
      [v.x.to_f, v.y.to_f, v.z.to_f]
    end

    def dot3(a, b)
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    end

    def add3(a, b)
      [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
    end

    def sub3(a, b)
      [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
    end

    def scale3(a, k)
      [a[0] * k, a[1] * k, a[2] * k]
    end

    def len3(a)
      Math.sqrt(dot3(a, a))
    end

    def cross3(a, b)
      [a[1] * b[2] - a[2] * b[1],
       a[2] * b[0] - a[0] * b[2],
       a[0] * b[1] - a[1] * b[0]]
    end

    def norm3(v)
      m = Math.sqrt(v[0]**2 + v[1]**2 + v[2]**2)
      m < 1.0e-12 ? [0.0, 0.0, 0.0] : [v[0] / m, v[1] / m, v[2] / m]
    end

    def parallel3?(a, b)
      c = cross3(a, b)
      Math.sqrt(c[0]**2 + c[1]**2 + c[2]**2) < 1.0e-6
    end

    # A rectangular box (w x h x d, millimetre extents already converted to
    # inches) centred on `origin`, aligned to axes xaxis/yaxis. Depth is along
    # the box's local z. Returns the group.
    def box(parent, origin, w, h, d, material: nil, lid_material: nil, transform: nil)
      group = parent.add_group
      ents  = group.entities

      hw = w / 2.0
      hh = h / 2.0
      pts = [
        Geom::Point3d.new(-hw, -hh, 0),
        Geom::Point3d.new(hw, -hh, 0),
        Geom::Point3d.new(hw, hh, 0),
        Geom::Point3d.new(-hw, hh, 0)
      ]
      face = ents.add_face(pts)
      unless face
        group.erase! if group.valid?
        return nil
      end
      face.reverse! if face.normal.z < 0
      face.pushpull(d)
      group.material = material if material

      # Lid: a thin inset panel on the +Z face, built in its OWN nested group
      # so it never merges with / disturbs the body's top face. Non-fatal.
      if lid_material
        lid_group = nil
        begin
          lid_group = ents.add_group
          le = lid_group.entities
          inset = [w, h].min * 0.08
          lid = [
            Geom::Point3d.new(-hw + inset, -hh + inset, d),
            Geom::Point3d.new(hw - inset, -hh + inset, d),
            Geom::Point3d.new(hw - inset, hh - inset, d),
            Geom::Point3d.new(-hw + inset, hh - inset, d)
          ]
          lface = le.add_face(lid)
          if lface
            lface.reverse! if lface.normal.z < 0
            lface.pushpull(mm(3))
            lid_group.material = lid_material
          else
            lid_group.erase!
          end
        rescue StandardError
          lid_group.erase! if lid_group && lid_group.valid?
        end
      end

      group.transform!(transform || Geom::Transformation.new(origin))
      group
    end

    # Move `group` so its local origin sits at `origin` with local +Z pointing
    # along `zdir`.
    def orient!(group, origin, zdir)
      z = zdir.normalize
      x = z.axes[0]
      y = z.axes[1]
      t = Geom::Transformation.axes(origin, x, y, z)
      group.transform!(t)
      group
    end

    # ---- internal helpers -------------------------------------------------

    def clean_points(pts)
      out = []
      pts.each do |p|
        out << p if out.empty? || out.last.distance(p) > 1.0e-3 # SketchUp merges < 0.001"
      end
      out
    end

    def clamp(v, lo, hi)
      return lo if v < lo
      return hi if v > hi

      v
    end

    def cleanup(group)
      group.erase! if group && group.valid?
      nil
    end
  end
end
