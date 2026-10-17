#[cfg(feature = "gui")]
use super::theme::AppTheme;
#[cfg(feature = "gui")]
use crate::hash::{hash_string, HashResult};
#[cfg(feature = "gui")]
use eframe::egui;

#[cfg(feature = "gui")]
pub struct HashForgeApp {
    input_text: String,
    current_hash: HashResult,
    dark_mode: bool,
    status_message: Option<String>,
}

#[cfg(feature = "gui")]
impl Default for HashForgeApp {
    fn default() -> Self {
        let initial_text = "dev-forge test".to_string();
        let initial_hash = hash_string(&initial_text);
        Self {
            input_text: initial_text,
            current_hash: initial_hash,
            dark_mode: true,
            status_message: None,
        }
    }
}

#[cfg(feature = "gui")]
impl eframe::App for HashForgeApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        AppTheme::apply(ctx, self.dark_mode);

        egui::TopBottomPanel::top("top_bar").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.heading("⚡ HashForge");
                ui.label("v0.1.0");

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let theme_icon = if self.dark_mode { "☀️ Claro" } else { "🌙 Oscuro" };
                    if ui.button(theme_icon).clicked() {
                        self.dark_mode = !self.dark_mode;
                    }
                });
            });
        });

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.spacing_mut().item_spacing = egui::vec2(8.0, 10.0);

            ui.label(egui::RichText::new("Entrada de texto para hashear:").strong());
            let text_edit = ui.add(
                egui::TextEdit::multiline(&mut self.input_text)
                    .desired_width(f32::INFINITY)
                    .desired_rows(4)
                    .hint_text("Introduce cualquier texto aquí..."),
            );

            if text_edit.changed() {
                self.current_hash = hash_string(&self.input_text);
                self.status_message = None;
            }

            ui.separator();

            ui.label(egui::RichText::new("Resultados Criptográficos:").strong());

            // SHA-256
            ui.group(|ui| {
                ui.horizontal(|ui| {
                    ui.label(egui::RichText::new("SHA-256:").color(AppTheme::ACCENT_COLOR).strong());
                    if ui.button("📋 Copiar").clicked() {
                        ui.output_mut(|o| o.copied_text = self.current_hash.sha256.clone());
                        self.status_message = Some("SHA-256 copiado al portapapeles".to_string());
                    }
                });
                ui.monospace(&self.current_hash.sha256);
            });

            // MD5
            ui.group(|ui| {
                ui.horizontal(|ui| {
                    ui.label(egui::RichText::new("MD5:").color(AppTheme::ACCENT_COLOR).strong());
                    if ui.button("📋 Copiar").clicked() {
                        ui.output_mut(|o| o.copied_text = self.current_hash.md5.clone());
                        self.status_message = Some("MD5 copiado al portapapeles".to_string());
                    }
                });
                ui.monospace(&self.current_hash.md5);
            });

            if let Some(msg) = &self.status_message {
                ui.label(egui::RichText::new(msg).color(AppTheme::SUCCESS_COLOR));
            }
        });
    }
}
