import QtQuick
import qs.services

// A sparkline of recent values (newest on the right), with a soft fill underneath
Canvas {
    id: root

    property var values: []
    property real max: 1
    property color accent: Theme.primary

    onValuesChanged: requestPaint()
    onMaxChanged: requestPaint()
    onAccentChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        // copy into a plain array: lists coming from C++ services can't be spread
        const v = [];
        for (let i = 0; i < (root.values?.length ?? 0); i++)
            v.push(Number(root.values[i]) || 0);
        if (v.length < 2)
            return;
        const top = Math.max(root.max, ...v) || 1;
        const step = width / (v.length - 1);
        const pt = i => [i * step, height - 2 - (v[i] / top) * (height - 4)];
        ctx.beginPath();
        ctx.moveTo(...pt(0));
        for (let i = 1; i < v.length; i++)
            ctx.lineTo(...pt(i));
        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        ctx.strokeStyle = root.accent;
        ctx.stroke();
        ctx.lineTo(width, height);
        ctx.lineTo(0, height);
        ctx.closePath();
        const g = ctx.createLinearGradient(0, 0, 0, height);
        g.addColorStop(0, Qt.alpha(root.accent, 0.28));
        g.addColorStop(1, Qt.alpha(root.accent, 0));
        ctx.fillStyle = g;
        ctx.fill();
    }
}
