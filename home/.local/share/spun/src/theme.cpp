#include "theme.h"
#include <QGuiApplication>
#include <QColor>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPalette>
#include <QRegularExpression>
#include <cmath>
#include <array>
#include <algorithm>

static QString read(const QString &path) {
  QFile file(path);
  return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll())
                                        : QString();
}
static QColor mix(QColor a, QColor b, qreal t) {
  return QColor::fromRgbF(a.redF() * (1 - t) + b.redF() * t,
                          a.greenF() * (1 - t) + b.greenF() * t,
                          a.blueF() * (1 - t) + b.blueF() * t);
}
static double contrast(QColor a, QColor b) {
  const auto luminance = [](QColor c) {
    const auto linear = [](double x) { return x <= .04045 ? x / 12.92 : std::pow((x + .055) / 1.055, 2.4); };
    return .2126 * linear(c.redF()) + .7152 * linear(c.greenF()) + .0722 * linear(c.blueF());
  };
  const auto first = luminance(a), second = luminance(b);
  return (std::max(first, second) + .05) / (std::min(first, second) + .05);
}
static QColor supportingText(QColor fg, QColor bg, QColor card, QColor accent) {
  const std::array surfaces{bg, card, mix(card, fg, .07), mix(card, accent, .13)};
  // Resolve this once per palette update, never per frame. Preserve the theme's
  // foreground hue while reducing muting when small text needs more contrast.
  for (int step = 32; step >= 0; --step) {
    const auto candidate = mix(fg, bg, step / 100.);
    if (std::all_of(surfaces.begin(), surfaces.end(), [&](QColor surface) { return contrast(candidate, surface) >= 4.5; }))
      return candidate;
  }
  return fg;
}
Theme::Theme(const QString &configRoot, const QString &stateRoot,
             QObject *parent)
    : QObject(parent), m_config(configRoot), m_state(stateRoot) {
  m_debounce.setSingleShot(true);
  m_debounce.setInterval(90);
  connect(&m_watcher, &QFileSystemWatcher::fileChanged, this,
          [this] { m_debounce.start(); });
  connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this,
          [this] { m_debounce.start(); });
  connect(&m_debounce, &QTimer::timeout, this, &Theme::reload);
  reload();
}
void Theme::watch() {
  // Watch parent directories too: generated files are often atomically
  // replaced.
  QStringList paths{m_config,
                    m_config + "/gtk-4.0",
                    m_config + "/gtk-4.0/noctalia.css",
                    m_config + "/noctalia",
                    m_config + "/noctalia/config.toml",
                    m_state,
                    m_state + "/noctalia",
                    m_state + "/noctalia/settings.toml",
                    // Caelestia: wallpaper scheme and shell appearance
                    m_state + "/caelestia",
                    m_state + "/caelestia/scheme.json",
                    m_config + "/caelestia",
                    m_config + "/caelestia/shell.json"};
  for (const auto &path : paths)
    if (QFileInfo::exists(path) && !m_watcher.files().contains(path) &&
        !m_watcher.directories().contains(path))
      m_watcher.addPath(path);
}
void Theme::reload() {
  watch();
  const auto previous = m_colors;
  const auto oldFont = m_font;
  const qreal oldRadius = m_radius, oldMotion = m_motion;
  // Caelestia shell: Material You scheme generated from the wallpaper. When it is
  // present it wins over Noctalia, and the font/rounding follow shell.json.
  const auto scheme = QJsonDocument::fromJson(read(m_state + "/caelestia/scheme.json").toUtf8())
                          .object().value("colours").toObject();
  if (!scheme.isEmpty()) {
    const auto colour = [&](const char *key, const char *fallback) {
      const QString hex = scheme.value(key).toString();
      return hex.size() == 6 ? QColor("#" + hex) : QColor(fallback);
    };
    if (scheme.contains("surface") && scheme.contains("onSurface") && scheme.contains("primary")) {
      const QColor bg = colour("surface", "#191919"), fg = colour("onSurface", "#ededed"),
                   card = colour("surfaceContainer", "#262626"), accent = colour("primary", "#b8c4cf");
      m_colors = {{"surface", bg}, {"text", fg}, {"card", card}, {"accent", accent},
                  {"onAccent", colour("onPrimary", "#253440")},
                  {"muted", supportingText(fg, bg, card, accent)},
                  {"outline", colour("outlineVariant", "#474747")},
                  {"hover", mix(card, fg, .07)}, {"pressed", mix(card, fg, .13)},
                  {"error", colour("error", "#ffb4ab")}};
    }
    const auto look = QJsonDocument::fromJson(read(m_config + "/caelestia/shell.json").toUtf8())
                          .object().value("appearance").toObject();
    const QString family = look.value("font").toObject().value("body").toObject().value("family").toString();
    m_font = family.isEmpty() ? "Rubik" : family;  // Caelestia's default body font
    m_radius = qBound(0., look.value("rounding").toObject().value("scale").toDouble(1), 2.);
    const auto anim = look.value("anim").toObject().value("durations").toObject();
    // Caelestia scales durations (bigger = slower); Spun scales speed
    m_motion = anim.contains("scale") ? qBound(.1, 1. / qMax(.01, anim.value("scale").toDouble(1)), 3.) : 1;
    if (previous != m_colors || oldFont != m_font || oldRadius != m_radius || oldMotion != m_motion)
      applyPalette();
    return;
  }
  QMap<QString, QColor> tokens;
  const QString css = read(m_config + "/gtk-4.0/noctalia.css");
  static const QRegularExpression expression(
      "@define-color\\s+(\\w+)\\s+(#[0-9a-fA-F]{6})\\s*;");
  auto matches = expression.globalMatch(css);
  while (matches.hasNext()) {
    const auto match = matches.next();
    tokens.insert(match.captured(1), QColor(match.captured(2)));
  }
  // Keep the last complete palette while Noctalia writes/regenerates its
  // export.
  const bool complete = tokens.contains("window_bg_color") &&
                        tokens.contains("window_fg_color") &&
                        tokens.contains("accent_bg_color") &&
                        tokens.contains("accent_fg_color") &&
                        tokens.contains("card_bg_color");
  if (complete || m_colors.isEmpty()) {
    QColor bg = tokens.value("window_bg_color", QColor("#191919"));
    QColor fg = tokens.value("window_fg_color", QColor("#ededed"));
    QColor card = tokens.value("card_bg_color", QColor("#262626"));
    m_colors = {
        {"surface", bg},
        {"text", fg},
        {"card", card},
        {"accent", tokens.value("accent_bg_color", QColor("#b8c4cf"))},
        {"onAccent", tokens.value("accent_fg_color", QColor("#253440"))},
        {"muted", supportingText(fg, bg, card, tokens.value("accent_bg_color", QColor("#b8c4cf")))},
        {"outline", mix(card, fg, .18)},
        {"hover", mix(card, fg, .07)},
        {"pressed", mix(card, fg, .13)},
        {"error", tokens.value("error_bg_color", QColor("#ffb4ab"))}};
  }
  m_font = "Adwaita Sans";
  m_radius = m_motion = 1;
  bool animations = true;
  static const QRegularExpression setting("^(\\w+)\\s*=\\s*(.+)$");
  for (const auto &path : QStringList{m_config + "/noctalia/config.toml",
                                      m_state + "/noctalia/settings.toml"}) {
    QString section;
    for (QString line : read(path).split('\n')) {
      line = line.trimmed();
      if (line.startsWith('[')) {
        section = line;
        continue;
      }
      // Other Noctalia sections cannot affect Spun. Compile the shared parser
      // once and only match settings in the two sections consumed below.
      if (section != "[shell]" && section != "[shell.animation]")
        continue;
      auto match = setting.match(line);
      if (!match.hasMatch())
        continue;
      const QString key = match.captured(1),
                    value = match.captured(2).split('#').first().trimmed();
      if (section == "[shell]" && key == "font_family" &&
          value.startsWith('"') && value.endsWith('"'))
        m_font = value.mid(1, value.size() - 2);
      bool ok = false;
      qreal number = value.toDouble(&ok);
      if (section == "[shell]" && key == "corner_radius_scale" && ok)
        m_radius = qBound(0., number, 2.);
      if (section == "[shell.animation]" && key == "speed" && ok)
        m_motion = qBound(.1, number, 3.);
      if (section == "[shell.animation]" && key == "enabled")
        animations = value != "false";
    }
  }
  if (!animations)
    m_motion = 0;
  if (previous != m_colors || oldFont != m_font || oldRadius != m_radius ||
      oldMotion != m_motion)
    applyPalette();
}
void Theme::applyPalette() {
  {
    QPalette palette = qApp->palette();
    palette.setColor(QPalette::Window, m_colors["surface"].value<QColor>());
    palette.setColor(QPalette::WindowText, m_colors["text"].value<QColor>());
    palette.setColor(QPalette::Base, m_colors["surface"].value<QColor>());
    palette.setColor(QPalette::Text, m_colors["text"].value<QColor>());
    palette.setColor(QPalette::Button, m_colors["card"].value<QColor>());
    palette.setColor(QPalette::ButtonText, m_colors["text"].value<QColor>());
    palette.setColor(QPalette::Highlight, m_colors["accent"].value<QColor>());
    palette.setColor(QPalette::HighlightedText,
                     m_colors["onAccent"].value<QColor>());
    palette.setColor(QPalette::ToolTipBase, m_colors["card"].value<QColor>());
    palette.setColor(QPalette::ToolTipText, m_colors["text"].value<QColor>());
    qApp->setPalette(palette);
    emit changed();
  }
}
