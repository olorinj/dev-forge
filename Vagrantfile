# -*- mode: ruby -*-
# vi: set ft=ruby :

# =============================================================================
# dev-forge : Vagrantfile Orquestador Multi-Lenguaje y Multiplataforma
# =============================================================================

Vagrant.configure("2") do |config|
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = false
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
      vb.memory = ENV.fetch("FORGE_LINUX_MEM", "4096")
      vb.cpus = ENV.fetch("FORGE_LINUX_CPUS", "4")
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
      vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
      vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
      vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["modifyvm", :id, "--vram", "16"]
      vb.customize ["modifyvm", :id, "--accelerate3d", "off"]
    end

    # Aprovisionamiento modular por etapas
    linux.vm.provision "shell", path: "provision/linux/00-base.sh"
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
    win.vm.box = "gusztavvargadr/visual-studio-2022-community-windows-11"
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
      vb.memory = ENV.fetch("FORGE_WIN_MEM", "8192")
      vb.cpus = ENV.fetch("FORGE_WIN_CPUS", "4")
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--paravirtprovider", "hyperv"]
      vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
      vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["modifyvm", :id, "--vram", "128"]
      vb.customize ["modifyvm", :id, "--accelerate3d", "off"]
    end

    # Aprovisionamiento modular por etapas en Windows
    win.vm.provision "shell", path: "provision/windows/00-base.ps1"
    win.vm.provision "shell", path: "provision/windows/10-msvc.ps1"
    win.vm.provision "shell", path: "provision/windows/20-rust-msvc.ps1"
    win.vm.provision "shell", path: "provision/windows/30-python.ps1"
    win.vm.provision "shell", path: "provision/windows/40-go.ps1"
    win.vm.provision "shell", path: "provision/windows/50-node.ps1"
    win.vm.provision "shell", path: "provision/windows/60-java.ps1"
    win.vm.provision "shell", path: "provision/windows/70-packagers.ps1"
  end
end

