# -*- mode: ruby -*-
# vi: set ft=ruby :

# =============================================================================
# dev-forge : Vagrantfile Orquestador Multi-Lenguaje y Multiplataforma
# =============================================================================

Vagrant.configure("2") do |config|
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = false
  end

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
  # 1. MAQUINA LINUX (Para Linux nativo, Android, y macOS cruzado con Docker)
  # ===========================================================================
  config.vm.define "forge-linux" do |linux|
    linux.vm.box = "bento/debian-12"
    linux.vm.hostname = "forge-linux"
    linux.vm.synced_folder ".", "/forge", mount_options: ["dmode=775", "fmode=775"]

    # Carpeta de workspace dinámica para el proyecto cliente si se define FORGE_WORKSPACE
    if ENV["FORGE_WORKSPACE"] && File.directory?(ENV["FORGE_WORKSPACE"])
      linux.vm.synced_folder ENV["FORGE_WORKSPACE"], "/workspace", mount_options: ["dmode=775", "fmode=775"]
    end

    linux.vm.provider "virtualbox" do |vb|
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
    end

    # Aprovisionamiento modular por etapas
    linux.vm.provision "shell", path: "provision/linux/00-base.sh", args: [linux_layout]
    linux.vm.provision "shell", path: "provision/linux/optimize-level2-recommended.sh"
    linux.vm.provision "shell", path: "provision/linux/10-rust.sh"
    linux.vm.provision "shell", path: "provision/linux/20-python.sh"
    linux.vm.provision "shell", path: "provision/linux/30-go.sh"
    linux.vm.provision "shell", path: "provision/linux/40-node.sh"
    linux.vm.provision "shell", path: "provision/linux/50-java-android.sh"
    linux.vm.provision "shell", path: "provision/linux/60-macos-cross.sh"
  end

  # ===========================================================================
  # 2. MAQUINA WINDOWS (Para ejecutables nativos MSVC, instaladores WiX/Inno)
  # ===========================================================================
  config.vm.define "forge-windows", autostart: false do |win|
    win.vm.box = "gusztavvargadr/windows-server-2022-standard-core"
    win.vm.hostname = "forge-windows"
    win.vm.boot_timeout = 1800
    win.vm.communicator = "winrm"
    win.winrm.retry_limit = 60
    win.winrm.retry_delay = 10
    win.vm.synced_folder ".", "c:/forge"

    # Carpeta de workspace dinámica para el proyecto cliente en Windows
    if ENV["FORGE_WORKSPACE"] && File.directory?(ENV["FORGE_WORKSPACE"])
      win.vm.synced_folder ENV["FORGE_WORKSPACE"], "c:/workspace"
    end

    win.vm.provider "virtualbox" do |vb|
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
    end

    # Aprovisionamiento modular por etapas en Windows
    win.vm.provision "shell", path: "provision/windows/00-base.ps1", args: ["-LanguageTag", win_lang_tag]
    win.vm.provision "shell", path: "provision/windows/optimize-level2-recommended.ps1"
    win.vm.provision "shell", path: "provision/windows/10-msvc.ps1"
    win.vm.provision "shell", path: "provision/windows/20-rust-msvc.ps1"
    win.vm.provision "shell", path: "provision/windows/30-python.ps1"
    win.vm.provision "shell", path: "provision/windows/40-go.ps1"
    win.vm.provision "shell", path: "provision/windows/50-node.ps1"
    win.vm.provision "shell", path: "provision/windows/60-java.ps1"
    win.vm.provision "shell", path: "provision/windows/70-packagers.ps1"
  end
end

