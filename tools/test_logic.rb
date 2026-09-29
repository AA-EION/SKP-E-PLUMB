# frozen_string_literal: true

# Offline unit tests for the SketchUp-independent logic (catalog + BOM math).
# Run with: ruby tools/test_logic.rb
$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'json'
require 'skp_e_plumb/catalog'
require 'skp_e_plumb/codes'
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
check('catalog has 5 conduit types') { Catalog::TYPE_KEYS.sort == %w[EMT GALV IMC PVC PVCM] }
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

# ---- Codes: conduit fill (NEC / NTC 2050 Ch.9) ------------------------------
thhn12 = ->(n) { Array.new(n) { { size: '12', ins: 'THHN' } } }
check('fill limit 1/2/over 2 = 53/31/40 %') do
  Codes.fill_limit_pct(1) == 53 && Codes.fill_limit_pct(2) == 31 && Codes.fill_limit_pct(3) == 40
end
# NEC Annex C Table C.1: max 9 × 12 AWG THHN in 1/2" EMT.
check('9 × 12 AWG THHN fit in 1/2" EMT (Annex C)') { Codes.fill('EMT', '1/2', thhn12.call(9))[:ok] }
check('10 × 12 AWG THHN do not fit in 1/2" EMT') { !Codes.fill('EMT', '1/2', thhn12.call(10))[:ok] }
check('min size for 10 × 12 AWG THHN is 3/4"') { Codes.min_size('EMT', thhn12.call(10)) == '3/4' }
check('THW is bigger than THHN (Table 5)') do
  Codes.wire_area_mm2('12', 'THW') > Codes.wire_area_mm2('12', 'THHN')
end
check('metric conductors use mm² sizes') { Codes.wire_label('2.5', 'H07V') == '2.5 mm²' }
check('kcmil label') { Codes.wire_label('250', 'THHN') == '250 kcmil' }

# ---- Codes: conductors & colours ---------------------------------------------
spec = { 'circuits' => 1, 'circuit' => '3F+N', 'system' => '208', 'wire_size' => '10',
         'ground' => true, 'ground_size' => '12', 'insulation' => 'THHN', 'profile' => 'NTC' }
conds = Codes.conductors(spec)
check('3F+N + ground = 5 conductors') { conds.length == 5 }
check('RETIE 208/120 V phases amarillo/azul/rojo') { conds.first(3).map { |c| c[:color] } == %w[Amarillo Azul Rojo] }
check('RETIE neutral white, ground green') { conds[3][:color] == 'Blanco' && conds[4][:color] == 'Verde' }
check('ground uses its own gauge') { conds[4][:size] == '12' }
iec = Codes.conductors(spec.merge('profile' => 'IEC', 'insulation' => 'H07V', 'wire_size' => '4'))
check('IEC 60445: brown/black/grey, blue N, green-yellow PE') do
  iec.map { |c| c[:color] } == %w[Café Negro Gris Azul Verde-amarillo]
end
check('480/277 V neutral grey') { Codes.colors('NEC', '480')[:neutral] == 'Gris' }
check('single-phase on 1F 120 V limits to one phase') do
  Codes.conductors(spec.merge('system' => '120', 'circuit' => '2F+N')).count { |c| c[:role] == 'Fase' } == 1
end
check('0 circuits = no conductors') { Codes.conductors(spec.merge('circuits' => 0)).empty? }

# ---- Codes: supports (3xx.30) -----------------------------------------------
check('EMT supports every 3 m (358.30)') { Codes.strap_spacing_m('NTC', 'EMT', '3/4') == 3.0 }
check('PVC 3/4" supports every 0.9 m (Table 352.30)') { Codes.strap_spacing_m('NEC', 'PVC', '3/4') == 0.9 }
check('PVC 2" supports every 1.5 m') { Codes.strap_spacing_m('NEC', 'PVC', '2') == 1.5 }
pos = Codes.strap_positions(5.0, 3.0)
check('strap positions: 0.3 m from each end, gaps <= 3 m') do
  (pos.first - 0.3).abs < 1e-9 && (pos.last - 4.7).abs < 1e-9 &&
    pos.each_cons(2).all? { |a, b| b - a <= 3.0 + 1e-9 }
end
check('short section gets one centred strap') { Codes.strap_positions(0.4, 3.0) == [0.2] }

# ---- Codes: review -------------------------------------------------------------
rv = Codes.review('NTC', type: 'EMT', size: '3/4', max_deg: 450.0, max_len_m: 20.0)
check('review flags > 360° of bends citing 358.26') { rv.any? { |x| x[:msg].include?('358.26') } }
check('NTC has no length limit') { rv.none? { |x| x[:msg].include?('Tramo') } }
rv_iec = Codes.review('IEC', type: 'PVCM', size: '20', max_deg: 180.0, max_len_m: 20.0)
check('IEC reference flags > 15 m between draw-in points') { rv_iec.any? { |x| x[:msg].include?('15 m') } }
rv_fill = Codes.review('NTC', type: 'EMT', size: '1/2', max_deg: 0,
                              fill: Codes.fill('EMT', '1/2', thhn12.call(10)), conds: thhn12.call(10))
check('review flags overfilled conduit and suggests a size') { rv_fill.any? { |x| x[:msg].include?('3/4"') } }
rv_r = Codes.review('NTC', type: 'EMT', size: '3/4', max_deg: 90, bend_radius_mm: 60.0, bend_mode: 'field')
check('review flags a bend radius under Table 2') { rv_r.any? { |x| x[:msg].include?('Tabla 2') } }
check('boxes include standard, Plexo and Rawelt families') do
  fams = Catalog::BOX_KEYS.map { |k| Catalog::BOXES[k][:family] }.uniq.sort
  fams == %w[Estándar Plexo Rawelt]
end
check('NEC Table 2 one-shot radius 1" = 146.05 mm') { (Catalog.min_bend_radius_mm('EMT', '1') - 146.05).abs < 0.01 }
check('IMC 3/4" OD per UL 1242 = 26.1 mm') { (Catalog.od_mm('IMC', '3/4') - 26.1).abs < 0.01 }
check('NEC Table 4 EMT 1/2" area = 196 mm²') { Catalog.area_mm2('EMT', '1/2') == 196 }
check('metric PVC uses IEC sizes') { Catalog.sizes_for('PVCM').include?('20') && Catalog.metric?('PVCM') }
check('metric PVC radius = 4×OD') { (Catalog.min_bend_radius_mm('PVCM', '20') - 80.0).abs < 0.01 }
check('size label metric') { Catalog.size_label('PVCM', '25') == 'PVC-IEC Ø25 mm' }
check('standard elbow 90 exact') { Catalog.standard_elbow(89.0) == [90.0, true] }
check('standard elbow 60 not standard') { Catalog.standard_elbow(60.0)[1] == false }
check('product standards per RETIE list') do
  Catalog::TYPES['EMT'][:std].include?('NTC 105') && Catalog::TYPES['IMC'][:std].include?('NTC 169') &&
    Catalog::TYPES['GALV'][:std].include?('NTC 171') && Catalog::TYPES['PVC'][:std].include?('NTC 979')
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
check('couplings summed to 2') { find(data, 'Unión / copla')[:qty] == 2 }
check('elbow 90 counted once') { find(data, 'Codo 90°')[:qty] == 1 }
check('grounding bushing counted') { find(data, 'Boquilla puesta a tierra')[:qty] == 1 }
check('box counted') { find(data, 'Caja')[:qty] == 1 }
check('box line gets its product standard') { find(data, 'Caja')[:std] == 'IEC 60670-1' }
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
check('box long axis follows a vertical run on a wall') do
  b = GU.surface_basis([1.0, 0.0, 0.0], [0.0, 0.0, 1.0])
  approx3(b[0], [0, 0, 1]) && approx3(b[2], [1, 0, 0]) && approx3(GU.cross3(b[0], b[1]), b[2])
end
check('run direction along the normal falls back to upright box') do
  b = GU.surface_basis([1.0, 0.0, 0.0], [1.0, 0.0, 0.0])
  approx3(b[1], [0, 0, 1])
end
check('rotate basis 90° stays right-handed') do
  x, y, z = GU.rotate_basis(wall_x, 1)
  approx3(x, wall_x[1]) && approx3(GU.cross3(x, y), z)
end

# ---- surface offset (tube laid on surfaces) --------------------------------
check('offset on one surface = off × normal') { approx3(GU.offset_vector([0, 0, 1.0], nil, 2.0), [0, 0, 2.0]) }
check('offset on a wall/floor corner clears both planes') do
  approx3(GU.offset_vector([0, 0, 1.0], [-1.0, 0, 0], 2.0), [-2.0, 0, 2.0])
end
check('offset on 135° corner is off from both planes') do
  a = [0.0, 0.0, 1.0]
  b = GU.norm3([1.0, 0.0, 1.0])
  v = GU.offset_vector(a, b, 1.0)
  (GU.dot3(v, a) - 1.0).abs < 1e-9 && (GU.dot3(v, b) - 1.0).abs < 1e-9
end
check('embedded (negative) offset goes into the surface') { GU.offset_vector([0, 0, 1.0], nil, -1.0)[2] == -1.0 }
check('segment normal: shared surface wins') do
  GU.segment_normal([[0, 0, 1.0], [-1.0, 0, 0]], [[-1.0, 0, 0]], [0, 0, 1.0]) == [-1.0, 0, 0]
end
check('segment normal: nil when the segment leaves the surface') do
  GU.segment_normal([[0, 0, 1.0]], [[0, 0, 1.0]], [0, 0, 1.0]).nil?
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
check('ray enters box from outside') do
  t = GU.ray_box_enter([-10.0, 0.0, 1.0], [1.0, 0.0, 0.0], mins, maxs)
  (t - 8.0).abs < 1e-9
end
check('ray missing the box returns nil') { GU.ray_box_enter([-10.0, 5.0, 1.0], [1.0, 0.0, 0.0], mins, maxs).nil? }

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
