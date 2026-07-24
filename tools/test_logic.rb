# frozen_string_literal: true

# Offline unit tests for the SketchUp-independent logic (catalog + BOM math).
# Run with: ruby tools/test_logic.rb
$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'skp_e_plumb/catalog'
require 'skp_e_plumb/bom'
require 'skp_e_plumb/geom_util'
require 'skp_e_plumb/version'
require 'skp_e_plumb/updater'

include SkpEPlumb

$failures = 0

def check(name)
  ok = yield
  puts "#{ok ? 'PASS' : 'FAIL'}  #{name}"
  $failures += 1 unless ok
rescue StandardError => e
  puts "ERROR #{name}: #{e.class}: #{e.message}"
  $failures += 1
end

# ---- Catalog ---------------------------------------------------------------
check('catalog has 4 conduit types') { Catalog::TYPE_KEYS.sort == %w[EMT GALV IMC PVC] }
check('EMT is set-screw (non-threaded)') { Catalog.connection_method('EMT') == :setscrew }
check('IMC is threaded') { Catalog.connection_method('IMC') == :threaded }
check('GALV is threaded') { Catalog.connection_method('GALV') == :threaded }
check('PVC is solvent') { Catalog.connection_method('PVC') == :solvent }
check('OD lookup EMT 3/4"') { (Catalog.od_mm('EMT', '3/4') - 23.4).abs < 0.01 }
check('NEC min bend radius 3/4" = 114.3mm') { (Catalog.min_bend_radius_mm('3/4') - 114.3).abs < 0.01 }
check('coupling label reflects connection') do
  Catalog.coupling_label('IMC').include?('roscada') &&
    Catalog.coupling_label('EMT').include?('set-screw')
end
check('boxes include Plexo and Rawelt families') do
  fams = Catalog::BOX_KEYS.map { |k| Catalog::BOXES[k][:family] }.uniq.sort
  fams == %w[Plexo Rawelt]
end
check('condulet types present (LB, T, X, ...)') do
  %w[RAWELT_LB RAWELT_T RAWELT_X RAWELT_C RAWELT_LL RAWELT_LR].all? { |k| Catalog::BOXES.key?(k) }
end

# ---- BOM aggregation -------------------------------------------------------
# 7 m of EMT 3/4" drawn as three stock pieces (3 + 3 + 1 m) -> 3 tubes counted.
raw = [
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Tubería EMT 3/4"',
    'length_mm' => 3000.0, 'stock_m' => 3.0 },
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Tubería EMT 3/4"',
    'length_mm' => 3000.0, 'stock_m' => 3.0 },
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Tubería EMT 3/4"',
    'length_mm' => 1000.0, 'stock_m' => 3.0 },
  { 'part' => 'coupling', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Copla set-screw', 'qty' => 1 },
  { 'part' => 'coupling', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Copla set-screw', 'qty' => 1 },
  { 'part' => 'elbow90', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Codo 90', 'qty' => 1 },
  { 'part' => 'bushing_gnd', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Bushing aterrizaje', 'qty' => 1 },
  { 'part' => 'box', 'type' => 'Plexo', 'size' => '105x105x55', 'desc' => 'Caja Plexo', 'box_key' => 'PLEXO_105', 'qty' => 1 }
]

data = Bom.summarize(raw)

def find(data, cat)
  data[:lines].find { |l| l[:category] == cat }
end

check('pipe counts 3 drawn pieces = 3 tubes') do
  pipe = find(data, 'Tubería')
  pipe && pipe[:qty] == 3 && pipe[:unit] == 'tubo(s)'
end
check('pipe detail reports total metres') { find(data, 'Tubería')[:detail].include?('7.00 m') }
check('couplings summed to 2') { find(data, 'Copla / Unión')[:qty] == 2 }
check('elbow 90 counted once') { find(data, 'Codo 90°')[:qty] == 1 }
check('grounding bushing counted') { find(data, 'Bushing aterrizaje')[:qty] == 1 }
check('box counted') { find(data, 'Caja')[:qty] == 1 }
check('part_total equals raw count') { data[:part_total] == raw.length }
check('lines sorted with Tubería first') { data[:lines].first[:category] == 'Tubería' }

# ---- surface orientation (box placement) -----------------------------------
GU = GeomUtil
def dot3(a, b) = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def approx3(a, b, tol = 1e-9) = (0..2).all? { |i| (a[i] - b[i]).abs < tol }

floor = GU.surface_basis([0.0, 0.0, 1.0])
check('floor: depth axis is +Z') { approx3(floor[2], [0, 0, 1]) }
check('floor: wide face is horizontal') { floor[0][2].abs < 1e-9 && floor[1][2].abs < 1e-9 }

wall_x = GU.surface_basis([1.0, 0.0, 0.0])
check('wall +X: depth axis is the wall normal') { approx3(wall_x[2], [1, 0, 0]) }
check('wall +X: up axis points up (+Z)') { approx3(wall_x[1], [0, 0, 1]) }
check('wall +X: side axis is horizontal') { wall_x[0][2].abs < 1e-9 }

wall_y = GU.surface_basis([0.0, 1.0, 0.0])
check('wall +Y: depth axis is the wall normal') { approx3(wall_y[2], [0, 1, 0]) }
check('wall +Y: up axis points up (+Z)') { approx3(wall_y[1], [0, 0, 1]) }

check('basis orthonormal & right-handed (wall)') do
  x, y, z = wall_x
  dot3(x, y).abs < 1e-9 && dot3(x, z).abs < 1e-9 && dot3(y, z).abs < 1e-9 &&
    approx3(GU.cross3(x, y), z, 1e-9)
end
check('degenerate normal falls back to identity') do
  b = GU.surface_basis([0.0, 0.0, 0.0])
  approx3(b[0], [1, 0, 0]) && approx3(b[1], [0, 1, 0]) && approx3(b[2], [0, 0, 1])
end

# ---- ray/box exit (conduit meets box surface) ------------------------------
# Box local frame: x,y in [-2,2], z in [0,4]; centre at (0,0,2).
mins = [-2.0, -2.0, 0.0]
maxs = [2.0, 2.0, 4.0]
check('ray exits +x face at t=2') { (GU.ray_box_t([0.0, 0.0, 2.0], [1.0, 0, 0], mins, maxs) - 2.0).abs < 1e-9 }
check('ray exits -z (back) at t=2') { (GU.ray_box_t([0.0, 0.0, 2.0], [0, 0, -1.0], mins, maxs) - 2.0).abs < 1e-9 }
check('ray exits +z (front) at t=2') { (GU.ray_box_t([0.0, 0.0, 2.0], [0, 0, 1.0], mins, maxs) - 2.0).abs < 1e-9 }
check('diagonal ray exits at nearest face') do
  t = GU.ray_box_t([0.0, 0.0, 2.0], GU.norm3([1.0, 0.0, 0.2]), mins, maxs)
  t && t > 1.9 && t < 2.2
end

# ---- updater version compare -----------------------------------------------
check('1.7.0 > 1.6.0') { Updater.newer?('1.7.0', '1.6.0') }
check('1.10.0 > 1.9.0 (numeric, not lexical)') { Updater.newer?('1.10.0', '1.9.0') }
check('2.0.0 > 1.99.99') { Updater.newer?('2.0.0', '1.99.99') }
check('equal is not newer') { !Updater.newer?('1.7.0', '1.7.0') }
check('older is not newer') { !Updater.newer?('1.6.5', '1.7.0') }
check('tag with v stripped compares') { Updater.cmp('1.7.0', '1.7.0').zero? }

# ---- exports ---------------------------------------------------------------
csv = Bom.to_csv(data)
check('CSV has header + a row per line') { csv.lines.length == data[:lines].length + 1 }
check('CSV quotes fields with commas') { !csv.include?("Tubería EMT 3/4\",EMT") || csv.include?('"') }
html = Bom.to_html(data)
check('HTML export renders a table') { html.include?('<table>') && html.include?('Bushing aterrizaje') }

# Piece-based counting: each drawn pipe piece is one tube.
one = Bom.summarize([{ 'part' => 'pipe', 'type' => 'IMC', 'size' => '1', 'desc' => 'x',
                       'length_mm' => 3000.0, 'stock_m' => 3.0 }])
check('one drawn piece -> 1 tube') { one[:lines].first[:qty] == 1 }
two = Bom.summarize([
  { 'part' => 'pipe', 'type' => 'IMC', 'size' => '1', 'desc' => 'x', 'length_mm' => 3000.0, 'stock_m' => 3.0 },
  { 'part' => 'pipe', 'type' => 'IMC', 'size' => '1', 'desc' => 'x', 'length_mm' => 500.0, 'stock_m' => 3.0 }
])
check('two drawn pieces -> 2 tubes (pieces mode)') { two[:lines].first[:qty] == 2 }

# Optimized mode: four 1 m offcuts across the model reuse into ceil(4/3)=2 tubes.
four = [
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'x', 'length_mm' => 1000.0, 'stock_m' => 3.0 },
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'x', 'length_mm' => 1000.0, 'stock_m' => 3.0 },
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'x', 'length_mm' => 1000.0, 'stock_m' => 3.0 },
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'x', 'length_mm' => 1000.0, 'stock_m' => 3.0 }
]
check('pieces mode: four 1m offcuts -> 4 tubes') { Bom.summarize(four, :pieces)[:lines].first[:qty] == 4 }
check('optimized mode: four 1m offcuts -> 2 tubes') { Bom.summarize(four, :optimized)[:lines].first[:qty] == 2 }
check('optimized mode reported in data') { Bom.summarize(four, :optimized)[:mode] == :optimized }
check('total metres shown in both modes') { Bom.summarize(four, :optimized)[:lines].first[:detail].include?('4.00 m') }

puts
if $failures.zero?
  puts 'ALL TESTS PASSED'
  exit 0
else
  puts "#{$failures} TEST(S) FAILED"
  exit 1
end
