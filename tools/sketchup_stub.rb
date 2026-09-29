# frozen_string_literal: true

# Minimal stand-in for the parts of the SketchUp Ruby API the builder uses, so
# the geometry pipeline can be exercised in CI without SketchUp. It models
# points, vectors, affine transformations, groups, attributes and materials;
# faces/follow-me are recorded, not meshed.

module Geom
  class Vector3d
    attr_reader :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      x, y, z = x if x.is_a?(Array)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def to_a = [x, y, z]
    def length = Math.sqrt(x * x + y * y + z * z)
    def +(o) = Vector3d.new(x + o.x, y + o.y, z + o.z)
    def -(o) = Vector3d.new(x - o.x, y - o.y, z - o.z)
    def dot(o) = x * o.x + y * o.y + z * o.z
    alias % dot
    def *(o) = Vector3d.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    def reverse = Vector3d.new(-x, -y, -z)
    def scale(k) = Vector3d.new(x * k, y * k, z * k)

    def normalize
      l = length
      raise ArgumentError, 'zero vector' if l.zero?

      Vector3d.new(x / l, y / l, z / l)
    end

    def angle_between(o)
      Math.acos([[normalize.dot(o.normalize), -1.0].max, 1.0].min)
    end

    def parallel?(o) = (self * o).length < 1.0e-9

    # SketchUp's arbitrary axis algorithm.
    def axes
      zz = normalize
      xx = if zz.x.abs < 1.0 / 64 && zz.y.abs < 1.0 / 64
             Vector3d.new(0, 1, 0) * zz
           else
             Vector3d.new(0, 0, 1) * zz
           end
      xx = xx.normalize
      [xx, (zz * xx).normalize, zz]
    end

    def transform(t) = t.apply_vector(self)
  end

  class Point3d
    attr_reader :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      x, y, z = x if x.is_a?(Array)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def to_a = [x, y, z]
    def clone = Point3d.new(x, y, z)

    def -(o)
      o.is_a?(Point3d) ? Vector3d.new(x - o.x, y - o.y, z - o.z) : Point3d.new(x - o.x, y - o.y, z - o.z)
    end

    def +(v) = Point3d.new(x + v.x, y + v.y, z + v.z)
    def distance(o) = (self - o).length

    def offset(v, len = nil)
      v = v.normalize.scale(len) if len
      self + v
    end

    def transform(t) = t.apply_point(self)
  end

  class Transformation
    attr_reader :m, :t # 3x3 row-major, translation

    def initialize(arg = nil)
      @m = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
      @t = [0.0, 0.0, 0.0]
      @t = arg.to_a.map(&:to_f) if arg.is_a?(Point3d) || arg.is_a?(Vector3d)
    end

    def self.from(m, t)
      tr = new
      tr.instance_variable_set(:@m, m)
      tr.instance_variable_set(:@t, t)
      tr
    end

    def self.axes(origin, xa, ya, za)
      m = [[xa.x, ya.x, za.x], [xa.y, ya.y, za.y], [xa.z, ya.z, za.z]]
      from(m, origin.to_a)
    end

    def self.rotation(center, axis, angle)
      a = axis.normalize
      c = Math.cos(angle)
      s = Math.sin(angle)
      k = 1 - c
      m = [
        [c + a.x * a.x * k, a.x * a.y * k - a.z * s, a.x * a.z * k + a.y * s],
        [a.y * a.x * k + a.z * s, c + a.y * a.y * k, a.y * a.z * k - a.x * s],
        [a.z * a.x * k - a.y * s, a.z * a.y * k + a.x * s, c + a.z * a.z * k]
      ]
      rc = mul_vec(m, center.to_a)
      from(m, [center.x - rc[0], center.y - rc[1], center.z - rc[2]])
    end

    def self.mul_vec(m, v)
      (0..2).map { |i| m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] }
    end

    def apply_point(p)
      r = Transformation.mul_vec(@m, p.to_a)
      Point3d.new(r[0] + @t[0], r[1] + @t[1], r[2] + @t[2])
    end

    def apply_vector(v) = Vector3d.new(*Transformation.mul_vec(@m, v.to_a))

    def *(o)
      m = (0..2).map { |i| (0..2).map { |j| (0..2).sum { |k| @m[i][k] * o.m[k][j] } } }
      ot = Transformation.mul_vec(@m, o.t)
      Transformation.from(m, [ot[0] + @t[0], ot[1] + @t[1], ot[2] + @t[2]])
    end

    def inverse
      a = @m
      det = a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
            a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
            a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
      inv = [
        [(a[1][1] * a[2][2] - a[1][2] * a[2][1]) / det, (a[0][2] * a[2][1] - a[0][1] * a[2][2]) / det,
         (a[0][1] * a[1][2] - a[0][2] * a[1][1]) / det],
        [(a[1][2] * a[2][0] - a[1][0] * a[2][2]) / det, (a[0][0] * a[2][2] - a[0][2] * a[2][0]) / det,
         (a[0][2] * a[1][0] - a[0][0] * a[1][2]) / det],
        [(a[1][0] * a[2][1] - a[1][1] * a[2][0]) / det, (a[0][1] * a[2][0] - a[0][0] * a[2][1]) / det,
         (a[0][0] * a[1][1] - a[0][1] * a[1][0]) / det]
      ]
      it = Transformation.mul_vec(inv, @t)
      Transformation.from(inv, it.map { |v| -v })
    end

    def identity?
      (0..2).all? { |i| (0..2).all? { |j| (@m[i][j] - (i == j ? 1 : 0)).abs < 1e-12 } } &&
        @t.all? { |v| v.abs < 1e-12 }
    end

    def origin = Point3d.new(*@t)
    def xaxis = Vector3d.new(@m[0][0], @m[1][0], @m[2][0])
    def yaxis = Vector3d.new(@m[0][1], @m[1][1], @m[2][1])
    def zaxis = Vector3d.new(@m[0][2], @m[1][2], @m[2][2])
  end

  class BoundingBox
    def initialize = @pts = []
    def add(*p) = @pts.concat(p.flatten)
  end
end

ORIGIN = Geom::Point3d.new(0, 0, 0) unless defined?(ORIGIN)

module Sketchup
  class Color
    def initialize(*rgb) = @rgb = rgb
  end

  class Material
    attr_accessor :name, :color

    def initialize(name) = @name = name
  end

  class Materials
    def initialize = @h = {}
    def [](n) = @h[n]
    def add(n) = (@h[n] = Material.new(n))
  end

  class AttributeDictionary < Hash; end

  module Attrs
    def attribute_dictionary(name, create = false)
      @dicts ||= {}
      @dicts[name] ||= AttributeDictionary.new if create
      @dicts[name]
    end

    def set_attribute(dict, key, value)
      attribute_dictionary(dict, true)[key] = value
    end

    def get_attribute(dict, key, default = nil)
      d = attribute_dictionary(dict)
      d && d.key?(key) ? d[key] : default
    end
  end

  class Edge
    def valid? = true
  end

  class Face
    attr_reader :normal, :path

    def initialize(normal) = @normal = normal
    def reverse! = (@normal = @normal.reverse)
    def pushpull(_d) = true
    def followme(path) = (@path = path)
  end

  class ComponentDefinition
    attr_reader :entities, :instances

    def initialize(owner_model)
      @entities = Entities.new(owner_model, self)
      @instances = []
    end
  end

  class Group
    include Attrs
    attr_accessor :name, :material
    attr_reader :definition, :parent, :transformation

    @@pid = 0

    def initialize(model, parent)
      @model = model
      @parent = parent
      @definition = ComponentDefinition.new(model)
      @definition.instances << self
      @transformation = Geom::Transformation.new
      @valid = true
      @pid = (@@pid += 1)
    end

    def entities = @definition.entities
    def model = @model
    def valid? = @valid
    def persistent_id = @pid
    def transform!(t) = (@transformation = t * @transformation)
    def transformation=(t)
      @transformation = t
    end

    def erase!
      @valid = false
      @parent.entities.delete(self) if @parent.respond_to?(:entities)
    end

    def bounds = Geom::BoundingBox.new
  end

  class ComponentInstance < Group; end

  class Entities
    include Enumerable

    def initialize(model, owner)
      @model = model
      @owner = owner
      @list = []
    end

    def each(&b) = @list.each(&b)
    def delete(e) = @list.delete(e)
    def length = @list.length

    def add_group
      g = Group.new(@model, @owner)
      @list << g
      g
    end

    def add_circle(_c, normal, _r, _n)
      @last_normal = normal
      [Edge.new]
    end

    def add_face(*_args) = Face.new(@last_normal || Geom::Vector3d.new(0, 0, 1))

    def add_edges(pts)
      @last_path = pts
      [Edge.new]
    end

    def erase_entities(_e) = nil
  end

  class Model
    attr_reader :entities, :materials

    def initialize
      @entities = Entities.new(self, self)
      @materials = Materials.new
    end

    def active_entities = @entities
    def raytest(*_args) = nil

    def find_entity_by_persistent_id(pid)
      find = lambda do |ents|
        ents.each do |e|
          return e if e.persistent_id == pid
          r = find.call(e.entities)
          return r if r
        end
        nil
      end
      find.call(@entities)
    end
  end

  @defaults = {}

  def self.read_default(_s, k, d) = @defaults.fetch(k, d)
  def self.write_default(_s, k, v) = (@defaults[k] = v)
  def self.active_model = (@model ||= Model.new)
end

class Numeric
  def to_l = self
end
