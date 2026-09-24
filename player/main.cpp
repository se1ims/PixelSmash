// Qt media player.
//
// Build: see CMakeLists.txt in the same directory.
#include <QDebug>
#include <QAction>
#include <QApplication>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QElapsedTimer>
#include <QFileDialog>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QLabel>
#include <QMainWindow>
#include <QMenuBar>
#include <QMimeData>
#include <QPainter>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSlider>
#include <QStatusBar>
#include <QStyle>
#include <QToolButton>
#include <QVBoxLayout>
#include <QWidget>

#include <functional>
#include <signal.h>

// ---------------------------------------------------------------------------
// VideoWidget — displays a frame, or a play overlay when nothing is loaded.
// ---------------------------------------------------------------------------

class VideoWidget : public QWidget {
public:
    std::function<void()> onDoubleClick;
    std::function<void()> onClick;

    explicit VideoWidget(QWidget *parent = nullptr) : QWidget(parent) {
        setMinimumSize(320, 180);
        setAutoFillBackground(true);
        QPalette pal = palette();
        pal.setColor(QPalette::Window, Qt::black);
        setPalette(pal);
    }

    void setFrame(const QImage &img) {
        frame = img;
        showOverlay = false;
        update();
    }

    void clearFrame() {
        frame = QImage();
        showOverlay = true;
        update();
    }

    void setCaption(const QString &c) {
        caption = c;
        update();
    }

protected:
    void mouseReleaseEvent(QMouseEvent *) override { if (onClick) onClick(); }
    void mouseDoubleClickEvent(QMouseEvent *) override {
        if (onDoubleClick) onDoubleClick();
    }

    void paintEvent(QPaintEvent *) override {
        QPainter p(this);
        p.fillRect(rect(), Qt::black);

        if (!frame.isNull()) {
            QSize target = frame.size().scaled(size(), Qt::KeepAspectRatio);
            QRect dst(QPoint((width()  - target.width())  / 2,
                             (height() - target.height()) / 2),
                      target);
            p.drawImage(dst, frame);
            return;
        }

        if (!showOverlay) return;

        p.setRenderHint(QPainter::Antialiasing);
        const int r = 44;
        QPoint c = rect().center();
        QRect circle(c.x() - r, c.y() - r, r * 2, r * 2);

        p.setPen(QPen(QColor(255, 255, 255, 60), 2));
        p.setBrush(QColor(255, 255, 255, 18));
        p.drawEllipse(circle);

        QPolygon tri;
        tri << QPoint(c.x() - 11, c.y() - 16)
            << QPoint(c.x() - 11, c.y() + 16)
            << QPoint(c.x() + 18, c.y());
        p.setBrush(QColor(255, 255, 255, 170));
        p.setPen(Qt::NoPen);
        p.drawPolygon(tri);

        if (!caption.isEmpty()) {
            p.setPen(QColor(255, 255, 255, 140));
            QRect textRect(0, c.y() + r + 16, width(), 24);
            p.drawText(textRect, Qt::AlignHCenter | Qt::AlignTop,
                       fontMetrics().elidedText(caption, Qt::ElideMiddle,
                                                width() - 40));
        }
    }

private:
    QImage  frame;
    QString caption = "Drop a file here or press Ctrl+O";
    bool    showOverlay = true;
};

// ---------------------------------------------------------------------------
// Player — main window.
// ---------------------------------------------------------------------------

class Player : public QMainWindow {
public:
    Player() {
        setAcceptDrops(true);
        setStyleSheet(
            "QMainWindow, QWidget#controls { background: #1b1b1f; }"
            "QMenuBar { background: #1b1b1f; color: #dcdcdc; }"
            "QMenuBar::item:selected { background: #34343c; }"
            "QMenu { background: #26262c; color: #dcdcdc;"
            "        border: 1px solid #34343c; }"
            "QMenu::item { padding: 5px 28px 5px 20px; }"
            "QMenu::item:selected { background: #e8710a; color: white; }"
            "QMenu::separator { height: 1px; background: #34343c;"
            "                   margin: 4px 8px; }"
            "QStatusBar { background: #141417; color: #8b8b95; }"
            "QLabel { color: #b4b4be; }"
            "QToolButton {"
            "  background: transparent; border: none; border-radius: 4px;"
            "  padding: 6px;"
            "}"
            "QToolButton:hover { background: #34343c; }"
            "QToolButton:pressed { background: #26262c; }"
            "QSlider::groove:horizontal {"
            "  height: 4px; background: #3a3a44; border-radius: 2px;"
            "}"
            "QSlider::sub-page:horizontal {"
            "  background: #e8710a; border-radius: 2px;"
            "}"
            "QSlider::handle:horizontal {"
            "  background: #f28a2e; width: 12px; height: 12px;"
            "  margin: -4px 0; border-radius: 6px;"
            "}"
            "QSlider::handle:horizontal:hover { background: #ffa050; }"
        );

        buildActions();
        buildMenus();

        auto *central = new QWidget;
        auto *root = new QVBoxLayout(central);
        root->setContentsMargins(0, 0, 0, 0);
        root->setSpacing(0);

        // Video area
        video = new VideoWidget;
        video->onClick = [this] { if (playing) togglePause(); };
        video->onDoubleClick = [this] { toggleFullscreen(); };
        root->addWidget(video, 1);

        // Controls (seek bar + buttons), grouped so they hide in fullscreen
        controls = new QWidget;
        controls->setObjectName("controls");
        auto *cl = new QVBoxLayout(controls);
        cl->setContentsMargins(12, 8, 12, 8);
        cl->setSpacing(4);

        auto *seekRow = new QHBoxLayout;
        curLabel = new QLabel("00:00");
        durLabel = new QLabel("00:00");
        position = new QSlider(Qt::Horizontal);
        position->setRange(0, 1000);
        seekRow->addWidget(curLabel);
        seekRow->addWidget(position, 1);
        seekRow->addWidget(durLabel);
        cl->addLayout(seekRow);

        auto *btnRow = new QHBoxLayout;
        btnRow->setSpacing(4);
        openBtn  = makeButton(actOpen);
        playBtn  = makeButton(actPlay);
        stopBtn  = makeButton(actStop);
        fullBtn  = makeButton(actFull);
        btnRow->addWidget(playBtn);
        btnRow->addWidget(stopBtn);
        btnRow->addSpacing(8);
        btnRow->addWidget(openBtn);
        btnRow->addStretch();
        btnRow->addWidget(fullBtn);
        cl->addLayout(btnRow);

        root->addWidget(controls);
        setCentralWidget(central);
        statusBar()->showMessage("Ready");

        setWindowTitle("Player");
        resize(960, 620);

        // Seeking: restart the process at the chosen offset on release.
        connect(position, &QSlider::sliderPressed, this,
                [this] { seeking = true; });
        connect(position, &QSlider::sliderMoved, this, [this](int v) {
            if (durationSecs > 0)
                curLabel->setText(fmtTime(durationSecs * v / 1000.0));
        });
        connect(position, &QSlider::sliderReleased, this, [this] {
            seeking = false;
            if (durationSecs > 0 && !currentPath.isEmpty())
                startPlayback(durationSecs * position->value() / 1000.0);
        });

        // QProcess signals
        connect(&proc, &QProcess::started, this, [this] {
            statusBar()->showMessage("Playing: " + QFileInfo(currentPath).fileName());
        });
        connect(&proc, &QProcess::errorOccurred, this,
                [this](QProcess::ProcessError err) {
            statusBar()->showMessage(
                QString("Error: %1 (%2)").arg(proc.errorString()).arg(int(err)));
        });
        connect(&proc,
                QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, [this](int code, QProcess::ExitStatus st) {
            playing = false;
            paused = false;
            updatePlayAction();
            if (st == QProcess::CrashExit)
                statusBar()->showMessage("Playback crashed");
            else if (code != 0)
                statusBar()->showMessage(QString("Failed (exit %1)").arg(code));
            else {
                statusBar()->showMessage("Finished");
                if (durationSecs > 0) {
                    position->setValue(1000);
                    curLabel->setText(durLabel->text());
                }
            }
        });
        connect(&proc, &QProcess::readyReadStandardError, this,
                [this] { parseFfmpegOutput(proc.readAllStandardError()); });

        updatePlayAction();
    }

    ~Player() override { stopAll(); }

protected:
    void dragEnterEvent(QDragEnterEvent *e) override {
        if (e->mimeData()->hasUrls()) e->acceptProposedAction();
    }
    void dropEvent(QDropEvent *e) override {
        const auto urls = e->mimeData()->urls();
        if (!urls.isEmpty() && urls.first().isLocalFile())
            openPath(urls.first().toLocalFile());
    }
    void keyPressEvent(QKeyEvent *e) override {
        if (e->key() == Qt::Key_Escape && isFullScreen()) toggleFullscreen();
        else QMainWindow::keyPressEvent(e);
    }

private:
    // Widgets
    VideoWidget *video   = nullptr;
    QWidget     *controls = nullptr;
    QSlider     *position = nullptr;
    QLabel      *curLabel = nullptr;
    QLabel      *durLabel = nullptr;
    QToolButton *openBtn = nullptr, *playBtn = nullptr,
                *stopBtn = nullptr, *fullBtn = nullptr;
    QAction *actOpen = nullptr, *actPlay = nullptr, *actStop = nullptr,
            *actFull = nullptr, *actQuit = nullptr;

    // State
    QProcess proc;
    QString  currentPath;
    double   durationSecs = 0;
    bool     playing = false;
    bool     paused  = false;
    bool     seeking = false;

    // ---- UI construction --------------------------------------------------

    void buildActions() {
        auto *st = style();
        actOpen = new QAction(st->standardIcon(QStyle::SP_DialogOpenButton),
                              "&Open File...", this);
        actOpen->setShortcut(QKeySequence::Open);
        connect(actOpen, &QAction::triggered, this, &Player::openFile);

        actPlay = new QAction(st->standardIcon(QStyle::SP_MediaPlay),
                              "&Play", this);
        actPlay->setShortcut(Qt::Key_Space);
        connect(actPlay, &QAction::triggered, this, &Player::togglePause);

        actStop = new QAction(st->standardIcon(QStyle::SP_MediaStop),
                              "&Stop", this);
        actStop->setShortcut(Qt::Key_S);
        connect(actStop, &QAction::triggered, this, &Player::stopAll);

        actFull = new QAction(st->standardIcon(QStyle::SP_TitleBarMaxButton),
                              "&Fullscreen", this);
        actFull->setShortcut(Qt::Key_F);
        connect(actFull, &QAction::triggered, this, &Player::toggleFullscreen);

        actQuit = new QAction("&Quit", this);
        actQuit->setShortcut(QKeySequence::Quit);
        connect(actQuit, &QAction::triggered, this, &QWidget::close);

        // Shortcuts must work while the menu bar is hidden (fullscreen).
        for (QAction *a : {actOpen, actPlay, actStop, actFull, actQuit})
            addAction(a);
    }

    void buildMenus() {
        auto *media = menuBar()->addMenu("&Media");
        media->addAction(actOpen);
        media->addSeparator();
        media->addAction(actQuit);

        auto *playback = menuBar()->addMenu("&Playback");
        playback->addAction(actPlay);
        playback->addAction(actStop);

        auto *view = menuBar()->addMenu("&View");
        view->addAction(actFull);
    }

    QToolButton *makeButton(QAction *a) {
        auto *b = new QToolButton;
        b->setDefaultAction(a);
        b->setIconSize(QSize(20, 20));
        b->setToolButtonStyle(Qt::ToolButtonIconOnly);
        b->setAutoRaise(true);
        return b;
    }

    void updatePlayAction() {
        bool showPause = playing && !paused;
        actPlay->setIcon(style()->standardIcon(
            showPause ? QStyle::SP_MediaPause : QStyle::SP_MediaPlay));
        actPlay->setText(showPause ? "&Pause" : "&Play");
    }

    // ---- Actions ----------------------------------------------------------

    void toggleFullscreen() {
        bool fs = !isFullScreen();
        menuBar()->setVisible(!fs);
        controls->setVisible(!fs);
        statusBar()->setVisible(!fs);
        if (fs) showFullScreen(); else showNormal();
    }

    void openFile() {
        QString path = QFileDialog::getOpenFileName(
            this, "Open media", QString(),
            "Media (*.avi *.mkv *.mp4 *.wav *.mp3 *.mov);;All files (*)");
        if (!path.isEmpty()) openPath(path);
    }

    void openPath(const QString &path) {
        stopAll();
        currentPath = path;
        durationSecs = 0;
        durLabel->setText("00:00");
        setWindowTitle(QFileInfo(path).fileName() + " - Player");
        video->setCaption(QFileInfo(path).fileName());
        startPlayback(0);
    }

    void startPlayback(double startSecs) {
        if (proc.state() != QProcess::NotRunning) {
            proc.kill();
            proc.waitForFinished(1000);
        }

        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("LD_LIBRARY_PATH", "/usr/local/lib");
        proc.setProcessEnvironment(env);

        QString prog = "/usr/local/bin/ffmpeg";
        QStringList args;
        if (startSecs > 0)
            args << "-ss" << QString::number(startSecs, 'f', 3);
        args << "-i" << currentPath << "-f" << "null" << "-";

        proc.start(prog, args);
        if (!proc.waitForStarted(3000)) {
            statusBar()->showMessage("Could not start ffmpeg: " + proc.errorString());
            return;
        }

        video->clearFrame();
        playing = true;
        paused = false;
        updatePlayAction();
    }

    void togglePause() {
        if (!playing) {
            if (!currentPath.isEmpty()) startPlayback(0);
            else openFile();
            return;
        }
        qint64 pid = proc.processId();
        if (pid <= 0) return;
        paused = !paused;
        ::kill(pid_t(pid), paused ? SIGSTOP : SIGCONT);
        statusBar()->showMessage(paused ? "Paused" : "Playing: " +
                                 QFileInfo(currentPath).fileName());
        updatePlayAction();
    }

    void stopAll() {
        if (proc.state() != QProcess::NotRunning) {
            if (paused) ::kill(pid_t(proc.processId()), SIGCONT);
            proc.kill();
            proc.waitForFinished(1000);
        }
        playing = false;
        paused = false;
        video->clearFrame();
        position->setValue(0);
        curLabel->setText("00:00");
        updatePlayAction();
        statusBar()->showMessage("Stopped");
    }

    // ---- ffmpeg output -> duration / position -----------------------------

    static double toSecs(const QRegularExpressionMatch &m) {
        return m.captured(1).toInt() * 3600 + m.captured(2).toInt() * 60 +
               m.captured(3).toDouble();
    }

    void parseFfmpegOutput(const QByteArray &raw) {
        const QString text = QString::fromUtf8(raw);

        // Raw output still goes to the terminal for debugging.
        qInfo().noquote() << text.trimmed();

        static const QRegularExpression durRe(
            R"(Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?))");
        static const QRegularExpression timeRe(
            R"(time=\s*(\d+):(\d+):(\d+(?:\.\d+)?))");

        auto d = durRe.match(text);
        if (d.hasMatch()) {
            durationSecs = toSecs(d);
            durLabel->setText(fmtTime(durationSecs));
        }

        double last = -1;
        auto it = timeRe.globalMatch(text);
        while (it.hasNext()) last = toSecs(it.next());

        if (last >= 0 && !seeking) {
            curLabel->setText(fmtTime(last));
            if (durationSecs > 0)
                position->setValue(int(qBound(0.0, last / durationSecs, 1.0) * 1000));
        }
    }

    static QString fmtTime(double secsF) {
        int secs = int(secsF);
        int h = secs / 3600, m = (secs / 60) % 60, s = secs % 60;
        if (h > 0)
            return QString("%1:%2:%3").arg(h)
                .arg(m, 2, 10, QChar('0')).arg(s, 2, 10, QChar('0'));
        return QString("%1:%2").arg(m, 2, 10, QChar('0'))
                               .arg(s, 2, 10, QChar('0'));
    }
};

int main(int argc, char **argv) {
    qputenv("LD_LIBRARY_PATH", "/usr/local/lib");
    QApplication app(argc, argv);
    Player p;
    p.show();
    return app.exec();
}
