# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Updater
  # ---------------------------------------------------------------------------
  # Self-update against GitHub Releases (works on macOS and Windows, no
  # Extension Warehouse required). Checks the latest release, compares versions,
  # and can download + install the .rbz via Sketchup.install_from_archive.
  #
  # This runs on the USER's machine and network — not the build environment.
  # ===========================================================================
  module Updater
    REPO = 'AA-EION/SKP-E-PLUMB'
    API_LATEST = "https://api.github.com/repos/#{REPO}/releases/latest".freeze
    RELEASES_URL = "https://github.com/#{REPO}/releases/latest".freeze
    DONATE_URL = 'https://www.paypal.com/donate/?business=juanesgtgt2%40gmail.com' \
                 '&no_recurring=0&item_name=Apoyo%20a%20SKP%20E-Plumb&currency_code=USD'.freeze

    module_function

    # The changelog section for a given version, read from the CHANGELOG.md that
    # ships inside the plugin (added at build time). Returns the raw markdown of
    # that version's block, or nil.
    def changelog_notes(version)
      path = File.join(__dir__, 'CHANGELOG.md')
      return nil unless File.exist?(path)

      text = File.read(path)
      text = text.force_encoding('UTF-8') if text.respond_to?(:force_encoding)
      out = []
      capture = false
      text.each_line do |ln|
        if ln =~ /^\#\#\s*\[?#{Regexp.escape(version)}\]?/
          capture = true
          next
        elsif capture && ln =~ /^\#\#\s/
          break
        end
        out << ln if capture
      end
      s = out.join.strip
      s.empty? ? nil : s
    rescue StandardError
      nil
    end

    def current_version
      SkpEPlumb::VERSION
    end

    # Fetch the latest release from GitHub. Returns a hash with :version,
    # :html_url, :rbz_url, :notes — or { error: msg }.
    def fetch_latest
      require 'net/http'
      require 'uri'
      require 'json'

      uri = URI(API_LATEST)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 6
      http.read_timeout = 6
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = "SKP-E-Plumb/#{current_version}"
      req['Accept'] = 'application/vnd.github+json'
      res = http.request(req)
      return { error: "HTTP #{res.code}" } unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body)
      asset = (data['assets'] || []).find { |a| a['name'].to_s.downcase.end_with?('.rbz') }
      {
        version: data['tag_name'].to_s.sub(/\Av/i, ''),
        html_url: data['html_url'] || RELEASES_URL,
        rbz_url: asset && asset['browser_download_url'],
        notes: data['body'].to_s
      }
    rescue StandardError => e
      { error: e.message }
    end

    # Semantic-ish version compare: 1 if a>b, -1 if a<b, 0 if equal.
    def cmp(a, b)
      pa = a.to_s.split('.').map(&:to_i)
      pb = b.to_s.split('.').map(&:to_i)
      [pa.length, pb.length].max.times do |i|
        d = (pa[i] || 0) <=> (pb[i] || 0)
        return d unless d.zero?
      end
      0
    end

    def newer?(remote, local = current_version)
      cmp(remote, local) > 0
    end

    # Check for updates. When interactive, also reports "up to date" / errors.
    def check(interactive: true)
      info = fetch_latest
      if info[:error]
        UI.messagebox("SKP E-Plumb: no se pudo verificar actualizaciones.\n#{info[:error]}") if interactive
        return
      end

      if info[:version].to_s.empty?
        UI.messagebox('SKP E-Plumb: no se encontró información de versión.') if interactive
        return
      end

      if newer?(info[:version])
        prompt_update(info)
      elsif interactive
        UI.messagebox("SKP E-Plumb está actualizado (v#{current_version}).")
      end
    end

    def prompt_update(info)
      msg = "SKP E-Plumb: hay una nueva versión disponible.\n\n" \
            "Instalada: v#{current_version}\nDisponible: v#{info[:version]}\n\n" \
            "¿Descargar e instalar ahora?\n" \
            "(Sí = instalar · No = abrir la página de descarga · Cancelar = después)"
      choice = UI.messagebox(msg, MB_YESNOCANCEL)
      case choice
      when IDYES then install(info)
      when IDNO  then UI.openURL(info[:html_url])
      end
    end

    def install(info)
      unless info[:rbz_url]
        UI.openURL(info[:html_url])
        return
      end

      path = download(info[:rbz_url])
      unless path
        UI.messagebox("No se pudo descargar el paquete. Abriendo la página de descarga…")
        UI.openURL(info[:html_url])
        return
      end

      unless Sketchup.respond_to?(:install_from_archive)
        UI.messagebox("Tu versión de SketchUp no permite instalar automáticamente.\n" \
                      "El paquete se descargó en:\n#{path}")
        UI.openURL(info[:html_url])
        return
      end

      begin
        Sketchup.install_from_archive(path)
        UI.messagebox("SKP E-Plumb v#{info[:version]} instalado.\n" \
                      'Reinicia SketchUp si algo no aparece actualizado.')
      rescue Interrupt
        nil # user cancelled the SketchUp install confirmation
      rescue StandardError => e
        UI.messagebox("No se pudo instalar automáticamente: #{e.message}\n" \
                      'Abriendo la página de descarga…')
        UI.openURL(info[:html_url])
      end
    end

    # Download a URL (following GitHub redirects) to a temp .rbz. Returns path.
    def download(url)
      require 'net/http'
      require 'uri'

      uri = URI(url)
      5.times do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 10
        http.read_timeout = 60
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = "SKP-E-Plumb/#{current_version}"
        res = http.request(req)

        if res.is_a?(Net::HTTPRedirection) && res['location']
          uri = URI(res['location'])
          next
        elsif res.is_a?(Net::HTTPSuccess)
          dir = begin
            Sketchup.temp_dir
          rescue StandardError
            require 'tmpdir'
            Dir.tmpdir
          end
          path = File.join(dir, 'SKP-E-Plumb-update.rbz')
          File.open(path, 'wb') { |f| f.write(res.body) }
          return path
        else
          return nil
        end
      end
      nil
    rescue StandardError
      nil
    end
  end
end
