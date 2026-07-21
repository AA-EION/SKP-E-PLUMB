# frozen_string_literal: true

# Offline unit tests for the SketchUp-independent logic (catalog + BOM math).
# Run with: ruby tools/test_logic.rb
$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'skp_e_plumb/catalog'
require 'skp_e_plumb/bom'

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
# 7 m of EMT 3/4" from two segments, 3 m stock -> ceil(7/3) = 3 tubes.
raw = [
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Tubería EMT 3/4"',
    'length_mm' => 4000.0, 'stock_m' => 3.0 },
  { 'part' => 'pipe', 'type' => 'EMT', 'size' => '3/4', 'desc' => 'Tubería EMT 3/4"',
    'length_mm' => 3000.0, 'stock_m' => 3.0 },
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

check('pipe rolls up to 3 tubes (7m / 3m stock)') do
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

# ---- exports ---------------------------------------------------------------
csv = Bom.to_csv(data)
check('CSV has header + a row per line') { csv.lines.length == data[:lines].length + 1 }
check('CSV quotes fields with commas') { !csv.include?("Tubería EMT 3/4\",EMT") || csv.include?('"') }
html = Bom.to_html(data)
check('HTML export renders a table') { html.include?('<table>') && html.include?('Bushing aterrizaje') }

# Edge case: exactly one stock length -> 1 tube, no rounding surprise.
one = Bom.summarize([{ 'part' => 'pipe', 'type' => 'IMC', 'size' => '1', 'desc' => 'x',
                       'length_mm' => 3000.0, 'stock_m' => 3.0 }])
check('exactly 3m with 3m stock -> 1 tube') { one[:lines].first[:qty] == 1 }
tiny = Bom.summarize([{ 'part' => 'pipe', 'type' => 'IMC', 'size' => '1', 'desc' => 'x',
                        'length_mm' => 3001.0, 'stock_m' => 3.0 }])
check('3.001m with 3m stock -> 2 tubes') { tiny[:lines].first[:qty] == 2 }

puts
if $failures.zero?
  puts 'ALL TESTS PASSED'
  exit 0
else
  puts "#{$failures} TEST(S) FAILED"
  exit 1
end
