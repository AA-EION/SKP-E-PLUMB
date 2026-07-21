# frozen_string_literal: true

require 'sketchup.rb'

begin
  require 'json'
rescue LoadError
  # JSON is optional; UIDialogs has a manual fallback encoder.
end

module SkpEPlumb
  # Load order matters: data -> geometry -> bom -> settings -> builder -> tools
  # -> ui -> menus.
  dir = File.dirname(__FILE__)
  %w[
    version catalog geom_util bom settings builder
    conduit_tool box_tool ui_dialogs
  ].each { |f| require File.join(dir, "#{f}.rb") }

  # ===========================================================================
  # Menu / toolbar wiring
  # ===========================================================================
  module Menus
    module_function

    ICONS = File.join(File.dirname(__FILE__), 'resources', 'icons').freeze

    def icon(base)
      # SketchUp uses two sizes. Return a hash of paths (may not exist yet).
      {
        small: File.join(ICONS, "#{base}_16.png"),
        large: File.join(ICONS, "#{base}_24.png")
      }
    end

    def apply_icon(cmd, base)
      i = icon(base)
      cmd.small_icon = i[:small] if File.exist?(i[:small])
      cmd.large_icon = i[:large] if File.exist?(i[:large])
    end

    def cmd_draw
      c = UI::Command.new('Dibujar tubería') do
        Sketchup.active_model.select_tool(ConduitTool.new)
      end
      c.tooltip = 'Dibujar tubería / canalización eléctrica'
      c.status_bar_text = 'Clic para marcar el trazado. Alt/Option cambia entre doblar tubo y codo prefabricado.'
      apply_icon(c, 'conduit')
      c
    end

    def cmd_box
      c = UI::Command.new('Colocar caja') do
        Sketchup.active_model.select_tool(BoxTool.new)
      end
      c.tooltip = 'Colocar caja (Plexo / Rawelt)'
      c.status_bar_text = 'Clic para ubicar la caja seleccionada en Ajustes.'
      apply_icon(c, 'box')
      c
    end

    def cmd_toggle
      c = UI::Command.new('Cambiar modo de curva') do
        mode = Settings.toggle_bend_mode!
        UIDialogs.refresh_settings
        Sketchup.set_status_text("Modo de curva: #{mode == :field ? 'DOBLAR TUBO' : 'CODO PREFABRICADO'}")
      end
      c.tooltip = 'Alternar doblar tubo / codo prefabricado'
      c.status_bar_text = 'Cambia cómo se resuelven las curvas al dibujar.'
      apply_icon(c, 'bend')
      c
    end

    def cmd_bom
      c = UI::Command.new('Ver BOM') { UIDialogs.show_bom }
      c.tooltip = 'Ver lista de materiales (BOM)'
      c.status_bar_text = 'Genera y muestra la lista de materiales del modelo.'
      apply_icon(c, 'bom')
      c
    end

    def cmd_export_csv
      c = UI::Command.new('Exportar BOM (CSV)') { UIDialogs.export_bom(:csv) }
      c.tooltip = 'Exportar BOM a CSV'
      c
    end

    def cmd_export_html
      c = UI::Command.new('Exportar BOM (HTML)') { UIDialogs.export_bom(:html) }
      c.tooltip = 'Exportar BOM a HTML'
      c
    end

    def cmd_settings
      c = UI::Command.new('Ajustes…') { UIDialogs.show_settings }
      c.tooltip = 'Ajustes de SKP E-Plumb'
      c.status_bar_text = 'Tipo de canalización, diámetro, tramo de stock, radio de curvatura, cajas.'
      apply_icon(c, 'settings')
      c
    end

    def cmd_about
      UI::Command.new('Acerca de…') { show_about }
    end

    def show_about
      msg = <<~TXT
        SKP E-Plumb v#{SkpEPlumb::VERSION}
        Modelador de canalizaciones eléctricas y BOM para SketchUp.

        Soporta EMT, IMC, Galvanizado (RMC) y PVC eléctrico con coplas,
        codos, curvas de campo, bushings, contratuercas y cajas
        (Plexo / Rawelt), respetando el tramo comercial del inventario.

        Licencia GPL-3.0-or-later · © 2026 AA-EION
      TXT
      UI.messagebox(msg)
    end

    def build
      menu = UI.menu('Extensions').add_submenu('SKP E-Plumb')
      menu.add_item(cmd_draw)
      menu.add_item(cmd_box)
      menu.add_item(cmd_toggle)
      menu.add_separator
      menu.add_item(cmd_bom)
      menu.add_item(cmd_export_csv)
      menu.add_item(cmd_export_html)
      menu.add_separator
      menu.add_item(cmd_settings)
      menu.add_item(cmd_about)

      toolbar = UI::Toolbar.new('SKP E-Plumb')
      toolbar.add_item(cmd_draw)
      toolbar.add_item(cmd_box)
      toolbar.add_item(cmd_toggle)
      toolbar.add_separator
      toolbar.add_item(cmd_bom)
      toolbar.add_item(cmd_settings)
      toolbar.restore
    end
  end

  unless defined?(@ui_built) && @ui_built
    Menus.build
    @ui_built = true
  end
end
