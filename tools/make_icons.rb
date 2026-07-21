# frozen_string_literal: true

# Generates the toolbar/menu PNG icons for SKP E-Plumb with a tiny, dependency
# free PNG encoder (Zlib is in the stdlib). Run: ruby tools/make_icons.rb
require 'zlib'

OUT = File.expand_path('../skp_e_plumb/resources/icons', __dir__)

# Simple RGBA canvas.
class Canvas
  attr_reader :w, :h

  def initialize(w, h)
    @w = w
    @h = h
    @px = Array.new(w * h) { [0, 0, 0, 0] }
  end

  def set(x, y, rgba)
    return if x.negative? || y.negative? || x >= @w || y >= @h

    @px[y * @w + x] = rgba
  end

  def fill_rect(x0, y0, x1, y1, rgba)
    (y0..y1).each { |y| (x0..x1).each { |x| set(x, y, rgba) } }
  end

  # Rounded rectangle background.
  def round_rect(x0, y0, x1, y1, r, rgba)
    (y0..y1).each do |y|
      (x0..x1).each do |x|
        # skip the four rounded corners
        next if corner_out?(x, y, x0, y0, x1, y1, r)

        set(x, y, rgba)
      end
    end
  end

  def corner_out?(x, y, x0, y0, x1, y1, r)
    cx = if x < x0 + r then x0 + r elsif x > x1 - r then x1 - r else x end
    cy = if y < y0 + r then y0 + r elsif y > y1 - r then y1 - r else y end
    dx = x - cx
    dy = y - cy
    dx * dx + dy * dy > r * r
  end

  def disc(cx, cy, rad, rgba)
    ((cy - rad)..(cy + rad)).each do |y|
      (((cx - rad))..(cx + rad)).each do |x|
        dx = x - cx
        dy = y - cy
        set(x, y, rgba) if dx * dx + dy * dy <= rad * rad
      end
    end
  end

  def line(x0, y0, x1, y1, rgba, thick = 1)
    x0 = x0.round; y0 = y0.round; x1 = x1.round; y1 = y1.round
    dx = (x1 - x0).abs
    dy = -(y1 - y0).abs
    sx = x0 < x1 ? 1 : -1
    sy = y0 < y1 ? 1 : -1
    err = dx + dy
    loop do
      thick.times { |ox| thick.times { |oy| set(x0 + ox, y0 + oy, rgba) } }
      break if x0 == x1 && y0 == y1

      e2 = 2 * err
      if e2 >= dy
        err += dy
        x0 += sx
      end
      if e2 <= dx
        err += dx
        y0 += sy
      end
    end
  end

  def ring(cx, cy, rad, inner, rgba)
    (((cy - rad))..(cy + rad)).each do |y|
      (((cx - rad))..(cx + rad)).each do |x|
        dx = x - cx
        dy = y - cy
        d = dx * dx + dy * dy
        set(x, y, rgba) if d <= rad * rad && d >= inner * inner
      end
    end
  end

  def to_png
    raw = +''.b
    @h.times do |y|
      raw << 0.chr # filter: none
      @w.times do |x|
        r, g, b, a = @px[y * @w + x]
        raw << [r, g, b, a].pack('C4')
      end
    end
    idat = Zlib::Deflate.deflate(raw)

    png = +"\x89PNG\r\n\x1A\n".b
    png << chunk('IHDR', [@w, @h, 8, 6, 0, 0, 0].pack('N2C5'))
    png << chunk('IDAT', idat)
    png << chunk('IEND', ''.b)
    png
  end

  def chunk(type, data)
    body = type.b + data.b
    [body.bytesize - type.bytesize].pack('N') + body + [Zlib.crc32(body)].pack('N')
  end
end

WHITE = [255, 255, 255, 255].freeze

THEMES = {
  'conduit'  => [43, 108, 176, 255],
  'box'      => [44, 122, 123, 255],
  'bend'     => [76, 81, 191, 255],
  'bom'      => [47, 133, 90, 255],
  'settings' => [74, 85, 104, 255],
  'edit'     => [200, 120, 40, 255]
}.freeze

def glyph(canvas, name, s)
  # s = scale factor (size / 24.0)
  u = ->(v) { (v * s).round }
  case name
  when 'conduit'
    # horizontal pipe (capsule) with two rings (couplings)
    canvas.fill_rect(u.call(3), u.call(10), u.call(21), u.call(14), WHITE)
    canvas.fill_rect(u.call(8), u.call(8), u.call(9), u.call(16), THEMES['conduit'])
    canvas.fill_rect(u.call(15), u.call(8), u.call(16), u.call(16), THEMES['conduit'])
  when 'box'
    canvas.fill_rect(u.call(5), u.call(5), u.call(19), u.call(19), WHITE)
    canvas.fill_rect(u.call(8), u.call(8), u.call(16), u.call(16), THEMES['box'])
  when 'bend'
    # L-shaped conduit
    canvas.fill_rect(u.call(6), u.call(4), u.call(10), u.call(16), WHITE)
    canvas.fill_rect(u.call(6), u.call(14), u.call(20), u.call(18), WHITE)
  when 'bom'
    # list rows
    [6, 11, 16].each do |y|
      canvas.fill_rect(u.call(5), u.call(y), u.call(7), u.call(y + 2), WHITE)
      canvas.fill_rect(u.call(9), u.call(y), u.call(19), u.call(y + 2), WHITE)
    end
  when 'settings'
    canvas.ring(u.call(12), u.call(12), u.call(8), u.call(4), WHITE)
    canvas.disc(u.call(12), u.call(12), u.call(2), WHITE)
  when 'edit'
    # centreline with square anchors (edit-by-anchors)
    nodes = [[5, 16], [11, 8], [15, 15], [19, 7]]
    thick = [(1.5 * s).round, 1].max
    nodes.each_cons(2) do |(ax, ay), (bx, by)|
      canvas.line(u.call(ax), u.call(ay), u.call(bx), u.call(by), WHITE, thick)
    end
    nodes.each do |(px, py)|
      canvas.fill_rect(u.call(px) - thick, u.call(py) - thick,
                       u.call(px) + thick, u.call(py) + thick, WHITE)
    end
  end
end

def make(name, size)
  c = Canvas.new(size, size)
  s = size / 24.0
  m = (size * 0.08).round
  c.round_rect(m, m, size - 1 - m, size - 1 - m, (size * 0.18).round, THEMES[name])
  glyph(c, name, s)
  File.binwrite(File.join(OUT, "#{name}_#{size}.png"), c.to_png)
end

require 'fileutils'
FileUtils.mkdir_p(OUT)
THEMES.each_key do |name|
  make(name, 16)
  make(name, 24)
end
puts "Icons written to #{OUT}"
Dir[File.join(OUT, '*.png')].sort.each { |f| puts "  #{File.basename(f)} (#{File.size(f)} B)" }
