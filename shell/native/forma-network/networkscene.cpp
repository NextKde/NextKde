#include "networkscene.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <QImage>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <cstring>

using namespace mayo;
namespace Kos::Forma {
namespace {
const Color blue = Color::hex(0x0099ff), red = Color::hex(0xff3b40), green = Color::hex(0x34c759);
Color color(const QColor &c) { return {float(c.redF()), float(c.greenF()), float(c.blueF()), float(c.alphaF())}; }
std::string utf8(const QString &s) { return s.toUtf8().toStdString(); }
QString number(double value, bool bytes = false) {
    if (!std::isfinite(value) || value < 0) return QStringLiteral("—");
    const QStringList units = bytes ? QStringList{"B", "KB", "MB", "GB", "TB"} : QStringList{"B/s", "KB/s", "MB/s", "GB/s", "TB/s"};
    int unit = 0;
    while (value >= 1024 && unit < 4) { value /= 1024; ++unit; }
    QString digits = QString::number(value, 'f', value < 10 && unit ? 2 : value < 100 && unit ? 1 : 0);
    if (digits.contains('.')) {
        while (digits.endsWith('0')) digits.chop(1);
        if (digits.endsWith('.')) digits.chop(1);
    }
    return digits + ' ' + units[unit];
}
Label text(const QString &s, float size = 12, FontWeight weight = FontWeight::Regular) {
    return Label(utf8(s)).verbatim().font(Font{size, weight, size + 3}).lineLimit(1);
}
Canvas swatch(Color c) {
    return Canvas([c](Painter &p, Rect r) { p.fillRoundedRect(r, 2.5f, c); }).frame(10, 10);
}
Label badge(const QString &s, Color c) {
    return text(s, 10, FontWeight::Semibold).foreground(Color::white()).background(c).cornerRadius(4).frame(50, 14).textAlign(TextAlign::Center);
}

// Only the visualization itself is custom. Surrounding text, stacks, rows,
// buttons, clipping, scrolling, focus and animations are original Forma controls.
class TrafficChart final : public Widget {
public:
    std::vector<double> download, upload;
    Label upper = text("0 B/s", 9), lower = text("0 B/s", 9);
    TrafficChart() { addChild(upper.node()); addChild(lower.node()); setFixedHeight(90); }
    Size measureContent(Size available) override { return {available.width, 90}; }
    void arrangeContent(const Rect &r) override {
        upper.node()->measure({r.width - 8, 12}); upper.node()->arrange({r.x + 4, r.y + 2, r.width - 8, 12});
        lower.node()->measure({r.width - 8, 12}); lower.node()->arrange({r.x + 4, r.bottom() - 14, r.width - 8, 12});
    }
    // The peak labels belong to the data, not the frame. They used to be formatted
    // inside draw(), allocating two strings on every repaint for values that change
    // at most once per sample.
    void setData(std::vector<double> down, std::vector<double> up) {
        download = std::move(down); upload = std::move(up);
        upper.setText(utf8(peak(upload))); lower.setText(utf8(peak(download)));
        invalidate();
    }
    void labelColor(Color c) { upper.foreground(c); lower.foreground(c); }
    void draw(Painter &p) override {
        const Rect r = frame();
        p.fillRoundedRect(r, 6, theme().colors.label.withAlpha(0.045f));
        p.pushClip(r, 6);
        const float middle = r.y + r.height * .5f;
        const float amplitude = r.height * .5f - 2;
        auto series = [&](const std::vector<double> &values, Color c, bool upwards) {
            const double maximum = std::max(256.0, values.empty() ? 0.0 : *std::max_element(values.begin(), values.end()));
            if (values.empty()) return;
            const int capacity = std::max(60, int(values.size()));
            const float dx = r.width / (capacity - 1);
            const int offset = capacity - int(values.size());
            for (std::size_t i = 1; i < values.size(); ++i) {
                const float x0 = r.x + (offset + i - 1) * dx;
                const float x1 = r.x + (offset + i) * dx;
                const float h0 = float(std::clamp(values[i - 1] / maximum, 0.0, 1.0)) * amplitude;
                const float h1 = float(std::clamp(values[i] / maximum, 0.0, 1.0)) * amplitude;
                const float sign = upwards ? -1.f : 1.f;
                // Pixel-wide strips avoid overlapping translucent triangle edges.
                const float pixel = 1 / p.scale();
                for (float x = x0; x < x1; x += pixel) {
                    const float h = std::lerp(h0, h1, (x - x0) / dx);
                    p.fillRect({x, upwards ? middle - h : middle, std::min(pixel, x1 - x), h}, c.withAlpha(.55f));
                }
                p.drawLine({x0, middle + sign * h0}, {x1, middle + sign * h1}, c, pixel);
            }
        };
        series(upload, red, true);
        series(download, blue, false);
        p.drawLine({r.x, middle}, {r.right(), middle}, theme().colors.separator, 1 / p.scale());
        paintChildren(p);
        p.popClip();
    }
private:
    static QString peak(const std::vector<double> &values) {
        return number(std::max(256.0, values.empty() ? 0.0 : *std::max_element(values.begin(), values.end())));
    }
};
class ConnectivityGrid final : public Widget {
public:
    // -1 unknown, 0 disconnected, 1 reachable. Resolved once per sample set
    // instead of converting a QVariantList on every frame.
    std::vector<std::int8_t> states;
    ConnectivityGrid() { setFixedHeight(30); }
    Size measureContent(Size a) override { return {a.width, 30}; }
    void setSamples(const QVariantList &samples) {
        states.clear();
        states.reserve(samples.size());
        for (const auto &sample : samples) states.push_back(sample.isNull() ? -1 : sample.toBool() ? 1 : 0);
        invalidate();
    }
    void draw(Painter &p) override {
        const auto r = frame();
        const float w = r.width / 30, h = r.height / 3;
        const Color unknown = theme().colors.label.withAlpha(.09f);
        for (int x = 0; x < 30; ++x) for (int y = 0; y < 3; ++y) {
            const int i = x * 3 + y - (90 - int(states.size()));
            const Color c = i < 0 || i >= int(states.size()) || states[i] < 0 ? unknown
                : states[i] ? green : red;
            p.fillRoundedRect({r.x + x * w, r.y + y * h, w - 1.5f, h - 1.5f}, .5f, c);
        }
    }
};
}

struct NetworkScene::Impl {
    QVariantMap translations;
    QString tr(const char *source) const { return translations.value(QString::fromUtf8(source), QString::fromUtf8(source)).toString(); }
    // Process rows are ranked by rate, so their order changes on most refreshes.
    // Keeping the nodes keyed by name+icon lets a refresh reorder and retitle the
    // same widgets instead of destroying the list, its glyph layout and the
    // per-row icon textures every two seconds.
    struct ProcessRow {
        QString name, iconSource;
        std::shared_ptr<Widget> node;
        Label download, upload;
    };
    std::shared_ptr<Widget> root;
    VStack body, processes;
    ScrollView scroll{body};
    std::map<QString, Label> fields;
    QSet<QString> statusFields;
    std::vector<ProcessRow> rows;
    Label emptyLabel = text("", 11).lineLimit(3).padding(Insets(8,0));
    QString emptyState;
    bool processesInitialized = false;
    qulonglong iconRevision = 0;
    mutable int components = -1;
    std::shared_ptr<TrafficChart> chart = std::make_shared<TrafficChart>();
    std::shared_ptr<ConnectivityGrid> grid = std::make_shared<ConnectivityGrid>();
    std::vector<std::shared_ptr<Widget>> detailNodes;
    std::vector<Label> sectionLabels;
    std::vector<std::shared_ptr<LabelView>> secondaryLabels;
    std::vector<Divider> sectionLines;
    Label processNote = text("Visible TCP connections only. Proxy traffic may be counted twice; UDP/QUIC is excluded.", 10).lineLimit(3).padding(Insets(8,0));
    Button detailsButton{"Process traffic"};
    Color ink = Color::white(), muted = Color::white(.7f);
    bool themeApplied = false;

    Label field(QString key, QString initial = "—", float size = 12, FontWeight weight = FontWeight::Regular) {
        auto label = text(initial, size, weight);
        fields.emplace(key, label);
        return label;
    }
    void section(const QString &title, const std::optional<Button> &button = {}) {
        // Stats uses 1pt tracking in section headings. Compose original Label
        // controls with the original HStack rather than a second text renderer.
        HStack label;
        label.spacing(1);
        for (const auto character : title.toUpper()) {
            auto glyph = text(QString(character), 10, FontWeight::Semibold);
            label.add(glyph); sectionLabels.push_back(glyph);
        }
        auto left = Divider().height(1), right = Divider().height(1);
        auto row = HStack({left, label, right}).spacing(8).height(30).fillWidth();
        left.node()->setParentAxis(Axis::Vertical); right.node()->setParentAxis(Axis::Vertical);
        left.foreground(Color::white(.07f)); right.foreground(Color::white(.07f));
        sectionLines.push_back(left); sectionLines.push_back(right);
        if (button) body.add(ZStack({row, HStack({Spacer(), *button}).spacing(0).fillWidth()}).height(30).fillWidth());
        else body.add(row);
    }
    void row(const QString &title, const QString &key, std::optional<Color> c = {}) {
        auto value = field(key, "—", 12, FontWeight::Semibold).textAlign(TextAlign::Trailing).width(128);
        // Forma owns row measurement and layout; Stats' compact metrics override
        // the framework's normal settings-row padding, not its implementation.
        FormRow row(utf8(title), value);
        row.node()->setPadding(Insets(0));
        row.node()->setMinSize(std::nullopt, 22);
        row.node()->setFixedHeight(22);
        row.node()->setSpacing(4);
        auto label = std::dynamic_pointer_cast<LabelView>(row.node()->children().front());
        label->setFont(Font{12, FontWeight::Regular, 15});
        label->setTextTranslationEnabled(false);
        label->setMaxSize(c ? 114 : 128, std::nullopt);
        secondaryLabels.push_back(label);
        if (c) row.node()->insertChild(0, swatch(*c).node());
        body.add(row);
    }
    void statusRow(const QString &title, const QString &key) {
        auto status = field(key, "—", 10, FontWeight::Semibold).foreground(Color::white()).background(green)
            .cornerRadius(4).frame(50, 14).textAlign(TextAlign::Center);
        auto label = text(title);
        secondaryLabels.push_back(label.node());
        statusFields.insert(key);
        body.add(HStack({label, Spacer(), status}).spacing(4).height(22).fillWidth());
    }
    ProcessRow makeRow(const QString &name, const QString &iconSource, const QImage &bitmap) {
        auto down = text("—", 11, FontWeight::Medium).textAlign(TextAlign::Trailing).width(54);
        auto up = text("—", 11, FontWeight::Medium).textAlign(TextAlign::Trailing).width(54);
        Element icon;
        if (!bitmap.isNull()) {
            auto native = ImageData::create(bitmap.width(), bitmap.height());
            std::vector<std::uint8_t> pixels(bitmap.width() * bitmap.height() * 4);
            for (int y = 0; y < bitmap.height(); ++y)
                std::memcpy(pixels.data() + y * bitmap.width() * 4, bitmap.constScanLine(y), bitmap.width() * 4);
            native->update(std::move(pixels));
            icon = Image(native).contentMode(ContentMode::Fit).frame(12,12);
        } else {
            icon = Canvas([](Painter &p, Rect r) {
                p.fillRoundedRect(r, 2, theme().colors.secondaryLabel.withAlpha(.3f));
                p.drawLine({r.x+3,r.y+4},{r.right()-3,r.y+4},theme().colors.secondaryLabel, .8f);
                p.drawLine({r.x+3,r.y+7},{r.right()-4,r.y+7},theme().colors.secondaryLabel, .8f);
            }).frame(12,12);
        }
        auto row = HStack({icon, text(name, 12).width(132), down, up}).spacing(4).height(22).fillWidth();
        return {name, iconSource, row.node(), down, up};
    }
    void syncProcesses(const QVariantList &applications, const QString &empty) {
        bool changed = applications.size() != int(rows.size())
            || (rows.empty() && empty != emptyState);
        for (int i = 0; !changed && i < int(applications.size()); ++i) {
            const auto value = applications[i].toMap();
            changed = value.value("name").toString() != rows[i].name
                || value.value("iconSource").toString() != rows[i].iconSource;
        }
        emptyState = empty;
        if (changed) {
            std::map<QString, ProcessRow> previous;
            for (auto &row : rows) previous.emplace(row.name + QChar(0x1f) + row.iconSource, std::move(row));
            std::vector<ProcessRow> next;
            next.reserve(applications.size());
            for (const auto &value : applications) {
                const auto object = value.toMap();
                const auto name = object.value("name").toString();
                const auto source = object.value("iconSource").toString();
                auto it = previous.find(name + QChar(0x1f) + source);
                if (it != previous.end()) {
                    next.push_back(std::move(it->second));
                    previous.erase(it);
                } else {
                    next.push_back(makeRow(name, source, object.value("iconImage").value<QImage>()));
                }
            }
            rows = std::move(next);
            processes.node()->clearChildren();
            for (auto &row : rows) processes.node()->addChild(row.node);
            if (rows.empty()) {
                emptyLabel.setText(utf8(empty));
                processes.node()->addChild(emptyLabel.node());
            }
            processes.node()->addChild(processNote.node());
            components = -1;
        }
        for (int i = 0; i < int(rows.size()); ++i) {
            const auto row = applications[i].toMap();
            rows[i].download.setText(utf8(number(row.value("download").toDouble())));
            rows[i].upload.setText(utf8(number(row.value("upload").toDouble())));
        }
    }
    int count(const Widget *w) const {
        int total = 1;
        for (const auto &child : w->children()) total += count(child.get());
        return total;
    }
};

NetworkScene::NetworkScene(std::function<void()> close, std::function<void()> toggle,
                           std::function<void()> refresh, std::function<void()> reset, const QVariantMap &translations)
    : d(std::make_unique<Impl>()) {
    d->translations = translations;
    d->processNote.setText(utf8(d->tr("Visible TCP connections only. Proxy traffic may be counted twice; UDP/QUIC is excluded.")));
    auto signal = Canvas([](Painter &p, Rect r) {
        for (int i = 0; i < 4; ++i) p.fillRect({r.x + i * 4, r.bottom() - 5 - i * 2, 3, float(5 + i * 2)}, theme().colors.secondaryLabel);
    }).frame(16, 16);
    auto closeButton = Button(Icon::Xmark).style(ButtonStyle::Borderless).controlSize(ControlSize::Small)
        .onClick(std::move(close)).frame(22, 22);
    auto header = HStack({signal, text(d->tr("Network"), 14, FontWeight::Semibold).textAlign(TextAlign::Center).fillWidth(), closeButton})
        .spacing(4).padding(Insets(0, 8)).height(42).fillWidth();
    auto download = d->field("download", "0", 26, FontWeight::Light).textAlign(TextAlign::Trailing);
    auto upload = d->field("upload", "0", 26, FontWeight::Light).textAlign(TextAlign::Trailing);
    auto downloadUnit = d->field("downloadUnit", "B/s", 13, FontWeight::Light);
    auto uploadUnit = d->field("uploadUnit", "B/s", 13, FontWeight::Light);
    auto down = VStack({HStack({download, downloadUnit}).spacing(3), HStack({swatch(blue), text(d->tr("Download"), 11)}).spacing(4)})
        .spacing(0).align(Alignment::Center).fillWidth();
    auto up = VStack({HStack({upload, uploadUnit}).spacing(3), HStack({swatch(red), text(d->tr("Upload"), 11)}).spacing(4)})
        .spacing(0).align(Alignment::Center).fillWidth();
    d->body.spacing(0).padding(Insets(0, 8, 8, 8)).fillWidth();
    d->body.add(HStack({down, up}).spacing(0).height(90).fillWidth());
    d->section(d->tr("Usage history")); d->body.add(d->chart);
    d->section(d->tr("Connectivity history")); d->body.add(d->grid);
    auto resetButton = Button("↻").style(ButtonStyle::Borderless).controlSize(ControlSize::Small)
        .onClick(std::move(reset)).frame(18, 20);
    d->section(d->tr("Interface"), resetButton);
    d->row(d->tr("Total upload:"), "totalUpload", red);
    d->row(d->tr("Total download:"), "totalDownload", blue);
    d->statusRow(d->tr("Status:"), "status");
    d->statusRow(d->tr("Internet connection:"), "internet");
    d->row(d->tr("Latency:"), "latency"); d->row(d->tr("Jitter:"), "jitter");
    auto refreshButton = Button("↻").style(ButtonStyle::Borderless).controlSize(ControlSize::Small)
        .onClick(refresh).frame(18, 20);
    d->section(d->tr("Interface"), refreshButton);
    d->row(d->tr("Interface:"), "interface"); d->statusRow(d->tr("Status:"), "interfaceStatus");
    d->row(d->tr("Physical address:"), "macAddress"); d->row(d->tr("Network:"), "network");
    d->section(d->tr("Address"), Button("↻").style(ButtonStyle::Borderless).controlSize(ControlSize::Small).onClick(refresh).frame(18,20));
    d->row(d->tr("Local IP:"), "localIp"); d->row(d->tr("Public IP:"), "publicIp");
    d->detailsButton.setTitle("");
    d->detailsButton.style(ButtonStyle::Borderless).controlSize(ControlSize::Small).onClick(std::move(toggle)).frame(18,20);
    d->section(d->tr("Top processes"), d->detailsButton);
    auto columnSwatch = [](Color c) { return HStack({Spacer(), swatch(c)}).spacing(0).width(54); };
    auto processCaption = text(d->tr("Process"), 10).fillWidth();
    d->secondaryLabels.push_back(processCaption.node());
    auto columns = HStack({processCaption, columnSwatch(blue), columnSwatch(red)}).height(22).spacing(4);
    d->processes.spacing(0).fillWidth();
    d->body.add(columns); d->body.add(d->processes);
    d->detailNodes = {columns.node(), d->processes.node()};
    d->scroll.fillWidth().fillHeight();
    d->root = VStack({header, d->scroll}).spacing(0).fillWidth().fillHeight().node();
}
NetworkScene::~NetworkScene() = default;
const std::shared_ptr<Widget> &NetworkScene::root() const { return d->root; }

void NetworkScene::applyTheme(const QColor &ink, const QColor &muted) {
    const Color nextInk = color(ink), nextMuted = color(muted);
    if (d->themeApplied && d->ink == nextInk && d->muted == nextMuted) return;
    d->ink = nextInk; d->muted = nextMuted; d->themeApplied = true;
    d->root->setForeground(d->ink);
    for (auto &label : d->sectionLabels) label.foreground(d->ink.withAlpha(theme().isDark() ? .3f : .38f));
    for (auto &label : d->secondaryLabels) label->setForeground(d->muted);
    for (auto &line : d->sectionLines) line.foreground(Color::black(theme().isDark() ? .12f : .08f));
    d->processNote.foreground(d->muted);
    d->chart->labelColor(d->muted);
    for (auto &[key, value] : d->fields) {
        // Status pills paint their own background and always use white ink.
        if (d->statusFields.contains(key)) continue;
        value.foreground(key.endsWith("Unit") ? d->muted : d->ink);
    }
    d->root->notifyThemeChanged();
}

void NetworkScene::applyData(const QVariantMap &data, bool details) {
    auto set = [&](const QString &key, const QString &value) { d->fields.at(key).setText(utf8(value.isEmpty() ? QStringLiteral("—") : value)); };
    auto rate = [&](const QString &key, double value) {
        const auto parts = number(value).split(' ');
        set(key, parts.value(0)); set(key + "Unit", parts.value(1));
    };
    rate("download", data.value("download").toDouble()); rate("upload", data.value("upload").toDouble());
    set("totalUpload", number(data.value("totalUpload", -1).toDouble(), true));
    set("totalDownload", number(data.value("totalDownload", -1).toDouble(), true));
    const bool connected = data.value("connected").toBool();
    const QString internet = data.value("connectivity").toString();
    for (const auto &key : {QStringLiteral("status"), QStringLiteral("interfaceStatus"), QStringLiteral("internet")}) {
        const bool known = key != "internet" || internet == "full" || internet == "limited" || internet == "none" || internet == "portal";
        const bool up = connected && (key != "internet" || internet == "full");
        set(key, known ? up ? d->tr("UP") : d->tr("DOWN") : QStringLiteral("—"));
        d->fields.at(key).foreground(Color::white()).background(known ? up ? green : red : Color::white(.16f));
    }
    for (const auto &key : {"interface", "network", "macAddress", "localIp", "publicIp", "latency", "jitter"}) set(key, data.value(key).toString());
    auto values = [&](const char *key) {
        std::vector<double> result;
        for (const auto &v : data.value(key).toList()) {
            const double x = v.toDouble(); result.push_back(std::isfinite(x) ? std::max(0.0, x) : 0);
        }
        return result;
    };
    d->chart->setData(values("downloadHistory"), values("uploadHistory"));
    d->grid->setSamples(data.value("connectivityHistory").toList());
    for (const auto &node : d->detailNodes) node->setHidden(!details);
    d->detailsButton.icon(details ? Icon::ChevronUp : Icon::ChevronDown);
    const QString emptyState = data.value("applicationsError").toString().isEmpty() ? d->tr("Sampling application traffic…") : data.value("applicationsError").toString();
    d->syncProcesses(data.value("applications").toList(), emptyState);
}
int NetworkScene::nativeComponentCount() const {
    if (d->components < 0) d->components = d->count(d->root.get());
    return d->components;
}
float NetworkScene::scrollOffset() const { return d->scroll.node()->offset().y; }
}
