# -*- mode: ruby -*-
# vi: set ft=ruby :

# =============================================================================
# dev-forge : Vagrantfile Orquestador Multi-Lenguaje y Multiplataforma
# =============================================================================

require 'fileutils'

Vagrant.configure("2") do |config|
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = false
  end

  # Directorio de caché persistente en el host para compiladores (Cargo, Go, Pip, Gradle)
  host_cache_dir = File.expand_path("~/.dev-forge/cache")
  FileUtils.mkdir_p(host_cache_dir) unless File.directory?(host_cache_dir)

  # Carga del perfil de dimensionamiento del host (generado por dev-forge tune)
  user_profile = File.expand_path("~/.dev-forge/forge-host.env")
  repo_profile = File.expand_path("config/forge-host.env", __dir__)
  host_profile = File.exist?(user_profile) ? user_profile : (File.exist?(repo_profile) ? repo_profile : nil)

  if host_profile && File.exist?(host_profile)
    File.readlines(host_profile).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")
      key, val = line.split("=", 2)
      val = val.to_s.gsub(/^["']|["']$/, '')
      ENV[key] ||= val
    end
  end

  # Detección del sistema operativo anfitrión (Host OS)
  is_darwin = (RbConfig::CONFIG['host_os'] =~ /darwin|mac os/i)
  is_windows = (RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/i)

  # Detección y normalización del teclado del host para ambas VMs
  host_kb = ENV["FORGE_HOST_KEYBOARD"].to_s.strip
  if host_kb.empty?
    if is_darwin
      mac_src = `defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleSelectedInputSources 2>/dev/null | grep 'KeyboardLayout Name' | head -n 1 | awk -F'"' '{print $4}'`.strip rescue ""
      case mac_src.downcase
      when /spanish|español/ then host_kb = "es"
      when /latin|latam/     then host_kb = "latam"
      when /british|uk/      then host_kb = "gb"
      when /french|français/ then host_kb = "fr"
      when /german|deutsch/  then host_kb = "de"
      when /italian|italiano/ then host_kb = "it"
      when /portuguese/      then host_kb = "pt"
      when /u\.s\.|us|abc/   then host_kb = "us"
      end
    else
      host_kb = `(localectl status 2>/dev/null | awk '/X11 Layout/{print $3}') || (grep '^XKBLAYOUT=' /etc/default/keyboard 2>/dev/null | cut -d'=' -f2 | tr -d '\"' | tr -d \"'\")`.strip rescue ""
    end
    host_kb = ENV["LANG"].to_s.split('_').first.downcase if host_kb.empty?
    host_kb = "es" if host_kb.empty?
  end

  case host_kb.downcase
  when "es", "es-es", "es_es"
    linux_layout = "es"
    win_lang_tag = "es-ES"
  when "us", "en", "en-us", "en_us"
    linux_layout = "us"
    win_lang_tag = "en-US"
  when "gb", "uk", "en-gb", "en_gb"
    linux_layout = "gb"
    win_lang_tag = "en-GB"
  when "latam", "es-419", "es-mx", "es_mx"
    linux_layout = "latam"
    win_lang_tag = "es-MX"
  when "fr", "fr-fr", "fr_fr"
    linux_layout = "fr"
    win_lang_tag = "fr-FR"
  when "de", "de-de", "de_de"
    linux_layout = "de"
    win_lang_tag = "de-DE"
  when "it", "it-it", "it_it"
    linux_layout = "it"
    win_lang_tag = "it-IT"
  when "pt", "pt-pt", "pt_pt"
    linux_layout = "pt"
    win_lang_tag = "pt-PT"
  when "br", "pt-br", "pt_br"
    linux_layout = "br"
    win_lang_tag = "pt-BR"
  else
    linux_layout = host_kb.split(/[-_]/).first.downcase
    win_lang_tag = host_kb.include?("-") ? host_kb : "#{linux_layout}-#{linux_layout.upcase}"
  end

  # ===========================================================================
  # Resolucion Inteligente de Boxes: Prioridad Absoluta a Custom Boxes VDI
  # ===========================================================================
  def resolve_box(devforge_box, fallback_upstream)
    override = ENV["FORGE_" + devforge_box.split('/').last.upcase.gsub('-', '_') + "_BOX"]
    return override if override && !override.empty?
    return devforge_box if ENV["FORGE_FORCE_CUSTOM_BOX"] == "1"

    box_slug = devforge_box.gsub('/', '-VAGRANTSLASH-')
    File.directory?(File.expand_path("~/.vagrant.d/boxes/#{box_slug}")) ? devforge_box : fallback_upstream
  end

  linux_box_name    = resolve_box("olorinj/dev-forge-linux", "bento/debian-12")
  windows_box_name  = resolve_box("olorinj/dev-forge-windows", "gusztavvargadr/windows-server-2022-standard-core")
  runner_box_name   = resolve_box("olorinj/dev-forge-runner", "bento/debian-12")

  is_linux_prebaked   = (linux_box_name == "olorinj/dev-forge-linux")
  is_windows_prebaked = (windows_box_name == "olorinj/dev-forge-windows")
  is_runner_prebaked  = (runner_box_name == "olorinj/dev-forge-runner")

  # ===========================================================================
  # 1. MAQUINA LINUX (Para Linux nativo y macOS cruzado con Docker)
  # ===========================================================================
  config.vm.define "forge-linux" do |linux|
    linux.vm.box = linux_box_name
    linux.vm.hostname = "forge-linux"
    # Carpeta del proyecto dev-forge y caché de compiladores
    linux.vm.synced_folder ".", "/forge", mount_options: ["dmode=775", "fmode=775"]
    linux.vm.synced_folder host_cache_dir, "/forge-cache", mount_options: ["dmode=775", "fmode=775", "uid=1000", "gid=1000"]

    linux.vm.provider "virtualbox" do |vb|
      vb.linked_clone = true
      vb.name = "FORGE-LINUX"
      vb.memory = ENV.fetch("FORGE_LINUX_MEM", "5120")
      vb.cpus = ENV.fetch("FORGE_LINUX_CPUS", "2")
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--paravirtprovider", is_darwin ? "default" : "kvm"]
      vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
      vb.customize ["storagectl", :id, "--name", "SATA Controller", "--hostiocache", "on"]
      vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"] unless is_darwin
      vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
      vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["modifyvm", :id, "--vram", "16"]
      vb.customize ["modifyvm", :id, "--accelerate3d", "off"]
      vb.customize ["modifyvm", :id, "--groups", "/DEV-FORGE"]
    end

    # Aprovisionamiento declarativo e idempotente con Ansible
    # Si la box ya esta pre-compilada, no se ejecuta en cada boot ordinario
    linux.vm.provision "ansible", run: (is_linux_prebaked ? "never" : "once") do |ansible|
      ansible.playbook = "provision/ansible/linux.yml"
      ansible.compatibility_mode = "2.0"
      ansible.extra_vars = {
        host_keyboard: linux_layout
      }
    end
  end

  # ===========================================================================
  # 2. MAQUINA WINDOWS (Para ejecutables nativos MSVC, instaladores WiX/Inno)
  # ===========================================================================
  config.vm.define "forge-windows", autostart: false do |win|
    win.vm.box = windows_box_name
    win.vm.hostname = "forge-windows"
    win.vm.boot_timeout = 1800
    win.vm.communicator = "winrm"
    win.winrm.username = "vagrant"
    win.winrm.password = "vagrant"
    win.winrm.retry_limit = 60
    win.winrm.retry_delay = 10
    # Carpeta del proyecto dev-forge y caché de compiladores
    win.vm.synced_folder ".", "c:/forge"
    win.vm.synced_folder host_cache_dir, "c:/forge-cache"

    win.vm.provider "virtualbox" do |vb|
      vb.linked_clone = true
      vb.name = "FORGE-WINDOWS"
      vb.memory = ENV.fetch("FORGE_WIN_MEM", "5120")
      vb.cpus = ENV.fetch("FORGE_WIN_CPUS", "2")
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--paravirtprovider", "hyperv"]
      vb.customize ["storagectl", :id, "--name", "SATA Controller", "--hostiocache", "on"]
      vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
      vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["modifyvm", :id, "--vram", "16"]
      vb.customize ["modifyvm", :id, "--accelerate3d", "off"]
      vb.customize ["modifyvm", :id, "--groups", "/DEV-FORGE"]
    end

    # Aprovisionamiento declarativo e idempotente con Ansible sobre WinRM
    win.vm.provision "ansible", run: (is_windows_prebaked ? "never" : "once") do |ansible|
      ansible.playbook = "provision/ansible/windows.yml"
      ansible.compatibility_mode = "2.0"
      ansible.extra_vars = {
        ansible_winrm_scheme: "http",
        ansible_winrm_server_cert_validation: "ignore",
        host_language_tag: win_lang_tag
      }
    end
  end

  # ===========================================================================
  # 3. MAQUINA RUNNER CI/CD (GitLab Runner aislado + Docker Engine)
  # ===========================================================================
  config.vm.define "forge-runner", autostart: false do |runner|
    runner.vm.box = runner_box_name
    runner.vm.hostname = "forge-runner"

    # Redireccion de puertos para servidor GitLab CE local
    runner.vm.network "forwarded_port", guest: 80, host: 8080, auto_correct: true
    runner.vm.network "forwarded_port", guest: 443, host: 8443, auto_correct: true

    # Carpeta del proyecto dev-forge y cache de compiladores
    runner.vm.synced_folder ".", "/forge", mount_options: ["dmode=775", "fmode=775"]
    runner.vm.synced_folder host_cache_dir, "/forge-cache", mount_options: ["dmode=775", "fmode=775", "uid=1000", "gid=1000"]

    runner.vm.provider "virtualbox" do |vb|
      vb.linked_clone = true
      vb.name = "FORGE-RUNNER"
      vb.memory = ENV.fetch("FORGE_RUNNER_MEM", "4096")
      vb.cpus = ENV.fetch("FORGE_RUNNER_CPUS", "4")
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--paravirtprovider", is_darwin ? "default" : "kvm"]
      vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
      vb.customize ["storagectl", :id, "--name", "SATA Controller", "--hostiocache", "on"]
      vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"] unless is_darwin
      vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
      vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["modifyvm", :id, "--vram", "16"]
      vb.customize ["modifyvm", :id, "--accelerate3d", "off"]
      vb.customize ["modifyvm", :id, "--groups", "/DEV-FORGE"]
    end

    runner.vm.provision "shell", run: (is_runner_prebaked ? "never" : "once"), path: "provision/runner/setup-runner.sh"
  end
end

