#[cfg(feature = "gui")]
use eframe::egui::{Color32, Visuals};

#[cfg(feature = "gui")]
pub struct AppTheme;

#[cfg(feature = "gui")]
impl AppTheme {
    pub const ACCENT_COLOR: Color32 = Color32::from_rgb(0, 180, 216);
    pub const BACKGROUND_DARK: Color32 = Color32::from_rgb(24, 26, 31);
    pub const SUCCESS_COLOR: Color32 = Color32::from_rgb(76, 175, 80);

    pub fn apply(ctx: &eframe::egui::Context, dark_mode: bool) {
        let mut visuals = if dark_mode {
            Visuals::dark()
        } else {
            Visuals::light()
        };

        visuals.selection.bg_fill = Self::ACCENT_COLOR;
        ctx.set_visuals(visuals);
    }
}
