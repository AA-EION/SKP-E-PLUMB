# frozen_string_literal: true

# Geometry tests for Builder, run against tools/sketchup_stub.rb (no SketchUp).
# They check the core promises: tubes never cut through the surfaces they are
# drawn on (including corners), boxes face out of the surface and conduits end
# on the box wall. Run with: ruby tools/test_builder.rb
$LOAD_PATH.unshift(File.expand_path('..', __dir__))
require_relative 'sketchup_stub'
require 'json'

%w[version catalog codes geom_util bom settings builder].each { |f| require "skp_e_plumb/#{f}" }

include SkpEPlumb

$failures = 0
def check(name)
  ok = yield
  puts "#{ok ? 'PASS' : 'FAIL'}  #{name}"
  $failures += 1 unless ok
rescue StandardError => e
  puts "ERROR #{name}: #{e.class}: #{e.message}\n  #{e.backtrace[0, 4].join("\n  ")}"
  $failures += 1
end

# Record every tube / sleeve swept by the builder.
module Spy
  def tube_group(parent, pts, radius, **kw)
    $tubes << { pts: pts.map(&:clone), radius: radius }
    super
  end
end
GeomUtil.singleton_class.prepend(Spy)

MM = ->(v) { GeomUtil.mm(v) }
P = ->(x, y, z) { Geom::Point3d.new(MM.(x), MM.(y), MM.(z)) }

def build(pts, modes, normals, opts = {})
  $tubes = []
  model = Sketchup::Model.new
  s = { profile: 'NTC', type: 'EMT', size: '3/4', stock_m: 3.0, bend_radius_mm: 114.3,
        bend_mode: :field, termination: 'std', connection: :setscrew, segments: 12,
        terminate_start: true, terminate_end: true, pull_boxes: false, max_bend_deg: 360,
        box_key: 'STD_4X4', install: 'surface', straps: true, standoff_mm: 0, cover_mm: 5,
        wiring: { 'circuits' => 1, 'circuit' => '1F+N', 'system' => '240', 'wire_size' => '12',
                  'ground' => true, 'ground_size' => 'same', 'insulation' => 'THHN', 'profile' => 'NTC' } }
  g = Builder.build_run(model, pts, modes, s.merge(opts), normals)
  [model, g]
end

def parts(group, part)
  out = []
  walk = lambda do |ents|
    ents.each do |e|
      if e.get_attribute(Bom::DICT, 'part') == part
        out << e
      else
        walk.call(e.entities)
      end
    end
  end
  walk.call(group.entities)
  out
end

pipe_tubes = -> { $tubes.select { |t| (t[:radius] - GeomUtil.mm(23.4 / 2)).abs < 1e-9 } }
r = GeomUtil.mm(23.4 / 2)

# ---- 1. floor -> wall corner -> up the wall (surface) ------------------------
# Floor z=0 (normal +Z); wall plane x=2000 mm facing -X.
floor = [0.0, 0.0, 1.0]
wall = [-1.0, 0.0, 0.0]
_m, g = build([P.(0, 500, 0), P.(2000, 500, 0), P.(2000, 500, 1500)], nil,
              [[floor], [floor, wall], [wall]])
check('run built') { !g.nil? }
check('tube never goes into the floor or the wall (surface install)') do
  pipe_tubes.call.all? { |t| t[:pts].all? { |p| p.z >= r - 1e-6 && p.x <= MM.(2000) - r + 1e-6 } }
end
check('the bend stays in the room corner (inside corner)') do
  pipe_tubes.call.flat_map { |t| t[:pts] }.any? { |p| p.z > MM.(20) && p.x < MM.(1990) }
end

# ---- 2. over a table edge (convex corner) --------------------------------------
# Table top z=800 (normal +Z), front face x=1000 (normal +X). Region x<1000, z<800 is solid.
top = [0.0, 0.0, 1.0]
front = [1.0, 0.0, 0.0]
_m, g = build([P.(0, 0, 800), P.(1000, 0, 800), P.(1000, 0, 0)], nil,
              [[top], [top, front], [front]])
def dist_to_table(p)
  x = p.x - GeomUtil.mm(1000)
  z = p.z - GeomUtil.mm(800)
  return Math.hypot(x, z) if x.positive? && z.positive?
  return x if x.positive?
  return z if z.positive?

  -[x.abs, z.abs].min
end
check('bend over an outside corner clears the edge by the tube radius') do
  pipe_tubes.call.all? { |t| t[:pts].all? { |p| dist_to_table(p) >= r - 1e-6 } }
end

# ---- 3. embedded run inside a wall ------------------------------------------
_m, g = build([P.(0, 0, 300), P.(3000, 0, 300)], nil, [[[0.0, -1.0, 0.0]], [[0.0, -1.0, 0.0]]],
              install: 'embedded')
check('embedded tube is fully inside the wall (behind its face)') do
  pipe_tubes.call.all? { |t| t[:pts].all? { |p| p.y >= r - 1e-6 } }
end
check('embedded run has no straps') { parts(g, Bom::PART_STRAP).empty? }

# ---- 4. straps along a straight wall run ----------------------------------------
wn = [0.0, -1.0, 0.0]
_m, g = build([P.(0, 0, 1000), P.(7000, 0, 1000)], nil, [[wn], [wn]])
straps = parts(g, Bom::PART_STRAP)
check('7 m EMT run gets supports every <= 3 m + near each end') { straps.length >= 4 }

# ---- 5. box at the end of the run: mounted on the wall, conduit ends on it ---
_m, g = build([P.(0, 0, 1000), P.(2000, 0, 1000)], [nil, 'box'], [[wn], [wn]])
boxes = parts(g, Bom::PART_BOX)
check('end box created') { boxes.length == 1 }
if boxes.any?
  bt = boxes.first.transformation
  check('box cover faces out of the wall (box +Z = wall normal)') do
    z = bt.zaxis
    (z.x - wn[0]).abs < 1e-9 && (z.y - wn[1]).abs < 1e-9 && (z.z - wn[2]).abs < 1e-9
  end
  check('box back sits on the wall plane') { bt.origin.y.abs < 1e-9 }
  check('box long side follows the run (+X)') { bt.xaxis.x.abs > 0.999 }
  check('conduit stops at the box side wall') do
    last = pipe_tubes.call.last[:pts].last
    (last.x - (MM.(2000) - MM.(101) / 2)).abs < 1e-6
  end
end

# ---- 6. pull boxes by cumulative bend degrees ----------------------------------
# A zig-zag on the wall with five 90° bends: > 360° => one pull box needed.
zig = [P.(0, 0, 500), P.(1000, 0, 500), P.(1000, 0, 1500), P.(2000, 0, 1500), P.(2000, 0, 500),
       P.(3000, 0, 500), P.(3000, 0, 1500)]
_m, g = build(zig, nil, zig.map { [wn] }, pull_boxes: true, max_bend_deg: 360)
check('pull box inserted when bends exceed 360°') { parts(g, Bom::PART_BOX).length == 1 }
check('stored max bends between boxes <= 360°') { g.get_attribute(Builder::RUN_DICT, 'max_deg') <= 360.0 }
_m, g2 = build(zig, nil, zig.map { [wn] }, pull_boxes: false)
check('without pull boxes the review flags > 360°') do
  issues = Bom.review_meta(Bom.read(g2, Bom::RUN_DICT))
  issues.any? { |i| i[:msg].include?('360') }
end

# ---- 7. premade elbow naming ------------------------------------------------
_m, g = build([P.(0, 0, 500), P.(1000, 0, 500), P.(1000, 0, 1500)], [nil, 'premade', nil], [[wn], [wn], [wn]])
elbows = parts(g, Bom::PART_ELBOW)
check('premade 90° elbow counted') { elbows.length == 1 && elbows.first.get_attribute(Bom::DICT, 'angle') == 90.0 }

# ---- 8. metadata round trip + moved run -------------------------------------
meta = Builder.read_run_meta(g)
check('run metadata readable') { meta && meta[:pts].length == 3 && meta[:normals][0] == [wn] }
check('options survive (JSON)') { meta[:s][:type] == 'EMT' && meta[:s][:install] == 'surface' }
g.transformation = Geom::Transformation.new(Geom::Point3d.new(MM.(500), 0, 0))
moved = Builder.read_run_meta(g)
check('moved run is edited where it now is') { (moved[:pts][0].x - MM.(500)).abs < 1e-9 }

# ---- 9. wiring + BOM rows ----------------------------------------------------
wm = Bom.read(g, Bom::RUN_DICT)
rows = Bom.wire_rows(wm)
check('3 conductors stored (fase, neutro, tierra)') { rows.map { |x| x['role'] } == %w[Fase Neutro Tierra] }
check('RETIE colours on 240/120 V') { rows.map { |x| x['color'] } == %w[Negro Blanco Verde] }
check('fill stored') { wm['fill_pct'].to_f.positive? && wm['fill_limit'].to_f == 40.0 }

# ---- 10. BOM from the stub model -------------------------------------------
model, = build([P.(0, 0, 1000), P.(7000, 0, 1000)], [nil, 'box'], [[wn], [wn]])
data = Bom.aggregate(model)
cats = data[:lines].map { |l| l[:category] }
check('BOM has pipe, couplings, supports, box and conductors') do
  %w[Tubería Soporte Caja Conductor].all? { |c| cats.include?(c) } && cats.include?('Unión / copla')
end
check('pipe line carries product standard') { data[:lines].find { |l| l[:category] == 'Tubería' }[:std].include?('NTC 105') }

# ---- 11. legacy 1.x run metadata still loads ----------------------------------
legacy = Sketchup::Model.new.active_entities.add_group
legacy.set_attribute(Builder::RUN_DICT, 'run', true)
legacy.set_attribute(Builder::RUN_DICT, 'px', [0.0, 40.0])
legacy.set_attribute(Builder::RUN_DICT, 'py', [0.0, 0.0])
legacy.set_attribute(Builder::RUN_DICT, 'pz', [0.0, 0.0])
legacy.set_attribute(Builder::RUN_DICT, 'nx', [0.0, 0.0])
legacy.set_attribute(Builder::RUN_DICT, 'ny', [0.0, 0.0])
legacy.set_attribute(Builder::RUN_DICT, 'nz', [1.0, 1.0])
legacy.set_attribute(Builder::RUN_DICT, 'auto_box', true)
legacy.set_attribute(Builder::RUN_DICT, 'auto_box_every', 2)
lm = Builder.read_run_meta(legacy)
check('1.x run: normals migrated') { lm[:normals] == [[[0.0, 0.0, 1.0]], [[0.0, 0.0, 1.0]]] }
check('1.x run: auto box every 2 curves -> pull boxes at 180°') do
  lm[:s][:pull_boxes] == true && lm[:s][:max_bend_deg] == 180
end

# ---- 12. connect through an existing box (in one side, out the other) --------
model = Sketchup::Model.new
spec = Catalog::BOXES['STD_4X4']
box = Builder.drop_box(model, model.active_entities, P.(2000, 0, 1000), spec, 'STD_4X4',
                       Geom::Vector3d.new(*wn), Geom::Vector3d.new(1, 0, 0))
check('box snap point is on the wall') { Builder.box_surface_point(box).y.abs < 1e-9 }
check('box normal read back in world space') { Builder.box_world_normal(box) == wn }
$tubes = []
s = { type: 'EMT', size: '3/4', install: 'surface', straps: true, segments: 8 }
sp = Builder.box_surface_point(box)
run = Builder.build_run(model, [P.(0, 0, 1000), sp, P.(4000, 0, 1000)], nil, s,
                        [[wn], [], [wn]], [nil, box, nil])
xs = pipe_tubes.call.flat_map { |t| t[:pts].map(&:x) }
check('pass-through: no tube inside the box') do
  xs.none? { |x| x > MM.(2000 - 50.5) + 1e-6 && x < MM.(2000 + 50.5) - 1e-6 }
end
check('pass-through: both sides reach the box walls') do
  xs.any? { |x| (x - MM.(2000 - 50.5)).abs < 1e-6 } && xs.any? { |x| (x - MM.(2000 + 50.5)).abs < 1e-6 }
end
check('box link stored by persistent id') do
  Builder.read_run_meta(run)[:box_conns][1] == box
end

# ---- 13. supports are never placed on a bend -----------------------------------
_m, g = build([P.(0, 0, 500), P.(1200, 0, 500), P.(1200, 0, 3000)], nil, [[wn], [wn], [wn]])
bend_zone = ->(p) { (p.x - MM.(1200)).abs < MM.(115) && (p.z - MM.(500)).abs < MM.(115) }
check('supports kept off the bend') do
  rings = $tubes.select { |t| (t[:radius] - r * 1.08).abs < 1e-9 }
  rings.any? && rings.none? { |t| bend_zone.call(t[:pts][0]) }
end

# ---- 14. panel state + exports render -----------------------------------------
module UI; class HtmlDialog; end; end
require 'skp_e_plumb/ui_dialogs'
st = UIDialogs.settings_state
check('panel state serialises to JSON') { JSON.parse(UIDialogs.safe_json(st)).key?('info') }
check('panel HTML embeds the state') { UIDialogs.settings_html.include?('render(S)') }
check('panel shows fill for the default circuit') { st[:info][:fill][:pct].to_f.positive? }
check('HTML export with code review') do
  html = Bom.to_html(Bom.aggregate(model), review: [{ pid: 1, name: 'x', issues: [{ level: :error, msg: 'm' }] }])
  html.include?('Revisión normativa') && !html.include?('select_pid')
end

puts
if $failures.zero?
  puts 'ALL BUILDER TESTS PASSED'
  exit 0
else
  puts "#{$failures} BUILDER TEST(S) FAILED"
  exit 1
end
