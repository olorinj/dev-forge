#!/usr/bin/env python3
"""HashForge - Python Implementation (CLI + GUI)"""
import argparse
import hashlib
import json
import os
import sys

def compute_hashes_bytes(data: bytes):
    sha256 = hashlib.sha256(data).hexdigest()
    md5 = hashlib.md5(data).hexdigest()
    return sha256, md5

def compute_hashes_string(text: str):
    return compute_hashes_bytes(text.encode("utf-8"))

def compute_hashes_file(path: str):
    with open(path, "rb") as f:
        return compute_hashes_bytes(f.read())

def print_result(source: str, sha256: str, md5: str, as_json: bool):
    if as_json:
        print(json.dumps({"source": source, "sha256": sha256, "md5": md5}))
    else:
        print("==================================================")
        print("  HashForge (Python) - Resultados de Hashing")
        print("==================================================")
        print(f"  Fuente:  {source}")
        print(f"  SHA-256: {sha256}")
        print(f"  MD5:     {md5}")
        print("==================================================")

def launch_gui():
    try:
        import tkinter as tk
        from tkinter import ttk, messagebox
    except ImportError:
        print("Error: tkinter no está disponible para interfaz gráfica.")
        sys.exit(1)

    root = tk.Tk()
    root.title("HashForge (Python)")
    root.geometry("520x360")
    root.minsize(400, 300)

    # Estilo
    style = ttk.Style()
    style.theme_use("clam")

    main_frame = ttk.Frame(root, padding="15")
    main_frame.pack(fill=tk.BOTH, expand=True)

    ttk.Label(main_frame, text="⚡ HashForge (Python)", font=("Helvetica", 14, "bold")).pack(anchor=tk.W, pady=(0, 10))
    ttk.Label(main_frame, text="Texto a hashear:").pack(anchor=tk.W)

    text_entry = tk.Text(main_frame, height=4, width=50)
    text_entry.pack(fill=tk.X, pady=(2, 10))
    text_entry.insert("1.0", "dev-forge test")

    sha_var = tk.StringVar()
    md5_var = tk.StringVar()

    def update_hashes(event=None):
        content = text_entry.get("1.0", tk.END).rstrip("\n")
        s, m = compute_hashes_string(content)
        sha_var.set(s)
        md5_var.set(m)

    text_entry.bind("<KeyRelease>", update_hashes)

    # Resultados
    ttk.Label(main_frame, text="SHA-256:").pack(anchor=tk.W)
    sha_entry = ttk.Entry(main_frame, textvariable=sha_var, state="readonly", font=("Courier", 10))
    sha_entry.pack(fill=tk.X, pady=(2, 8))

    ttk.Label(main_frame, text="MD5:").pack(anchor=tk.W)
    md5_entry = ttk.Entry(main_frame, textvariable=md5_var, state="readonly", font=("Courier", 10))
    md5_entry.pack(fill=tk.X, pady=(2, 10))

    btn_frame = ttk.Frame(main_frame)
    btn_frame.pack(fill=tk.X, pady=5)

    def copy_sha():
        root.clipboard_clear()
        root.clipboard_append(sha_var.get())
        messagebox.showinfo("Copiado", "SHA-256 copiado al portapapeles")

    def copy_md5():
        root.clipboard_clear()
        root.clipboard_append(md5_var.get())
        messagebox.showinfo("Copiado", "MD5 copiado al portapapeles")

    ttk.Button(btn_frame, text="Copiar SHA-256", command=copy_sha).pack(side=tk.LEFT, padx=(0, 5))
    ttk.Button(btn_frame, text="Copiar MD5", command=copy_md5).pack(side=tk.LEFT)

    update_hashes()
    root.mainloop()

def main():
    parser = argparse.ArgumentParser(description="HashForge (Python) - Calculador Criptográfico Multiplataforma")
    parser.add_argument("-s", "--string", help="Calcula los hashes SHA-256 y MD5 del texto")
    parser.add_argument("-f", "--file", help="Calcula los hashes SHA-256 y MD5 del archivo")
    parser.add_argument("-j", "--json", action="store_true", help="Formatea la salida en JSON")
    parser.add_argument("-g", "--gui", action="store_true", help="Inicia la interfaz gráfica")

    args = parser.parse_args()

    if args.string:
        s, m = compute_hashes_string(args.string)
        print_result(args.string, s, m, args.json)
        return

    if args.file:
        s, m = compute_hashes_file(args.file)
        print_result(args.file, s, m, args.json)
        return

    if args.gui:
        launch_gui()
        return

    # Si se ejecuta sin argumentos
    has_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY") or sys.platform == "win32")
    if has_display and sys.stdin.isatty():
        try:
            launch_gui()
            return
        except Exception:
            pass

    # Demostración CLI
    s, m = compute_hashes_string("dev-forge test")
    print_result("dev-forge test", s, m, args.json)

if __name__ == "__main__":
    main()

