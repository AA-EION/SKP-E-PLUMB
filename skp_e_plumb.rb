# frozen_string_literal: true
#
# SKP E-Plumb - Electrical Conduit Modeler & BOM for SketchUp
# Copyright (C) 2026  AA-EION
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# ---------------------------------------------------------------------------
# This is the SketchUp extension *registration* file. It must live at the
# top level of the .rbz next to the "skp_e_plumb" folder that holds the code.
# ---------------------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'

module SkpEPlumb
  # Absolute path to this file's directory (the plugin root inside Plugins/).
  PLUGIN_ROOT = File.dirname(__FILE__).freeze
  PLUGIN_DIR  = File.join(PLUGIN_ROOT, 'skp_e_plumb').freeze

  # Single source of truth for the version (shown in the Extension Manager).
  require File.join(PLUGIN_DIR, 'version.rb')

  # Human facing metadata --------------------------------------------------
  EXT_NAME    = 'SKP E-Plumb — Electrical Conduit & BOM'
  EXT_VERSION = VERSION
  EXT_CREATOR = 'AA-EION'
  EXT_COPYRIGHT = '© 2026 AA-EION — GPL-3.0-or-later'
  EXT_DESCRIPTION =
    'Draw electrical conduit runs (EMT, IMC, RMC, PVC, metric PVC) laid on ' \
    'walls, floors and ceilings with correct couplings, elbows, bends, ' \
    'bushings, supports, boxes and conductors; check them against NTC 2050 + ' \
    'RETIE, NEC or IEC 60364 and generate a Bill of Materials.'

  unless defined?(@loaded) && @loaded
    loader = File.join(PLUGIN_DIR, 'main.rb')

    extension = SketchupExtension.new(EXT_NAME, loader)
    extension.version     = EXT_VERSION
    extension.creator     = EXT_CREATOR
    extension.copyright   = EXT_COPYRIGHT
    extension.description = EXT_DESCRIPTION

    Sketchup.register_extension(extension, true)
    @loaded = true
  end
end
